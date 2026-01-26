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

/// Client for the Tor control protocol.
///
/// `TorControlClient` provides a high-level interface for communicating with Tor
/// via the control protocol. It supports:
/// - Authentication (cookie or password)
/// - Querying Tor state (`GETINFO`)
/// - Configuring Tor (`SETCONF`)
/// - Subscribing to events (`SETEVENTS`)
/// - Managing onion services (`ADD_ONION`, `DEL_ONION`)
///
/// ## Lifecycle Semantics
///
/// When using `addOnion()`:
/// - **Without `detach: true`**: The onion service is tied to this control connection.
///   When the connection closes, the service is automatically removed.
/// - **With `detach: true`**: The onion service persists until explicitly removed
///   via `delOnion()` or until Tor exits.
///
/// ## Thread Safety
///
/// This class is `Sendable` and safe to use from multiple tasks. However, the underlying
/// socket operations are serialized, so concurrent commands will be executed sequentially.
public final class TorControlClient: Sendable {
    
    /// The underlying control socket.
    private let socket: ControlSocket
    
    /// Path to the data directory (for reading cookie file).
    private let dataDirectory: String?
    
    /// Whether authentication has been performed.
    private let _isAuthenticated: ManagedAtomic<Bool>
    
    /// Whether authentication has been performed.
    public var isAuthenticated: Bool {
        _isAuthenticated.load()
    }
    
    /// Creates a control client from an existing socket.
    /// - Parameters:
    ///   - socket: The control socket to use.
    ///   - dataDirectory: Optional path to Tor's data directory (for cookie auth).
    public init(socket: ControlSocket, dataDirectory: String? = nil) {
        self.socket = socket
        self.dataDirectory = dataDirectory
        self._isAuthenticated = ManagedAtomic(false)
    }
    
    /// Creates a control client from a file descriptor.
    ///
    /// This is typically used with the socket returned by
    /// `tor_main_configuration_setup_control_socket()`, which is pre-authenticated.
    ///
    /// - Parameters:
    ///   - fileDescriptor: The control socket file descriptor.
    ///   - preAuthenticated: If true, skips authentication (for control sockets from tor_api).
    ///   - dataDirectory: Optional path to Tor's data directory.
    public init(fileDescriptor: Int32, preAuthenticated: Bool = false, dataDirectory: String? = nil) {
        self.socket = ControlSocket(fileDescriptor: fileDescriptor, ownsDescriptor: false)
        self.dataDirectory = dataDirectory
        self._isAuthenticated = ManagedAtomic(preAuthenticated)
    }
    
    /// Creates a control client by connecting to a TCP control port.
    /// - Parameters:
    ///   - host: The host to connect to.
    ///   - port: The control port.
    ///   - dataDirectory: Optional path to Tor's data directory (for cookie auth).
    public convenience init(host: String, port: Int, dataDirectory: String? = nil) throws {
        let socket = try ControlSocket(host: host, port: port)
        self.init(socket: socket, dataDirectory: dataDirectory)
    }
    
    // MARK: - Authentication
    
    /// Authenticates with the control port.
    ///
    /// If a cookie file exists in the data directory, cookie authentication is used.
    /// Otherwise, password authentication is attempted if a password is provided.
    ///
    /// - Parameter password: Optional password for authentication.
    /// - Throws: `TorError.controlAuthFailed` if authentication fails.
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
                    _isAuthenticated.store(true)
                    return
                }
            }
        }
        
        // Try password authentication
        if let password = password {
            let quotedPassword = "\"\(password.replacingOccurrences(of: "\"", with: "\\\""))\""
            let reply = try await socket.sendCommand("AUTHENTICATE \(quotedPassword)")
            
            if reply.isSuccess {
                _isAuthenticated.store(true)
                return
            }
            
            throw TorError.controlAuthFailed(reply.message)
        }
        
        // Try empty authentication (for control sockets that don't require auth)
        let reply = try await socket.sendCommand("AUTHENTICATE")
        
        if reply.isSuccess {
            _isAuthenticated.store(true)
            return
        }
        
        throw TorError.controlAuthFailed(reply.message)
    }
    
    // MARK: - GETINFO
    
    /// Queries information from Tor.
    /// - Parameter keys: The info keys to query.
    /// - Returns: Dictionary mapping keys to their values.
    /// - Throws: `TorError` on failure.
    public func getInfo(_ keys: [String]) async throws -> [String: String] {
        let command = "GETINFO \(keys.joined(separator: " "))"
        let reply = try await socket.sendCommand(command)
        return try ControlProtocolParser.parseGetInfoResponse(reply)
    }
    
    /// Queries a single info key.
    /// - Parameter key: The info key to query.
    /// - Returns: The value, or nil if not found.
    public func getInfo(_ key: String) async throws -> String? {
        let result = try await getInfo([key])
        return result[key]
    }
    
    /// Gets the current bootstrap status.
    /// - Returns: The parsed bootstrap status.
    public func getBootstrapStatus() async throws -> BootstrapStatus? {
        let info = try await getInfo(["status/bootstrap-phase"])
        guard let phase = info["status/bootstrap-phase"] else {
            return nil
        }
        return ControlProtocolParser.parseBootstrapStatus(phase)
    }
    
    // MARK: - SETCONF
    
    /// Sets configuration options.
    /// - Parameter options: Dictionary of option names to values. Use nil to reset to default.
    /// - Throws: `TorError` on failure.
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
    
    /// Subscribes to control port events.
    ///
    /// Returns an `AsyncStream` that yields events as they arrive. The subscription
    /// remains active until the stream is cancelled or the connection closes.
    ///
    /// - Parameter events: The events to subscribe to.
    /// - Returns: An async stream of event messages.
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
    
    /// Sends a raw command and returns the raw response.
    ///
    /// This is an escape hatch for commands not covered by the typed API.
    ///
    /// - Parameter line: The command to send (without CRLF).
    /// - Returns: The raw response string.
    public func sendRaw(_ line: String) async throws -> String {
        let reply = try await socket.sendCommand(line)
        return reply.lines.joined(separator: "\n")
    }
    
    // MARK: - Onion Services
    
    /// Creates an ephemeral onion service.
    ///
    /// ## Lifecycle
    ///
    /// - Without `detach: true`: The service is tied to this control connection and
    ///   will be removed when the connection closes.
    /// - With `detach: true`: The service persists until explicitly removed via
    ///   `delOnion()` or until Tor exits.
    ///
    /// - Parameters:
    ///   - key: The key specification (new or provided).
    ///   - ports: Port mappings from virtual ports to targets.
    ///   - detach: If true, the service persists after this connection closes.
    /// - Returns: The created onion service.
    /// - Throws: `TorError` on failure.
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
    
    /// Deletes an ephemeral onion service.
    ///
    /// - Parameter serviceID: The service ID (without .onion suffix).
    /// - Throws: `TorError` on failure.
    public func delOnion(_ serviceID: String) async throws {
        let reply = try await socket.sendCommand("DEL_ONION \(serviceID)")
        
        guard reply.isSuccess else {
            if reply.statusCode == 552 {
                throw TorError.invalidServiceID(serviceID)
            }
            throw TorError.controlProtocolError(code: reply.statusCode, message: reply.message)
        }
    }
    
    /// Deletes an ephemeral onion service.
    ///
    /// - Parameter service: The onion service to delete.
    /// - Throws: `TorError` on failure.
    public func delOnion(_ service: OnionService) async throws {
        try await delOnion(service.serviceID)
    }
    
    // MARK: - Utility Commands
    
    /// Sends a SIGNAL command.
    /// - Parameter signal: The signal name (e.g., "SHUTDOWN", "RELOAD", "NEWNYM").
    public func signal(_ signal: String) async throws {
        let reply = try await socket.sendCommand("SIGNAL \(signal)")
        
        guard reply.isSuccess else {
            throw TorError.controlProtocolError(code: reply.statusCode, message: reply.message)
        }
    }
    
    /// Requests a new identity (new circuits).
    public func newIdentity() async throws {
        try await signal("NEWNYM")
    }
    
    /// Requests Tor to shut down gracefully.
    public func shutdown() async throws {
        try await signal("SHUTDOWN")
    }
}

// MARK: - Atomic Bool Helper

/// A simple thread-safe boolean wrapper.
private final class ManagedAtomic<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    
    init(_ value: T) {
        self.value = value
    }
    
    func load() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    
    func store(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}
