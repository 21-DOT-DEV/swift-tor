//
//  TorClient.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import libtor

/// Actor-isolated driver for a single embedded Tor instance.
///
/// `TorClient` is swift-tor's primary entry point: one actor per Tor
/// instance, strict Swift-concurrency isolation of all mutable state,
/// and a high-level API that hides the dedicated `tor_run_main()`
/// background thread, the embedded pre-authenticated control socket,
/// and the `AsyncStream` fan-out of lifecycle events.
///
/// ### Basic usage
///
/// ```swift
/// let client = TorClient(configuration: .ephemeral())
/// try await client.start()
/// try await client.waitUntilBootstrapped()
/// print("SOCKS reachable at \(await client.socksEndpoint!)")
/// let control = try await client.control()
/// let service = try await control.addOnion(
///     key: .newV3(discardPrivateKey: true),
///     ports: [.toLocalPort(80, localPort: 8080)]
/// )
/// await client.stop()
/// ```
///
/// ### Thread model
///
/// Tor's C entry point `tor_run_main()` is a blocking, single-threaded
/// event loop that runs for the lifetime of the Tor instance. `TorClient`
/// pins that loop to a dedicated `Thread` so the Swift concurrency
/// runtime stays free for application work; actor isolation on every
/// mutable property (``state``, ``socksEndpoint``, the control client,
/// the event-continuation map) serialises callers without blocking the
/// Tor thread. Cross-thread bootstrapping happens through a
/// `CheckedContinuation` in ``start()``.
///
/// - Note: Conformance is `Sendable` via actor isolation; no
///   `@unchecked` escape hatches. Pairs with ``TorSession`` for
///   dependency injection (see ``TorSession`` for test-double guidance).
/// - Important: A single `TorClient` owns its `configuration.dataDirectory`
///   for the session. Constructing two clients pointed at the same data
///   directory will fail the second one with ``TorError/startFailed(_:)``
///   due to Tor's lockfile.
///
/// ## Topics
///
/// ### Creating
/// - ``init(configuration:)``
/// - ``init()``
///
/// ### Lifecycle
/// - ``start()``
/// - ``stop()``
/// - ``waitUntilBootstrapped(timeout:)``
///
/// ### Observing
/// - ``state``
/// - ``socksEndpoint``
/// - ``events``
///
/// ### Control access
/// - ``control()``
/// - ``configuration``
public actor TorClient {
    
    /// The immutable ``TorConfiguration`` snapshot used to start Tor.
    ///
    /// Captured at construction time and frozen for the life of this
    /// actor — mutating the original ``TorConfiguration`` after
    /// construction has no effect on a running session. To apply new
    /// configuration, call ``stop()`` and construct a fresh `TorClient`.
    ///
    /// - Stability: immutable (`let`), safe to read from any task.
    public let configuration: TorConfiguration
    
    /// Current lifecycle state, isolated to the actor.
    ///
    /// Reads require `await` to cross the actor boundary; writes happen
    /// only inside ``start()`` / ``stop()`` / ``waitUntilBootstrapped(timeout:)``
    /// and their helpers. Observers that need near-real-time updates
    /// without polling should consume ``events`` for
    /// ``TorEvent/stateChanged(_:)``.
    ///
    /// - Stability: follows the transition graph documented on
    ///   ``TorState``; default is ``TorState/idle``.
    public private(set) var state: TorState = .idle
    
    /// Tor's local SOCKS5 proxy endpoint once start succeeds, else `nil`.
    ///
    /// Populated by `discoverSocksPort()` via the `GETINFO
    /// net/listeners/socks` control-protocol key (control-spec.txt
    /// §3.9). Remains `nil` until Tor reaches ``TorState/running`` AND
    /// the port discovery completes; reverts to `nil` on ``stop()``.
    ///
    /// - Typical value: `HostPort(host: "127.0.0.1", port: <ephemeral>)`
    ///   when `configuration.socksPort == .ephemeral`, or the literal
    ///   fixed port when `.fixed(n)` was requested.
    /// - Important: Do not hand this endpoint to client code before
    ///   ``waitUntilBootstrapped(timeout:)`` succeeds — the SOCKS listener
    ///   is reachable immediately, but traffic will fail with
    ///   `Proxy connection refused` until bootstrap reaches 100%.
    public private(set) var socksEndpoint: HostPort?
    
    /// The control socket file descriptor.
    private var controlSocketFD: Int32 = -1
    
    /// The dedicated thread running Tor.
    private var torThread: Thread?
    
    /// The control client instance.
    private var controlClient: TorControlClient?
    
    /// Event continuation for broadcasting events.
    private var eventContinuations: [UUID: AsyncStream<TorEvent>.Continuation] = [:]
    
    /// Create a client bound to a specific ``TorConfiguration``.
    ///
    /// No work is performed at construction — the Tor process is not
    /// launched until ``start()`` is called. Keep construction cheap so
    /// dependency-injection frameworks can wire a `TorClient` without
    /// paying a startup cost.
    ///
    /// - Parameter configuration: The configuration snapshot to use.
    ///   See ``TorConfiguration/ephemeral(cacheDirectory:)`` for a
    ///   zero-residue default or ``TorConfiguration/init(dataDirectory:cacheDirectory:socksPort:cookieAuthentication:controlPassword:extraArgs:ownsDataDirectory:)``
    ///   for a fully-specified configuration.
    ///
    /// - Note: The configuration is copied by value into ``configuration``;
    ///   the caller's original struct is unaffected by later mutations
    ///   to this actor.
    public init(configuration: TorConfiguration) {
        self.configuration = configuration
    }
    
    /// Convenience initialiser using ``TorConfiguration/makeDefault()``.
    ///
    /// Useful for one-liner demos and quick test harnesses: generates a
    /// fresh UUID-suffixed temp `dataDirectory`, defaults SOCKS port to
    /// ephemeral, and leaves `ownsDataDirectory` off. The resulting
    /// session will leave state on disk after ``stop()`` — prefer
    /// ``init(configuration:)`` with ``TorConfiguration/ephemeral(cacheDirectory:)``
    /// for self-cleaning deployments.
    ///
    /// - Note: Equivalent to `TorClient(configuration: .makeDefault())`.
    public init() {
        self.configuration = TorConfiguration.makeDefault()
    }
    
    // MARK: - Lifecycle
    
    /// Start the embedded Tor process.
    ///
    /// Orchestrates the cross-thread dance that brings Tor up:
    /// 1. Create ``TorConfiguration/dataDirectory`` (and parents) with
    ///    `FileManager.createDirectory(atPath:withIntermediateDirectories:)`.
    /// 2. Call `tor_main_configuration_new()`, stamp the configuration
    ///    with our torrc-equivalent argv, and hand it
    ///    `tor_main_configuration_setup_control_socket()` to obtain a
    ///    pre-authenticated embedded control socket.
    /// 3. Post `tor_run_main()` to a dedicated `Thread`; bridge its
    ///    synchronous startup back to the actor with a
    ///    `CheckedContinuation`.
    /// 4. Bind a ``TorControlClient`` to the socket and populate
    ///    ``socksEndpoint`` via `GETINFO net/listeners/socks`
    ///    (control-spec.txt §3.9).
    ///
    /// Resolves once steps 1–4 complete, at which point ``state``
    /// advances to ``TorState/running``. Bootstrap progress is still in
    /// flight — pair with ``waitUntilBootstrapped(timeout:)`` to block
    /// until Tor is actually ready to carry user traffic.
    ///
    /// - Throws: ``TorError/alreadyStarted`` when ``state`` is
    ///   ``TorState/starting``, ``TorState/running``, or
    ///   ``TorState/stopping``; ``TorError/startFailed(_:)`` when
    ///   `tor_run_main()` returns non-zero or the argv is rejected.
    ///
    /// - Important: This method is idempotent only for terminal states
    ///   (``TorState/idle``, ``TorState/stopped``, ``TorState/failed(_:)``);
    ///   double-starting while ``state`` is transient throws.
    public func start() async throws {
        switch state {
        case .idle, .stopped, .failed:
            break // Allow start
        case .starting, .running, .stopping:
            throw TorError.alreadyStarted
        }
        
        state = .starting
        broadcastEvent(.stateChanged(.starting))
        
        // Create data directory
        try FileManager.default.createDirectory(
            atPath: configuration.dataDirectory,
            withIntermediateDirectories: true
        )
        
        // Start Tor on a dedicated thread using a continuation to bridge
        let controlFD = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            let config = self.configuration
            
            // Use a class to safely pass mutable state across thread boundary
            final class TorThreadContext: @unchecked Sendable {
                var controlFD: Int32 = -1
                var exitCode: Int32 = 0
                var continuationResumed = false
                let lock = NSLock()
                
                func resumeOnce(_ continuation: CheckedContinuation<Int32, Error>) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !continuationResumed else { return }
                    continuationResumed = true
                    continuation.resume(returning: controlFD)
                }
                
                func resumeWithError(_ continuation: CheckedContinuation<Int32, Error>, _ error: Error) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !continuationResumed else { return }
                    continuationResumed = true
                    continuation.resume(throwing: error)
                }
            }
            
            let context = TorThreadContext()
            
            self.torThread = Thread {
                guard let torConfig = tor_main_configuration_new() else {
                    context.resumeWithError(continuation, TorError.startFailed("Failed to create Tor configuration"))
                    return
                }
                
                // Get control socket BEFORE starting Tor
                context.controlFD = tor_main_configuration_setup_control_socket(torConfig)
                
                // Build arguments
                let args = config.buildArguments()
                
                // Convert to C strings
                let cArgs = args.map { strdup($0) }
                defer { cArgs.forEach { free($0) } }
                
                var argv: [UnsafeMutablePointer<CChar>?] = cArgs.map { $0 }
                let argc = Int32(argv.count)
                
                // Set command line
                argv.withUnsafeMutableBufferPointer { buffer in
                    _ = tor_main_configuration_set_command_line(torConfig, argc, buffer.baseAddress)
                }
                
                // Signal that control FD is ready
                context.resumeOnce(continuation)
                
                // Run Tor (blocks until exit)
                context.exitCode = tor_run_main(torConfig)
                tor_main_configuration_free(torConfig)
            }
            
            self.torThread?.name = "TorClient.torThread"
            self.torThread?.start()
        }
        
        // Store control socket
        self.controlSocketFD = controlFD
        
        // Wait a moment for Tor to initialize
        try await Task.sleep(for: .milliseconds(500))
        
        Self.sanitizeFileDescriptorLimit()
        
        // Create control client
        if controlSocketFD >= 0 {
            controlClient = TorControlClient(
                fileDescriptor: controlSocketFD,
                preAuthenticated: true,
                dataDirectory: configuration.dataDirectory
            )
        }
        
        // Discover SOCKS port
        await discoverSocksPort()
        
        state = .running
        broadcastEvent(.stateChanged(.running))
    }
    
    /// Stop the Tor instance and release all associated resources.
    ///
    /// Best-effort, non-throwing: if ``state`` is already ``TorState/idle``,
    /// ``TorState/stopped``, or ``TorState/failed(_:)`` the call is a
    /// no-op. Otherwise, the shutdown sequence:
    /// 1. Advances ``state`` to ``TorState/stopping`` and broadcasts a
    ///    corresponding ``TorEvent/stateChanged(_:)``.
    /// 2. Sends `SIGNAL SHUTDOWN` over the control socket
    ///    (control-spec.txt §3.7) via ``TorControlClient/shutdown()``.
    /// 3. Polls the Tor thread for up to **10 seconds** at 100 ms
    ///    intervals, then `Thread.cancel()`s if the thread is still
    ///    executing.
    /// 4. Releases the control client, closes the FD, and clears
    ///    ``socksEndpoint``.
    /// 5. If `configuration.ownsDataDirectory` is `true`, removes the
    ///    data directory best-effort (errors are swallowed).
    /// 6. Advances ``state`` to ``TorState/stopped`` and finishes every
    ///    outstanding ``events`` continuation.
    ///
    /// - Important: The 10 s grace window is deliberately shorter than
    ///   Tor's default `ShutdownWaitLength` (30 s) to bound the wait on
    ///   misbehaving Tor builds; `Thread.cancel()` after that window is
    ///   a best-effort unwind, not a guaranteed teardown.
    /// - Note: After resolution the `TorClient` is reusable — a
    ///   subsequent ``start()`` re-enters ``TorState/starting`` with a
    ///   fresh data directory when the configuration specifies an
    ///   ephemeral path.
    public func stop() async {
        guard state == .running || state == .starting else {
            return
        }
        
        state = .stopping
        broadcastEvent(.stateChanged(.stopping))
        
        // Send shutdown signal via control
        if let control = controlClient {
            try? await control.shutdown()
        }
        
        // Wait for thread to finish (with timeout)
        let deadline = Date().addingTimeInterval(10)
        while torThread?.isExecuting == true && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        // Force cancel if still running
        if torThread?.isExecuting == true {
            torThread?.cancel()
        }
        
        cleanup()
        
        // Clean up owned data directory (e.g., from `TorConfiguration.ephemeral()`).
        // Best-effort: ignored if the directory is already gone or unwritable.
        if configuration.ownsDataDirectory {
            try? FileManager.default.removeItem(atPath: configuration.dataDirectory)
        }
        
        state = .stopped
        broadcastEvent(.stateChanged(.stopped))
    }
    
    /// Block until Tor reports 100% bootstrap, or fail after `timeout`.
    ///
    /// Polls the Tor control protocol once per second using
    /// ``TorControlClient/getBootstrapStatus()`` and emits each observed
    /// phase as ``TorEvent/bootstrap(progress:tag:summary:)`` on
    /// ``events``. Resolves successfully on the first reading with
    /// `status.isComplete`; throws ``TorError/timeout`` if the
    /// `ContinuousClock` deadline elapses first.
    ///
    /// Uses `ContinuousClock` rather than `Date` so the timeout is
    /// immune to wall-clock jumps during bootstrap (DST transitions,
    /// manual clock changes). Bootstrap progress is monotonic, so
    /// subscribers may replace prior UI without reordering concerns.
    ///
    /// - Parameter timeout: Maximum time to wait. Defaults to 2 minutes.
    /// - Throws: ``TorError/notStarted`` when ``state`` is neither
    ///   ``TorState/running`` nor ``TorState/starting``;
    ///   ``TorError/controlUnavailable`` when the control client has
    ///   not bound; ``TorError/timeout`` when the deadline elapses.
    ///
    /// - Note: Cold-boot bootstraps typically complete in 30–60 seconds;
    ///   warm-cache bootstraps (see ``TorConfiguration/cacheDirectory``)
    ///   in 5–10 seconds. Choose `timeout` with appropriate headroom.
    public func waitUntilBootstrapped(timeout: Duration = .seconds(120)) async throws {
        guard state == .running || state == .starting else {
            throw TorError.notStarted
        }
        
        guard let control = controlClient else {
            throw TorError.controlUnavailable
        }
        
        let deadline = ContinuousClock.now + timeout
        
        while ContinuousClock.now < deadline {
            if let status = try? await control.getBootstrapStatus() {
                broadcastEvent(.bootstrap(
                    progress: status.progress,
                    tag: status.tag,
                    summary: status.summary
                ))
                
                if status.isComplete {
                    return
                }
            }
            
            try await Task.sleep(for: .seconds(1))
        }
        
        throw TorError.timeout
    }
    
    // MARK: - Control Access
    
    /// Return the ``TorControlClient`` bound to this Tor instance.
    ///
    /// Hands out the shared, pre-authenticated control client that
    /// swift-tor creates during ``start()``. Use it for advanced
    /// operations the high-level API does not expose: `GETINFO` queries
    /// beyond the curated list, raw `SETEVENTS` subscriptions, onion-
    /// service management (``TorControlClient/addOnion(key:ports:detach:)``),
    /// and Tor signals (`NEWNYM`, `DUMP`, etc.).
    ///
    /// - Returns: The shared ``TorControlClient``. The same instance is
    ///   returned across calls for the life of the session.
    /// - Throws: ``TorError/controlUnavailable`` when Tor is not running
    ///   or the control socket failed to authenticate during start.
    ///
    /// - Important: The returned client is owned by this `TorClient`.
    ///   Do not close its socket manually — that is handled by
    ///   ``stop()``. Calling control commands concurrently is safe;
    ///   commands are serialised at the socket layer.
    public func control() throws -> TorControlClient {
        guard let client = controlClient else {
            throw TorError.controlUnavailable
        }
        return client
    }
    
    // MARK: - Events
    
    /// Fresh fan-out `AsyncStream` of ``TorEvent`` values.
    ///
    /// Every access returns a new subscriber stream; swift-tor
    /// multiplexes each yielded ``TorEvent`` to all live subscribers, so
    /// two consumers see identical sequences. Surfaces:
    ///
    /// - ``TorEvent/bootstrap(progress:tag:summary:)`` as
    ///   ``waitUntilBootstrapped(timeout:)`` polls.
    /// - ``TorEvent/stateChanged(_:)`` on every ``state`` transition.
    /// - ``TorEvent/log(level:message:)``, ``TorEvent/circuit(id:status:)``,
    ///   and ``TorEvent/stream(id:status:target:)`` when the caller has
    ///   subscribed the corresponding raw events via
    ///   ``TorControlClient/subscribe(to:)``.
    ///
    /// - Important: Streams have **no replay**. Subscribers that start
    ///   after bootstrap completion will not see prior
    ///   ``TorEvent/bootstrap(progress:tag:summary:)`` values; read
    ///   ``state`` for the initial snapshot when opening the iterator.
    /// - Note: The stream completes exactly once, in ``stop()``, when
    ///   all continuations are finished.
    public var events: AsyncStream<TorEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task {
                await self.addEventContinuation(id: id, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.removeEventContinuation(id: id)
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func cleanup() {
        controlClient = nil
        controlSocketFD = -1
        torThread = nil
        socksEndpoint = nil
        
        // Finish all event streams
        for continuation in eventContinuations.values {
            continuation.finish()
        }
        eventContinuations.removeAll()
    }
    
    private func discoverSocksPort() async {
        // Try via control protocol (most reliable)
        for _ in 0..<20 {
            if let control = controlClient,
               let address = try? await control.getInfo("net/listeners/socks") {
                // Parse "127.0.0.1:9050" or "unix:/path" format
                let cleaned = address.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if cleaned.hasPrefix("unix:") {
                    // Unix socket - not supported for HostPort
                    break
                }
                let parts = cleaned.split(separator: ":")
                if parts.count == 2,
                   let port = Int(parts[1]) {
                    socksEndpoint = HostPort(host: String(parts[0]), port: port)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        
        // Fall back to configured port if fixed
        if case .fixed(let port) = configuration.socksPort {
            socksEndpoint = HostPort.localhost(port)
        }
    }
    
    private func addEventContinuation(id: UUID, continuation: AsyncStream<TorEvent>.Continuation) {
        eventContinuations[id] = continuation
    }
    
    private func removeEventContinuation(id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }
    
    private func broadcastEvent(_ event: TorEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }
    
    /// Sanitize the process file descriptor soft limit after Tor initialization.
    ///
    /// Tor's `set_max_file_descriptors()` raises `rlim_cur` to `rlim_max`.
    /// On macOS, `rlim_max` is `RLIM_INFINITY` (`0x7FFFFFFFFFFFFFFF`).
    /// C code that casts `rlim_t` (uint64) to `int` will silently truncate
    /// this to -1, causing "Not enough file descriptors" errors.
    ///
    /// We cap the soft limit at `kern.maxfilesperproc` (macOS) or 10240
    /// (Linux fallback) — safe for both Tor (which tracks its own FD budget
    /// internally) and any other code sharing the process.
    private static func sanitizeFileDescriptorLimit() {
        #if !os(Windows)
        // On Linux/Glibc, `RLIMIT_NOFILE` imports as `__rlimit_resource` (an enum),
        // but `getrlimit`/`setrlimit` expect `__rlimit_resource_t` (Int32). On Darwin
        // it's already Int32, so the cast is a no-op.
        #if canImport(Glibc) || canImport(Musl)
        // `RLIMIT_NOFILE` is imported as `__rlimit_resource` (enum); the syscalls
        // expect `__rlimit_resource_t` which is `Int32`.
        let resource = Int32(RLIMIT_NOFILE.rawValue)
        #else
        let resource = RLIMIT_NOFILE
        #endif
        var rlim = rlimit()
        guard getrlimit(resource, &rlim) == 0 else { return }
        guard rlim.rlim_cur > rlim_t(Int32.max) else { return }
        // sysconf(_SC_OPEN_MAX) returns rlim_cur — already poisoned.
        // Query the actual kernel per-process file limit instead.
        #if canImport(Darwin)
        var maxFiles: Int32 = 10240
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.maxfilesperproc", &maxFiles, &size, nil, 0)
        let cap = rlim_t(maxFiles > 0 ? maxFiles : 10240)
        #else
        let cap: rlim_t = 10240
        #endif
        rlim.rlim_cur = cap
        setrlimit(resource, &rlim)
        #endif
    }
}
