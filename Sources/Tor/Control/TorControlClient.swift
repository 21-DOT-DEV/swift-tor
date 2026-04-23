//
//  TorControlClient.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Synchronization

/// `Sendable` high-level client for Tor's control protocol
/// (control-spec.txt).
///
/// Wraps a ``ControlSocket`` and exposes a typed, `async` method per
/// control-protocol command family: authentication, `GETINFO`,
/// `SETCONF`, `SETEVENTS`, `SIGNAL`, `ADD_ONION` / `DEL_ONION`.
/// Every method sends exactly one command and awaits a single reply
/// (or an async event stream in the case of ``subscribe(to:)``),
/// translating reply codes into ``TorError`` cases and typed
/// payloads via ``ControlProtocolParser``.
///
/// Most callers never construct one directly — ``TorClient/start()``
/// creates a pre-authenticated instance and hands it out via
/// ``TorClient/control()``. Construct directly when driving a Tor
/// instance swift-tor did not launch (e.g. connecting to a
/// systemd-managed `tor` over its `ControlPort`).
///
/// ### Onion-service lifecycle
///
/// ``addOnion(key:ports:detach:)`` registers an onion service whose
/// lifetime is determined by the `detach` flag:
///
/// - `detach: false` — service is tied to **this** control connection
///   and is removed by Tor when the socket closes
///   (control-spec.txt §3.27).
/// - `detach: true` — service survives the control-socket closure and
///   only disappears on explicit ``delOnion(_:)-(String)`` or on Tor
///   process exit.
///
/// - Note: Conformance is `Sendable` (compiler-verified, no
///   `@unchecked`). Concurrent calls are safe and serialised at the
///   socket layer — commands execute in arrival order.
/// - Important: ``TorControlClient`` is authenticated at most once per
///   instance; subsequent calls to ``authenticate(password:)`` after
///   success are no-ops. For the embedded control socket
///   (``init(fileDescriptor:preAuthenticated:dataDirectory:)`` with
///   `preAuthenticated: true`) authentication is skipped entirely.
///
/// ## Topics
///
/// ### Creating
/// - ``init(socket:dataDirectory:)``
/// - ``init(fileDescriptor:preAuthenticated:dataDirectory:)``
/// - ``init(host:port:dataDirectory:)``
///
/// ### Authentication
/// - ``authenticate(password:)``
/// - ``isAuthenticated``
///
/// ### GETINFO
/// - ``getInfo(_:)-([String])``
/// - ``getInfo(_:)-(String)``
/// - ``getBootstrapStatus()``
///
/// ### Configuration & events
/// - ``setConf(_:)``
/// - ``subscribe(to:)``
///
/// ### Onion services
/// - ``addOnion(key:ports:detach:)``
/// - ``delOnion(_:)-(String)``
/// - ``delOnion(_:)-(OnionService)``
///
/// ### Signals
/// - ``signal(_:)``
/// - ``newIdentity()``
/// - ``shutdown()``
///
/// ### Escape hatch
/// - ``sendRaw(_:)``
public final class TorControlClient: Sendable {
    
    /// The underlying control socket.
    private let socket: ControlSocket
    
    /// Path to the data directory (for reading cookie file).
    private let dataDirectory: String?
    
    /// Mutex-guarded authentication flag. Migrated from a hand-rolled
    /// `ManagedAtomic<Bool>` helper to `Mutex<Bool>` from the `Synchronization`
    /// module (SE-0410) so the class conforms to `Sendable` without
    /// `@unchecked` escapes anywhere in the call graph.
    private let _isAuthenticated: Mutex<Bool>

    /// `true` once any successful `AUTHENTICATE` (or pre-auth
    /// construction) has marked this client ready.
    ///
    /// Becomes `true` after the first successful
    /// ``authenticate(password:)`` call or after
    /// ``init(fileDescriptor:preAuthenticated:dataDirectory:)`` with
    /// `preAuthenticated: true`. Never reverts to `false` within a
    /// single instance — discard the client and construct a new one to
    /// re-authenticate a socket from scratch.
    ///
    /// - Note: Reads race-safely with a concurrent
    ///   ``authenticate(password:)``; the underlying flag is
    ///   `Mutex<Bool>`-guarded (SE-0410).
    public var isAuthenticated: Bool {
        _isAuthenticated.withLock { $0 }
    }
    
    /// Wrap an existing ``ControlSocket``.
    ///
    /// The primary low-level initialiser. Use when the caller already
    /// has a ``ControlSocket`` in hand — typically because they
    /// constructed one from a TCP endpoint or are injecting a mock for
    /// tests. The socket may be freshly-connected or already
    /// authenticated externally.
    ///
    /// - Parameters:
    ///   - socket: The underlying transport. Ownership is shared;
    ///     the client does not close the socket on `deinit`.
    ///   - dataDirectory: Optional path to Tor's data directory. When
    ///     non-`nil`, ``authenticate(password:)`` will try cookie
    ///     authentication by reading `<dataDir>/control_auth_cookie`.
    ///
    /// - Note: Freshly constructed instances have
    ///   ``isAuthenticated`` = `false`. Callers must explicitly invoke
    ///   ``authenticate(password:)`` before issuing any other command.
    public init(socket: ControlSocket, dataDirectory: String? = nil) {
        self.socket = socket
        self.dataDirectory = dataDirectory
        self._isAuthenticated = Mutex<Bool>(false)
    }
    
    /// Wrap a raw file descriptor, optionally marking it as
    /// pre-authenticated.
    ///
    /// The primary embedded-mode initialiser. Swift-tor passes the FD
    /// returned by `tor_main_configuration_setup_control_socket()` with
    /// `preAuthenticated: true`, because the `tor_api` control socket
    /// is granted full control access without going through
    /// `AUTHENTICATE`.
    ///
    /// - Parameters:
    ///   - fileDescriptor: A valid, connected control-socket FD.
    ///   - preAuthenticated: When `true`, ``isAuthenticated`` starts
    ///     as `true` and ``authenticate(password:)`` is a no-op.
    ///     Defaults to `false`.
    ///   - dataDirectory: Optional path to Tor's data directory (for
    ///     cookie-based authentication on non-embedded sockets).
    ///
    /// - Important: The wrapper does **not** take ownership of the FD
    ///   (`ownsDescriptor: false` is passed to ``ControlSocket``).
    ///   Caller (usually ``TorClient/stop()``) is responsible for
    ///   closing the FD when the Tor instance exits.
    public init(fileDescriptor: Int32, preAuthenticated: Bool = false, dataDirectory: String? = nil) {
        self.socket = ControlSocket(fileDescriptor: fileDescriptor, ownsDescriptor: false)
        self.dataDirectory = dataDirectory
        self._isAuthenticated = Mutex<Bool>(preAuthenticated)
    }
    
    /// Open a TCP connection to a listening Tor control port and wrap
    /// it.
    ///
    /// Convenience for the external-Tor scenario: an already-running
    /// `tor` daemon is exposing its control port over TCP (typically
    /// `127.0.0.1:9051`) and swift-tor wants to drive it. The
    /// underlying ``ControlSocket`` owns the FD and closes it on
    /// `deinit`.
    ///
    /// - Parameters:
    ///   - host: IPv4 literal or DNS name of the control-port host.
    ///   - port: TCP port (typically 9051).
    ///   - dataDirectory: Optional path to the daemon's data
    ///     directory, used by ``authenticate(password:)`` for
    ///     cookie-based authentication.
    /// - Throws: ``TorError/ioError(_:)`` on socket/connect/DNS
    ///   failure propagated from ``ControlSocket/init(host:port:)``.
    ///
    /// - Important: The resulting client is **not authenticated**.
    ///   Call ``authenticate(password:)`` before any other command.
    public convenience init(host: String, port: Int, dataDirectory: String? = nil) throws {
        let socket = try ControlSocket(host: host, port: port)
        self.init(socket: socket, dataDirectory: dataDirectory)
    }
    
    // MARK: - Authentication
    
    /// Perform the `AUTHENTICATE` handshake (control-spec.txt §3.5).
    ///
    /// Tries up to three authentication methods, in order:
    /// 1. **Cookie** — if `dataDirectory` was provided and
    ///    `<dataDir>/control_auth_cookie` exists, the 32-byte cookie is
    ///    hex-encoded and sent as `AUTHENTICATE <hex>`.
    /// 2. **Password** — if a `password` argument is supplied, sent as
    ///    `AUTHENTICATE "<quoted password>"`. Requires Tor to be
    ///    configured with matching `HashedControlPassword`.
    /// 3. **Null** — as a last resort, sends bare `AUTHENTICATE`. Works
    ///    on sockets configured for no-auth (rare; also used by some
    ///    test harnesses).
    ///
    /// A no-op when ``isAuthenticated`` is already `true`.
    ///
    /// - Parameter password: Optional cleartext password, used only
    ///   for method (2). Ignored when cookie auth succeeds.
    /// - Throws: ``TorError/controlAuthFailed(_:)`` if every method
    ///   exhausted returns a non-success reply (Tor reply `515`).
    ///
    /// - Important: For embedded-mode control sockets constructed via
    ///   ``init(fileDescriptor:preAuthenticated:dataDirectory:)`` with
    ///   `preAuthenticated: true`, this method is a no-op and never
    ///   sends `AUTHENTICATE` on the wire.
    public func authenticate(password: String? = nil) async throws {
        if isAuthenticated {
            return
        }
        
        // Try cookie authentication first
        if let dataDir = dataDirectory {
            let cookiePath = (dataDir as NSString).appendingPathComponent("control_auth_cookie")
            if FileManager.default.fileExists(atPath: cookiePath),
               let cookieData = FileManager.default.contents(atPath: cookiePath) {
                let cookieHex = cookieData.map { String(format: "%02x", $0) }.joined()
                let reply = try await socket.sendCommand("AUTHENTICATE \(cookieHex)")
                
                if reply.isSuccess {
                    _isAuthenticated.withLock { $0 = true }
                    return
                }
            }
        }
        
        // Try password authentication
        if let password = password {
            let quotedPassword = "\"\(password.replacingOccurrences(of: "\"", with: "\\\""))\""
            let reply = try await socket.sendCommand("AUTHENTICATE \(quotedPassword)")
            
            if reply.isSuccess {
                _isAuthenticated.withLock { $0 = true }
                return
            }
            
            throw TorError.controlAuthFailed(reply.message)
        }
        
        // Try empty authentication (for control sockets that don't require auth)
        let reply = try await socket.sendCommand("AUTHENTICATE")
        
        if reply.isSuccess {
            _isAuthenticated.withLock { $0 = true }
            return
        }
        
        throw TorError.controlAuthFailed(reply.message)
    }
    
    // MARK: - GETINFO
    
    /// Issue a multi-key `GETINFO` command (control-spec.txt §3.9).
    ///
    /// Joins `keys` with spaces and sends `GETINFO k1 k2 …`. Tor replies
    /// with one `250-key=value` line per key; the response is parsed
    /// into a dictionary by ``ControlProtocolParser/parseGetInfoResponse(_:)``.
    ///
    /// - Parameter keys: Info keys to query (e.g. `["version",
    ///   "status/bootstrap-phase", "net/listeners/socks"]`).
    /// - Returns: Dictionary mapping each requested key to its
    ///   returned value. Missing keys are omitted (Tor responds with
    ///   an error reply in that case).
    /// - Throws: ``TorError/controlProtocolError(code:message:)`` for
    ///   non-success replies (e.g. 552 "unrecognized key"), or
    ///   ``TorError/invalidResponse(_:)`` on malformed output.
    ///
    /// - Note: For the full GETINFO key vocabulary see
    ///   control-spec.txt §3.9. swift-tor uses `version`,
    ///   `net/listeners/socks`, and `status/bootstrap-phase` most
    ///   frequently.
    public func getInfo(_ keys: [String]) async throws -> [String: String] {
        let command = "GETINFO \(keys.joined(separator: " "))"
        let reply = try await socket.sendCommand(command)
        return try ControlProtocolParser.parseGetInfoResponse(reply)
    }
    
    /// Convenience: issue `GETINFO` for a single key.
    ///
    /// Composes ``getInfo(_:)-([String])`` with a single-element
    /// array and looks up the key in the returned dictionary. Avoids
    /// the array boilerplate at call sites that want just one value.
    ///
    /// - Parameter key: The single info key to query.
    /// - Returns: The value string, or `nil` when Tor returned no
    ///   entry for that key.
    /// - Throws: Same errors as ``getInfo(_:)-([String])``.
    public func getInfo(_ key: String) async throws -> String? {
        let result = try await getInfo([key])
        return result[key]
    }
    
    /// Fetch and parse Tor's current bootstrap status.
    ///
    /// Queries `GETINFO status/bootstrap-phase` (control-spec.txt
    /// §3.9) and runs the returned value through
    /// ``ControlProtocolParser/parseBootstrapStatus(_:)``. Returns
    /// `nil` when Tor hasn't yet published a bootstrap phase (rare;
    /// typically observed immediately after ``TorClient/start()``
    /// resolves and before the Tor thread produces its first status).
    ///
    /// - Returns: A ``BootstrapStatus`` populated with the current
    ///   phase, or `nil` if the key is missing / unparsable.
    /// - Throws: Errors from ``getInfo(_:)-([String])``.
    ///
    /// - Note: ``TorClient/waitUntilBootstrapped(timeout:)`` calls
    ///   this method on a 1-second poll loop. Prefer the higher-level
    ///   wait method unless you need custom polling cadence or
    ///   progress UI.
    public func getBootstrapStatus() async throws -> BootstrapStatus? {
        let info = try await getInfo(["status/bootstrap-phase"])
        guard let phase = info["status/bootstrap-phase"] else {
            return nil
        }
        return ControlProtocolParser.parseBootstrapStatus(phase)
    }
    
    // MARK: - SETCONF
    
    /// Issue a `SETCONF` command to mutate Tor's runtime configuration.
    ///
    /// Composes the command body per control-spec.txt §3.1: each
    /// option with a non-`nil` value becomes `Key="Value"` (double
    /// quotes escape internal quotes); each option with a `nil`
    /// value becomes the bare `Key` form, which resets the option to
    /// its configured default.
    ///
    /// - Parameter options: Dictionary of torrc option names to
    ///   optional string values. Pass `nil` as a value to reset.
    /// - Throws: ``TorError/controlProtocolError(code:message:)`` on
    ///   rejection (e.g. reply 553 "invalid config value").
    ///
    /// - Important: Not all torrc options are settable at runtime —
    ///   Tor rejects immutable options with reply 553. Consult
    ///   tor.1.txt for the per-option mutability annotation before
    ///   building a mutation.
    public func setConf(_ options: [String: String?]) async throws {
        var parts: [String] = []
        for (key, value) in options {
            if let value = value {
                let quotedValue = "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
                parts.append("\(key)=\(quotedValue)")
            } else {
                parts.append(key)
            }
        }
        
        let command = "SETCONF \(parts.joined(separator: " "))"
        let reply = try await socket.sendCommand(command)
        
        guard reply.isSuccess else {
            throw TorError.controlProtocolError(code: reply.statusCode, message: reply.message)
        }
    }
    
    // MARK: - SETEVENTS / Event Subscription
    
    /// Subscribe to Tor async events and return a stream of decoded
    /// messages.
    ///
    /// Issues `SETEVENTS <keywords>` (control-spec.txt §4) with the
    /// space-joined raw values of `events`, then spawns a background
    /// `Task` that reads lines from the socket via
    /// ``ControlSocket/readLineAsync()``, routes each `650`-status
    /// line through ``ControlProtocolParser/parseAsyncEvent(_:)``,
    /// and yields the result into the returned stream.
    ///
    /// The subscription stays active for the life of the control
    /// connection. Call ``subscribe(to:)`` with an empty `events`
    /// set to unsubscribe (Tor's convention).
    ///
    /// - Parameter events: Events to subscribe to.
    /// - Returns: An `AsyncStream<TorControlEventMessage>` producing
    ///   decoded events until the connection closes or the consumer
    ///   cancels the owning task.
    /// - Throws: ``TorError/controlProtocolError(code:message:)`` if
    ///   Tor rejects the `SETEVENTS` command (e.g. unknown event
    ///   keyword).
    ///
    /// - Important: Only one subscribe loop should read from a given
    ///   ``ControlSocket`` at a time — two concurrent
    ///   ``subscribe(to:)`` streams on the same client will interleave
    ///   reads and fragment events. Use one ``TorControlClient`` per
    ///   subscriber.
    public func subscribe(to events: Set<TorControlEvent>) async throws -> AsyncStream<TorControlEventMessage> {
        let eventNames = events.map(\.rawValue).joined(separator: " ")
        let reply = try await socket.sendCommand("SETEVENTS \(eventNames)")
        
        guard reply.isSuccess else {
            throw TorError.controlProtocolError(code: reply.statusCode, message: reply.message)
        }
        
        return AsyncStream { continuation in
            Task {
                do {
                    while !Task.isCancelled {
                        let line = try await socket.readLineAsync()
                        
                        // Async events start with "650"
                        if let event = ControlProtocolParser.parseAsyncEvent(line) {
                            continuation.yield(event)
                        }
                    }
                } catch {
                    continuation.finish()
                }
            }
        }
    }
    
    // MARK: - Raw Command
    
    /// Escape-hatch: send an arbitrary control command and return the
    /// concatenated reply body.
    ///
    /// Intended for control commands swift-tor has not yet modelled
    /// (e.g. `HSFETCH`, `MAPADDRESS`, `DROPTIMEOUTS`). The response
    /// lines are joined with `\n` for consumer convenience.
    ///
    /// - Parameter line: The command body, without CRLF terminator.
    /// - Returns: The reply lines joined with `\n`.
    /// - Throws: ``TorError/ioError(_:)`` on transport failure.
    ///
    /// - Important: Does **not** classify success vs failure. Callers
    /// must inspect the returned string (or the underlying
    /// ``ControlSocket/sendCommand(_:)``) and react appropriately.
    /// Prefer the typed methods (``getInfo(_:)-([String])``,
    /// ``signal(_:)``, etc.) whenever one exists.
    public func sendRaw(_ line: String) async throws -> String {
        let reply = try await socket.sendCommand(line)
        return reply.lines.joined(separator: "\n")
    }
    
    // MARK: - Onion Services
    
    /// Register an ephemeral v3 onion service via `ADD_ONION`
    /// (control-spec.txt §3.27).
    ///
    /// Serialises `ADD_ONION <keyType> [Flags=…] Port=… Port=…` from
    /// the provided ``OnionKeySpec`` and ``OnionPortMapping`` array,
    /// sends it, parses the reply with
    /// ``ControlProtocolParser/parseAddOnionResponse(_:)-(ControlReply)``,
    /// and wraps the result in an ``OnionService`` with a fresh
    /// `createdAt` timestamp.
    ///
    /// ### Lifecycle
    ///
    /// - `detach: false` (default) — service is tied to **this**
    ///   control connection and removed when the socket closes.
    ///   Ideal for request-scoped services (e.g. a one-shot file
    ///   transfer).
    /// - `detach: true` — `Detach` flag is added; service persists
    ///   until explicit ``delOnion(_:)-(String)`` or Tor exit. Ideal
    ///   for long-lived services that outlive the launching process.
    ///
    /// - Parameters:
    ///   - key: Key policy. See ``OnionKeySpec/newV3(discardPrivateKey:)``
    ///     for Tor-generated keys or ``OnionKeySpec/providedV3(_:)``
    ///     to re-adopt a persisted key.
    ///   - ports: One or more virtual-port → target mappings. Use
    ///     ``OnionPortMapping/toLocalPort(_:localPort:)`` for the
    ///     common loopback case.
    ///   - detach: Whether to detach the service from this
    ///     connection. Defaults to `false`.
    /// - Returns: A fresh ``OnionService`` record. Its
    ///   ``OnionService/privateKey`` is populated iff `key` was
    ///   ``OnionKeySpec/newV3(discardPrivateKey:)`` with
    ///   `discardPrivateKey: false` or
    ///   ``OnionKeySpec/providedV3(_:)`` (in which case it echoes the
    ///   supplied key).
    /// - Throws: ``TorError/controlProtocolError(code:message:)`` on
    ///   rejection, ``TorError/invalidResponse(_:)`` on malformed
    ///   reply, or ``TorError/serviceAlreadyExists(_:)`` when a
    ///   duplicate key is submitted (Tor reply 550/554).
    ///
    /// - Important: ``OnionService/privateKey`` is secret material.
    ///   Persist only via Keychain (Apple) or an equivalent
    ///   credential store.
    public func addOnion(
        key: OnionKeySpec,
        ports: [OnionPortMapping],
        detach: Bool = false
    ) async throws -> OnionService {
        var parts: [String] = ["ADD_ONION", key.keyType]
        
        // Add flags
        var flags = key.flags
        if detach {
            flags.append("Detach")
        }
        if !flags.isEmpty {
            parts.append("Flags=\(flags.joined(separator: ","))")
        }
        
        // Add port mappings
        for port in ports {
            parts.append(port.portSpec)
        }
        
        let command = parts.joined(separator: " ")
        let reply = try await socket.sendCommand(command)
        
        let response = try ControlProtocolParser.parseAddOnionResponse(reply)
        
        return OnionService(
            serviceID: response.serviceID,
            privateKey: response.privateKey,
            createdAt: Date()
        )
    }
    
    /// Remove an ephemeral onion service by its service ID
    /// (`DEL_ONION`, control-spec.txt §3.28).
    ///
    /// Sends `DEL_ONION <serviceID>` and consumes the reply. Reply
    /// `552` ("unrecognized entity") is translated to
    /// ``TorError/invalidServiceID(_:)`` so callers can branch on
    /// typo-vs-real-failure; any other non-success reply becomes
    /// ``TorError/controlProtocolError(code:message:)``.
    ///
    /// - Parameter serviceID: The v3 service ID **without** the
    ///   `.onion` suffix (56-character base32).
    /// - Throws: ``TorError/invalidServiceID(_:)`` for reply 552,
    ///   ``TorError/controlProtocolError(code:message:)`` for other
    ///   failures.
    ///
    /// - Note: Idempotent in the absence of the service — calling it
    ///   twice back-to-back yields a 552 on the second call, which
    ///   the caller may choose to ignore.
    public func delOnion(_ serviceID: String) async throws {
        let reply = try await socket.sendCommand("DEL_ONION \(serviceID)")
        
        guard reply.isSuccess else {
            if reply.statusCode == 552 {
                throw TorError.invalidServiceID(serviceID)
            }
            throw TorError.controlProtocolError(code: reply.statusCode, message: reply.message)
        }
    }
    
    /// Convenience overload: delete an onion service by value.
    ///
    /// Thin wrapper around ``delOnion(_:)-(String)`` that reaches
    /// into ``OnionService/serviceID`` for the ID. Prefer this
    /// overload when you still hold the ``OnionService`` handed back
    /// by ``addOnion(key:ports:detach:)`` — keeps the two sides of
    /// the lifecycle symmetric.
    ///
    /// - Parameter service: The service to delete.
    /// - Throws: Same errors as ``delOnion(_:)-(String)``.
    public func delOnion(_ service: OnionService) async throws {
        try await delOnion(service.serviceID)
    }
    
    // MARK: - Utility Commands
    
    /// Send a `SIGNAL` command to Tor (control-spec.txt §3.7).
    ///
    /// Raw signal-vocabulary escape hatch. Signals Tor supports
    /// include `RELOAD` (reload torrc), `SHUTDOWN` (graceful exit),
    /// `HALT` (immediate exit), `DUMP` (log state), `DEBUG` (rotate
    /// debug log), `NEWNYM` (rotate circuits), `CLEARDNSCACHE`, and
    /// `HEARTBEAT`.
    ///
    /// - Parameter signal: The signal keyword, uppercase.
    /// - Throws: ``TorError/controlProtocolError(code:message:)`` if
    ///   Tor rejects the signal (e.g. unknown keyword, reply 510).
    ///
    /// - Note: For the two common signals swift-tor ships with, use
    ///   ``newIdentity()`` (`NEWNYM`) and ``shutdown()`` (`SHUTDOWN`)
    ///   instead of typing the keyword by hand.
    public func signal(_ signal: String) async throws {
        let reply = try await socket.sendCommand("SIGNAL \(signal)")
        
        guard reply.isSuccess else {
            throw TorError.controlProtocolError(code: reply.statusCode, message: reply.message)
        }
    }
    
    /// Ask Tor to rotate circuits (`SIGNAL NEWNYM`).
    ///
    /// Tor builds fresh circuits for new streams going forward;
    /// already-established streams remain on their existing circuits
    /// until closed. Useful for rotating exits between anonymised
    /// request batches.
    ///
    /// - Throws: ``TorError/controlProtocolError(code:message:)`` if
    ///   the signal is rejected.
    ///
    /// - Note: `NEWNYM` is rate-limited by Tor (default 10 seconds
    ///   between signals). Rapid re-invocation is silently
    ///   coalesced; observe ``TorEvent/log(level:message:)`` at
    ///   ``TorLogLevel/notice`` for the coalesce notice.
    public func newIdentity() async throws {
        try await signal("NEWNYM")
    }
    
    /// Ask Tor to exit cleanly (`SIGNAL SHUTDOWN`).
    ///
    /// Tor finishes in-flight requests, tears down circuits, and
    /// exits. Called by ``TorClient/stop()`` before its 10-second
    /// join window. Callers should not invoke this directly unless
    /// they own the Tor lifecycle outside swift-tor (e.g. driving an
    /// external `tor` daemon).
    ///
    /// - Throws: ``TorError/controlProtocolError(code:message:)`` on
    ///   rejection.
    ///
    /// - Important: Tor's `ShutdownWaitLength` (default 30 seconds)
    ///   controls the grace period for in-flight requests; swift-tor
    ///   shortens the wait to 10 s at the ``TorClient/stop()``
    ///   level so shutdown is bounded for UIs.
    public func shutdown() async throws {
        try await signal("SHUTDOWN")
    }
}
