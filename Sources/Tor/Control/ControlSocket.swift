//
//  ControlSocket.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Synchronization

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

/// Cross-platform, `Sendable` line-oriented wrapper around a Tor control
/// socket file descriptor.
///
/// `ControlSocket` is the POSIX-level plumbing that sits under
/// ``TorControlClient``. It provides the three operations the
/// control protocol demands (control-spec.txt §2): write a
/// CRLF-terminated command line, read back a CRLF-terminated reply
/// line, and assemble multi-line (`250-`, `250+`, `650+`) replies into a
/// single `[String]`. The underlying FD is either the pre-authenticated
/// socket from `tor_main_configuration_setup_control_socket()` (embedded
/// mode) or a freshly-opened TCP connection to a listening `ControlPort`.
///
/// Platform plumbing is abstracted across Darwin (`Darwin`), Linux
/// (`Glibc`, `Musl`), and Windows (`WinSDK`) via `#if canImport(…)`
/// guards. Sockets are configured with `SO_RCVTIMEO` so blocking `recv`
/// calls honour ``readTimeout`` without requiring a polling loop.
///
/// - Note: Conformance is `Sendable` (compiler-verified, no `@unchecked`).
///   All mutable state lives inside a `Mutex<State>` from the
///   `Synchronization` module (SE-0410); callers may share instances
///   across concurrency domains and call methods concurrently — each
///   operation acquires the mutex for its own critical section.
/// - Important: The `deinit` calls `close(2)` (or `closesocket()` on
///   Windows) **only** when ``init(fileDescriptor:ownsDescriptor:)`` was
///   invoked with `ownsDescriptor: true`. Embedded control sockets from
///   `tor_api` are owned by Tor; swift-tor must not close them.
///
/// ## Topics
///
/// ### Creating
/// - ``init(fileDescriptor:ownsDescriptor:)``
/// - ``init(host:port:)``
/// - ``init(endpoint:)``
///
/// ### I/O
/// - ``writeLine(_:)``
/// - ``writeData(_:)``
/// - ``readLine()``
/// - ``readReply()``
/// - ``sendCommand(_:)``
/// - ``readLineAsync()``
///
/// ### State
/// - ``readTimeout``
/// - ``isValid``
public final class ControlSocket: Sendable {

    /// Combined mutable state serialised by the `Mutex` below.
    private struct State {
        /// Read buffer for accumulating partial lines.
        var readBuffer: Data = Data()
        /// Read timeout in seconds.
        var readTimeout: TimeInterval = 30.0
    }

    /// The underlying socket file descriptor.
    private let fd: Int32

    /// Whether this socket owns the file descriptor and should close it on deinit.
    private let ownsDescriptor: Bool

    /// Mutex-guarded mutable state. Replaces the previous `NSLock` + stored
    /// properties pair and enables compiler-verified `Sendable` conformance.
    private let state = Mutex<State>(State())

    /// Read timeout in seconds, applied to every ``readLine()`` call.
    ///
    /// When an in-flight `readLine()` has been waiting longer than this
    /// bound, it throws ``TorError/timeout``. Mutations race-safely with
    /// concurrent reads because both getter and setter acquire the
    /// internal `Mutex<State>`.
    ///
    /// - Stability: mutable at any time. The new value takes effect on
    ///   the **next** `setSocketTimeout` call inside the `readLine()`
    ///   polling loop (i.e., within one iteration, typically under
    ///   1 second). Default is `30.0` seconds.
    /// - Typical values: `30.0` for interactive use, `5.0` for tight CI
    ///   deadlines, `120.0` or more during bootstrap when slow consensus
    ///   downloads may delay the first reply.
    public var readTimeout: TimeInterval {
        get { state.withLock { $0.readTimeout } }
        set { state.withLock { $0.readTimeout = newValue } }
    }
    
    /// Wrap an already-open file descriptor.
    ///
    /// Primary embedded-mode entry point. Swift-tor passes the FD
    /// returned by `tor_main_configuration_setup_control_socket()` with
    /// `ownsDescriptor: false`, so Tor retains ownership. External
    /// callers that `socket(2)`'d and `connect(2)`'d a descriptor
    /// themselves should pass `ownsDescriptor: true` so `deinit` closes
    /// the FD when the wrapper drops.
    ///
    /// - Parameters:
    ///   - fileDescriptor: A valid, connected socket FD.
    ///   - ownsDescriptor: Whether `deinit` should close the FD.
    ///     Defaults to `false`.
    ///
    /// - Important: Passing `fileDescriptor: -1` creates an
    ///   invalid-but-constructible instance — ``isValid`` returns `false`
    ///   and every read/write throws ``TorError/ioError(_:)``. Useful
    ///   for placeholder/tests only.
    public init(fileDescriptor: Int32, ownsDescriptor: Bool = false) {
        self.fd = fileDescriptor
        self.ownsDescriptor = ownsDescriptor
    }
    
    /// Open a TCP connection to a control port and wrap it.
    ///
    /// Synchronously `socket(2)` + `connect(2)` to `host:port`, then
    /// take ownership of the resulting FD. DNS resolution uses
    /// `gethostbyname(3)` as a fallback when `inet_pton` can't parse
    /// `host` as an IPv4 literal. On success the returned `ControlSocket`
    /// is connected but **not** authenticated — callers must then go
    /// through the `AUTHENTICATE` handshake via ``TorControlClient``.
    ///
    /// - Parameters:
    ///   - host: IPv4 literal or DNS name of the control port host.
    ///   - port: TCP port (typically 9051 for Tor's default ControlPort).
    /// - Throws: ``TorError/ioError(_:)`` on socket/connect failure, DNS
    ///   resolution failure, or `WSAStartup` failure on Windows.
    ///
    /// - Note: Ownership is implicit — the wrapper always closes the FD
    ///   on `deinit`. Use ``init(fileDescriptor:ownsDescriptor:)`` when
    ///   finer ownership control is required.
    public convenience init(host: String, port: Int) throws {
        let fd = try Self.connectTCP(host: host, port: port)
        self.init(fileDescriptor: fd, ownsDescriptor: true)
    }
    
    /// Open a TCP connection to a typed ``HostPort`` endpoint.
    ///
    /// Thin wrapper around ``init(host:port:)`` that accepts the typed
    /// endpoint value swift-tor uses throughout its public API. Prefer
    /// this overload at API boundaries so host/port stay paired.
    ///
    /// - Parameter endpoint: The control port endpoint.
    /// - Throws: ``TorError/ioError(_:)`` on connection failure.
    public convenience init(endpoint: HostPort) throws {
        try self.init(host: endpoint.host, port: endpoint.port)
    }
    
    deinit {
        if ownsDescriptor && fd >= 0 {
            #if os(Windows)
            closesocket(fd)
            #else
            close(fd)
            #endif
        }
    }
    
    /// `true` if the wrapped FD is non-negative, i.e. structurally valid.
    ///
    /// Does **not** prove the peer is reachable or the TCP session is
    /// live — only that the wrapper was not constructed with a sentinel
    /// `-1` and that the socket has not been manually marked invalid.
    /// Liveness must be established by actually issuing a `readLine()`
    /// or `writeLine()`.
    ///
    /// - Returns: `true` when `fd >= 0`, else `false`.
    public var isValid: Bool {
        fd >= 0
    }
    
    // MARK: - Writing
    
    /// Send a single protocol command line.
    ///
    /// Appends `\r\n` to `line` per control-spec.txt §2 (line framing)
    /// and forwards the bytes to ``writeData(_:)``. The caller passes
    /// the command body without the CRLF terminator —
    /// `"GETINFO version"`, `"SIGNAL NEWNYM"`, etc.
    ///
    /// - Parameter line: The command, **without** the CRLF terminator.
    /// - Throws: ``TorError/ioError(_:)`` on `send(2)` failure or a
    ///   closed socket.
    ///
    /// - Important: Commands must not themselves contain raw CR or LF
    ///   bytes — the protocol has no quoting beyond CRLF line framing,
    ///   and embedded separators will be interpreted as command
    ///   boundaries by Tor.
    public func writeLine(_ line: String) throws {
        let data = (line + "\r\n").data(using: .utf8)!
        try writeData(data)
    }
    
    /// Send a raw byte payload, looping until every byte is written.
    /// 
    /// Low-level counterpart to ``writeLine(_:)``. Called when the
    /// caller needs to ship a pre-assembled payload (multi-line
    /// commands, binary-safe extensions). Loops over `send(2)` until
    /// the full `data` has been drained, handling short writes
    /// transparently.
    ///
    /// - Parameter data: The bytes to write verbatim.
    /// - Throws: ``TorError/ioError(_:)`` if the FD is closed or any
    ///   `send(2)` returns `-1`.
    ///
    /// - Important: Partial writes are **not** reported to the caller —
    ///   swift-tor retries transparently. If `send(2)` fails mid-
    ///   payload the caller must treat the socket as compromised and
    ///   abandon it; the Tor peer has consumed an unknown prefix of
    ///   the intended command.
    public func writeData(_ data: Data) throws {
        guard fd >= 0 else {
            throw TorError.ioError("Socket is closed")
        }
        
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var remaining = data.count
            var offset = 0
            
            while remaining > 0 {
                #if os(Windows)
                let written = WinSDK.send(fd, baseAddress.advanced(by: offset), Int32(remaining), 0)
                #else
                let written = send(fd, baseAddress.advanced(by: offset), remaining, 0)
                #endif
                
                if written < 0 {
                    throw TorError.ioError("Write failed: \(Self.lastErrorMessage())")
                }
                
                remaining -= Int(written)
                offset += Int(written)
            }
        }
    }
    
    // MARK: - Reading
    
    /// Read one CRLF-terminated line, buffering residual bytes for the
    /// next call.
    ///
    /// The core read primitive. Performs a bounded `recv(2)` loop with
    /// `SO_RCVTIMEO` set to the smaller of 1 second or the remaining
    /// budget, appending to an internal buffer until a CRLF is found
    /// (per control-spec.txt §2 line framing). Anything after the CRLF
    /// is retained for the next invocation, so multiple lines read in
    /// one syscall are surfaced correctly.
    ///
    /// Acquires the `Mutex<State>` for the full duration of the call.
    /// Concurrent `readLine()` / `readReply()` callers are serialised;
    /// the later caller blocks until the earlier one returns.
    ///
    /// - Returns: The line body **without** the trailing CRLF.
    /// - Throws: ``TorError/ioError(_:)`` on `recv(2)` failure or if
    ///   the peer closed the connection; ``TorError/timeout`` when
    ///   ``readTimeout`` elapses before a CRLF is seen.
    ///
    /// - Note: `EAGAIN`, `EWOULDBLOCK`, and `EINTR` are retried
    ///   transparently inside the timeout budget; callers only see
    ///   hard failures.
    public func readLine() throws -> String {
        try state.withLock { state in
            // Check if we already have a complete line in the buffer
            if let line = Self.extractLine(from: &state.readBuffer) {
                return line
            }

            // Read more data until we have a complete line
            let deadline = Date().addingTimeInterval(state.readTimeout)
            var tempBuffer = [UInt8](repeating: 0, count: 4096)

            while Date() < deadline {
                // Set read timeout on socket
                setSocketTimeout(seconds: min(1.0, deadline.timeIntervalSinceNow))

                #if os(Windows)
                let bytesRead = WinSDK.recv(fd, &tempBuffer, Int32(tempBuffer.count), 0)
                #else
                let bytesRead = recv(fd, &tempBuffer, tempBuffer.count, 0)
                #endif

                if bytesRead < 0 {
                    #if os(Windows)
                    let err = WSAGetLastError()
                    if err == WSAETIMEDOUT || err == WSAEWOULDBLOCK {
                        continue
                    }
                    #else
                    if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                        continue
                    }
                    #endif
                    throw TorError.ioError("Read failed: \(Self.lastErrorMessage())")
                }

                if bytesRead == 0 {
                    throw TorError.ioError("Connection closed")
                }

                state.readBuffer.append(contentsOf: tempBuffer[0..<Int(bytesRead)])

                if let line = Self.extractLine(from: &state.readBuffer) {
                    return line
                }
            }

            throw TorError.timeout
        }
    }
    
    /// Read a complete control-protocol reply as an ordered `[String]`.
    ///
    /// Assembles one or more ``readLine()`` results into a full reply
    /// by interpreting the fourth byte of each line per
    /// control-spec.txt §2.3: `' '` terminates, `-` continues the
    /// status, and `+` opens a data block terminated by a sole `.`.
    /// Callers receive every raw line (including status-code prefixes)
    /// so downstream ``ControlProtocolParser`` can classify them.
    ///
    /// - Returns: The raw reply lines in receive order. Always
    ///   non-empty in the success path.
    /// - Throws: ``TorError/ioError(_:)`` or ``TorError/timeout``
    ///   propagated from ``readLine()``.
    ///
    /// - Important: The function does **not** classify the status code
    ///   as success or failure. Pass the returned lines to
    ///   ``ControlProtocolParser/parseReply(_:)`` for that.
    public func readReply() throws -> [String] {
        var lines: [String] = []
        var inDataBlock = false
        
        while true {
            let line = try readLine()
            lines.append(line)
            
            if inDataBlock {
                // In a data block, look for the terminating "."
                if line == "." {
                    inDataBlock = false
                    // Continue reading for the final status line
                }
                continue
            }
            
            // Check for continuation markers
            if line.count >= 4 {
                let separator = line[line.index(line.startIndex, offsetBy: 3)]
                
                if separator == "+" {
                    // Start of data block
                    inDataBlock = true
                    continue
                } else if separator == "-" {
                    // Continuation line
                    continue
                } else if separator == " " {
                    // Final line
                    break
                }
            }
            
            // Single-line reply (3 digit code + space or end)
            if line.count >= 3 {
                let codeStr = String(line.prefix(3))
                if Int(codeStr) != nil {
                    break
                }
            }
            
            // Unknown format, treat as single line
            break
        }
        
        return lines
    }
    
    // MARK: - Private Helpers
    
    /// Extracts a complete CRLF-terminated line from the given read buffer.
    ///
    /// Static helper invoked inside `state.withLock { … }` closures where the
    /// buffer is available as a mutable reference to the Mutex-guarded state.
    private static func extractLine(from buffer: inout Data) -> String? {
        guard let crlfRange = buffer.range(of: Data([0x0D, 0x0A])) else {
            return nil
        }

        let lineData = buffer[..<crlfRange.lowerBound]
        buffer.removeSubrange(..<crlfRange.upperBound)

        return String(data: Data(lineData), encoding: .utf8)
    }
    
    /// Sets the socket read timeout.
    private func setSocketTimeout(seconds: TimeInterval) {
        #if os(Windows)
        var timeout = DWORD(seconds * 1000) // milliseconds
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, Int32(MemoryLayout<DWORD>.size))
        #else
#if canImport(Glibc)
        let usec = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1_000_000)
#else
        let usec = Int32((seconds.truncatingRemainder(dividingBy: 1)) * 1_000_000)
#endif
        var tv = timeval(
            tv_sec: Int(seconds),
            tv_usec: usec
        )
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        #endif
    }
    
    /// Connects to a TCP host and port.
    private static func connectTCP(host: String, port: Int) throws -> Int32 {
        #if os(Windows)
        // Windows socket initialization
        var wsaData = WSADATA()
        WSAStartup(MAKEWORD(2, 2), &wsaData)
        #endif
        
        #if canImport(Glibc)
        let sock = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
#else
        let sock = socket(AF_INET, SOCK_STREAM, 0)
#endif
        guard sock >= 0 else {
            throw TorError.ioError("Failed to create socket: \(lastErrorMessage())")
        }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        
        // Convert host to address
        if inet_pton(AF_INET, host, &addr.sin_addr) != 1 {
            // Try resolving hostname
            guard let hostent = gethostbyname(host),
                  let addrList = hostent.pointee.h_addr_list,
                  let firstAddr = addrList[0] else {
                #if os(Windows)
                closesocket(sock)
                #else
                close(sock)
                #endif
                throw TorError.ioError("Failed to resolve host: \(host)")
            }
            memcpy(&addr.sin_addr, firstAddr, Int(hostent.pointee.h_length))
        }
        
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard connectResult == 0 else {
            #if os(Windows)
            closesocket(sock)
            #else
            close(sock)
            #endif
            throw TorError.ioError("Failed to connect to \(host):\(port): \(lastErrorMessage())")
        }
        
        return sock
    }
    
    /// Returns the last system error message.
    private static func lastErrorMessage() -> String {
        #if os(Windows)
        let err = WSAGetLastError()
        return "error code \(err)"
        #else
        return String(cString: strerror(errno))
        #endif
    }
}

// MARK: - Async Extensions

extension ControlSocket {
    
    /// Send a command and return the parsed reply.
    ///
    /// The primary high-level I/O entry point. Internally:
    /// 1. Hops to a global-queue background thread via
    ///    `DispatchQueue.global(qos: .userInitiated)` so the blocking
    ///    ``writeLine(_:)`` + ``readReply()`` pair does not occupy a
    ///    Swift Concurrency cooperative thread.
    /// 2. Runs the write, the read-reply, and the
    ///    ``ControlProtocolParser/parseReply(_:)`` classification.
    /// 3. Bridges back via a `CheckedContinuation`.
    ///
    /// - Parameter command: The command body **without** CRLF.
    /// - Returns: A parsed ``ControlReply``.
    /// - Throws: ``TorError/ioError(_:)``, ``TorError/timeout``, or
    ///   ``TorError/invalidResponse(_:)`` if parsing fails.
    ///
    /// - Note: Commands execute in the order they arrive at this
    ///   method — concurrent callers are serialised by the internal
    ///   `Mutex<State>` on both the write and read paths.
    public func sendCommand(_ command: String) async throws -> ControlReply {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.writeLine(command)
                    let lines = try self.readReply()
                    let reply = try ControlProtocolParser.parseReply(lines)
                    continuation.resume(returning: reply)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// `readLine()` hoisted off the cooperative thread pool.
    ///
    /// Thin async wrapper that executes ``readLine()`` on a global
    /// dispatch queue and resumes a `CheckedContinuation` with the
    /// result. Intended for callers that need to consume async event
    /// streams (`650`-status lines) without blocking Swift Concurrency.
    ///
    /// - Returns: The line body without the trailing CRLF.
    /// - Throws: ``TorError/ioError(_:)`` or ``TorError/timeout``
    ///   propagated from ``readLine()``.
    public func readLineAsync() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let line = try self.readLine()
                    continuation.resume(returning: line)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
