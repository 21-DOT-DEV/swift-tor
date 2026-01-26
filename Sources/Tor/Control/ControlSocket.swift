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

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

/// A cross-platform wrapper for control socket I/O.
///
/// This class provides line-oriented read/write operations for the Tor control protocol,
/// which uses CRLF-terminated lines.
///
/// The socket can be either:
/// - A file descriptor from `tor_main_configuration_setup_control_socket()`
/// - A TCP connection to a control port
///
/// - Note: This class is `@unchecked Sendable` because the underlying file descriptor
///   operations are thread-safe when properly synchronized at a higher level.
public final class ControlSocket: @unchecked Sendable {
    
    /// The underlying socket file descriptor.
    private let fd: Int32
    
    /// Whether this socket owns the file descriptor and should close it on deinit.
    private let ownsDescriptor: Bool
    
    /// Read buffer for accumulating partial lines.
    private var readBuffer: Data = Data()
    
    /// Lock for thread-safe buffer access.
    private let lock = NSLock()
    
    /// Default read timeout in seconds.
    public var readTimeout: TimeInterval = 30.0
    
    /// Creates a control socket from an existing file descriptor.
    /// - Parameters:
    ///   - fileDescriptor: The socket file descriptor.
    ///   - ownsDescriptor: If true, the socket will close the descriptor on deinit.
    public init(fileDescriptor: Int32, ownsDescriptor: Bool = false) {
        self.fd = fileDescriptor
        self.ownsDescriptor = ownsDescriptor
    }
    
    /// Creates a control socket by connecting to a TCP endpoint.
    /// - Parameters:
    ///   - host: The host to connect to.
    ///   - port: The port to connect to.
    /// - Throws: `TorError.ioError` if the connection fails.
    public convenience init(host: String, port: Int) throws {
        let fd = try Self.connectTCP(host: host, port: port)
        self.init(fileDescriptor: fd, ownsDescriptor: true)
    }
    
    /// Creates a control socket by connecting to a `HostPort` endpoint.
    /// - Parameter endpoint: The endpoint to connect to.
    /// - Throws: `TorError.ioError` if the connection fails.
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
    
    /// Whether the socket is valid.
    public var isValid: Bool {
        fd >= 0
    }
    
    // MARK: - Writing
    
    /// Sends a command line to the control socket.
    /// - Parameter line: The command to send (without CRLF terminator).
    /// - Throws: `TorError.ioError` if the write fails.
    public func writeLine(_ line: String) throws {
        let data = (line + "\r\n").data(using: .utf8)!
        try writeData(data)
    }
    
    /// Sends raw data to the control socket.
    /// - Parameter data: The data to send.
    /// - Throws: `TorError.ioError` if the write fails.
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
    
    /// Reads a single line from the control socket.
    /// - Returns: The line without the CRLF terminator.
    /// - Throws: `TorError.ioError` if the read fails, `TorError.timeout` if the read times out.
    public func readLine() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        
        // Check if we already have a complete line in the buffer
        if let line = extractLine() {
            return line
        }
        
        // Read more data until we have a complete line
        let deadline = Date().addingTimeInterval(readTimeout)
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
            
            readBuffer.append(contentsOf: tempBuffer[0..<Int(bytesRead)])
            
            if let line = extractLine() {
                return line
            }
        }
        
        throw TorError.timeout
    }
    
    /// Reads a complete control protocol reply (may be multi-line).
    /// - Returns: Array of raw lines (including status codes).
    /// - Throws: `TorError` on read failure.
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
    
    /// Extracts a complete CRLF-terminated line from the read buffer.
    private func extractLine() -> String? {
        guard let crlfRange = readBuffer.range(of: Data([0x0D, 0x0A])) else {
            return nil
        }
        
        let lineData = readBuffer[..<crlfRange.lowerBound]
        readBuffer.removeSubrange(..<crlfRange.upperBound)
        
        return String(data: Data(lineData), encoding: .utf8)
    }
    
    /// Sets the socket read timeout.
    private func setSocketTimeout(seconds: TimeInterval) {
        #if os(Windows)
        var timeout = DWORD(seconds * 1000) // milliseconds
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, Int32(MemoryLayout<DWORD>.size))
        #else
        var tv = timeval(
            tv_sec: Int(seconds),
            tv_usec: Int32((seconds.truncatingRemainder(dividingBy: 1)) * 1_000_000)
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
        
        let sock = socket(AF_INET, SOCK_STREAM, 0)
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
    
    /// Sends a command and reads the reply asynchronously.
    /// - Parameter command: The command to send (without CRLF).
    /// - Returns: The parsed control reply.
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
    
    /// Reads a line asynchronously.
    /// - Returns: The line without CRLF terminator.
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
