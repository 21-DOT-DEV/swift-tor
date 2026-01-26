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

/// Main actor for managing an embedded Tor instance.
///
/// `TorClient` provides a high-level Swift Concurrency interface for:
/// - Starting and stopping Tor
/// - Monitoring bootstrap progress
/// - Accessing the SOCKS proxy endpoint
/// - Managing the control connection
///
/// ## Basic Usage
///
/// ```swift
/// let config = TorConfiguration.makeDefault()
/// let client = TorClient(configuration: config)
///
/// try await client.start()
/// try await client.waitUntilBootstrapped()
///
/// print("SOCKS: \(client.socksEndpoint!)")
///
/// let control = try await client.control()
/// let service = try await control.addOnion(
///     key: .newV3(discardPrivateKey: true),
///     ports: [.toLocalPort(80, localPort: 8080)]
/// )
/// ```
///
/// ## Thread Model
///
/// Tor's `tor_run_main()` blocks until Tor exits. This actor runs it on a dedicated
/// background thread, keeping the Swift concurrency runtime free for other work.
public actor TorClient {
    
    /// The configuration for this Tor instance.
    public let configuration: TorConfiguration
    
    /// The current state of Tor.
    public private(set) var state: TorState = .idle
    
    /// The SOCKS proxy endpoint, available after Tor starts.
    public private(set) var socksEndpoint: HostPort?
    
    /// The control socket file descriptor.
    private var controlSocketFD: Int32 = -1
    
    /// The dedicated thread running Tor.
    private var torThread: Thread?
    
    /// The control client instance.
    private var controlClient: TorControlClient?
    
    /// Event continuation for broadcasting events.
    private var eventContinuations: [UUID: AsyncStream<TorEvent>.Continuation] = [:]
    
    /// Creates a Tor client with the specified configuration.
    /// - Parameter configuration: The Tor configuration to use.
    public init(configuration: TorConfiguration) {
        self.configuration = configuration
    }
    
    /// Creates a Tor client with default configuration.
    public init() {
        self.configuration = TorConfiguration.makeDefault()
    }
    
    // MARK: - Lifecycle
    
    /// Starts the Tor instance.
    ///
    /// This method:
    /// 1. Creates the data directory if needed
    /// 2. Sets up the control socket
    /// 3. Starts Tor on a dedicated background thread
    /// 4. Waits for the control socket to be ready
    ///
    /// - Throws: `TorError.alreadyStarted` if Tor is already running,
    ///           `TorError.startFailed` if Tor fails to start.
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
    
    /// Stops the Tor instance gracefully.
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
        
        state = .stopped
        broadcastEvent(.stateChanged(.stopped))
    }
    
    /// Waits until Tor has fully bootstrapped.
    ///
    /// - Parameter timeout: Maximum time to wait. Defaults to 2 minutes.
    /// - Throws: `TorError.timeout` if bootstrap doesn't complete in time,
    ///           `TorError.notStarted` if Tor isn't running.
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
    
    /// Gets the control client for advanced operations.
    ///
    /// - Returns: The `TorControlClient` for this Tor instance.
    /// - Throws: `TorError.controlUnavailable` if the control connection isn't available.
    public func control() throws -> TorControlClient {
        guard let client = controlClient else {
            throw TorError.controlUnavailable
        }
        return client
    }
    
    // MARK: - Events
    
    /// An async stream of events from this Tor instance.
    ///
    /// Events include:
    /// - Bootstrap progress updates
    /// - State changes
    /// - Log messages (if subscribed via control protocol)
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
}
