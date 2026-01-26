//
//  HostPort.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Represents a network endpoint with host and port.
public struct HostPort: Sendable, Hashable, CustomStringConvertible {
    /// The host address (e.g., "127.0.0.1" or "localhost").
    public let host: String
    
    /// The port number.
    public let port: Int
    
    /// Creates a new host-port pair.
    /// - Parameters:
    ///   - host: The host address.
    ///   - port: The port number.
    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
    
    /// Creates a localhost endpoint with the specified port.
    /// - Parameter port: The port number.
    /// - Returns: A `HostPort` with host "127.0.0.1".
    public static func localhost(_ port: Int) -> HostPort {
        HostPort(host: "127.0.0.1", port: port)
    }
    
    public var description: String {
        "\(host):\(port)"
    }
}
