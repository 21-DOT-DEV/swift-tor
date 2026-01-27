//
//  OnionService.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Specifies the key type for creating an onion service.
public enum OnionKeySpec: Sendable {
    /// Generate a new v3 onion service key.
    /// - Parameter discardPrivateKey: If true, the private key is not returned and cannot be reused.
    case newV3(discardPrivateKey: Bool = false)
    
    /// Use a provided v3 private key.
    /// - Parameter key: The ED25519-V3 private key in Tor's format.
    case providedV3(String)
    
    /// Returns the key type string for the ADD_ONION command.
    var keyType: String {
        switch self {
        case .newV3:
            return "NEW:ED25519-V3"
        case .providedV3(let key):
            return "ED25519-V3:\(key)"
        }
    }
    
    /// Returns any flags needed for the ADD_ONION command.
    var flags: [String] {
        switch self {
        case .newV3(discardPrivateKey: true):
            return ["DiscardPK"]
        case .newV3(discardPrivateKey: false), .providedV3:
            return []
        }
    }
}

/// Specifies the target for an onion service port mapping.
public enum OnionPortTarget: Sendable, Hashable {
    /// Forward to a TCP host and port.
    case tcp(host: String, port: Int)
    
    /// Forward to a Unix domain socket.
    case unix(path: String)
    
    var targetString: String {
        switch self {
        case .tcp(let host, let port):
            return "\(host):\(port)"
        case .unix(let path):
            return "unix:\(path)"
        }
    }
}

/// Maps a virtual port on the onion service to a local target.
public struct OnionPortMapping: Sendable, Hashable {
    /// The port exposed on the .onion address.
    public let virtualPort: Int
    
    /// Where to forward connections to this port.
    public let target: OnionPortTarget
    
    /// Creates a port mapping.
    /// - Parameters:
    ///   - virtualPort: The port exposed on the .onion address.
    ///   - target: Where to forward connections.
    public init(virtualPort: Int, target: OnionPortTarget) {
        self.virtualPort = virtualPort
        self.target = target
    }
    
    /// Creates a port mapping to a local TCP port.
    /// - Parameters:
    ///   - virtualPort: The port exposed on the .onion address.
    ///   - localPort: The local port to forward to (on 127.0.0.1).
    public static func toLocalPort(_ virtualPort: Int, localPort: Int) -> OnionPortMapping {
        OnionPortMapping(virtualPort: virtualPort, target: .tcp(host: "127.0.0.1", port: localPort))
    }
    
    /// Returns the port specification for the ADD_ONION command.
    var portSpec: String {
        "Port=\(virtualPort),\(target.targetString)"
    }
}

/// Represents a created onion service.
public struct OnionService: Sendable {
    /// The service ID (without the .onion suffix).
    public let serviceID: String
    
    /// The private key, if available.
    /// This is nil if the key was discarded during creation.
    public let privateKey: String?
    
    /// When this service was created.
    public let createdAt: Date
    
    /// The full .onion address.
    public var onionAddress: String {
        "\(serviceID).onion"
    }
    
    /// Creates an onion service record.
    /// - Parameters:
    ///   - serviceID: The service ID (without .onion).
    ///   - privateKey: The private key, if available.
    ///   - createdAt: When the service was created.
    public init(serviceID: String, privateKey: String? = nil, createdAt: Date = Date()) {
        self.serviceID = serviceID
        self.privateKey = privateKey
        self.createdAt = createdAt
    }
}
