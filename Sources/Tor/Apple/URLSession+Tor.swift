//
//  URLSession+Tor.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

#if canImport(CFNetwork)
import Foundation

/// Apple-only extensions for routing URLSession traffic through Tor.
extension URLSessionConfiguration {
    
    /// Creates a URLSession configuration that routes all traffic through a SOCKS5 proxy.
    ///
    /// Use this with a running `TorClient` to route HTTP/HTTPS requests through Tor:
    ///
    /// ```swift
    /// let client = TorClient()
    /// try await client.start()
    /// try await client.waitUntilBootstrapped()
    ///
    /// let config = URLSessionConfiguration.configuredForTor(socksEndpoint: client.socksEndpoint!)
    /// let session = URLSession(configuration: config)
    ///
    /// let (data, _) = try await session.data(from: URL(string: "https://check.torproject.org/api/ip")!)
    /// ```
    ///
    /// - Parameter endpoint: The SOCKS5 proxy endpoint (typically from `TorClient.socksEndpoint`).
    /// - Returns: A configured `URLSessionConfiguration` that routes through the proxy.
    public static func configuredForTor(socksEndpoint endpoint: HostPort) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [
            kCFProxyTypeKey: kCFProxyTypeSOCKS,
            kCFStreamPropertySOCKSProxyHost: endpoint.host,
            kCFStreamPropertySOCKSProxyPort: endpoint.port,
            kCFStreamPropertySOCKSVersion: kCFStreamSocketSOCKSVersion5
        ]
        return config
    }
    
    /// Creates an ephemeral URLSession configuration that routes all traffic through a SOCKS5 proxy.
    ///
    /// This is similar to `configuredForTor(socksEndpoint:)` but uses an ephemeral configuration
    /// that doesn't persist cookies, caches, or credentials to disk.
    ///
    /// - Parameter endpoint: The SOCKS5 proxy endpoint.
    /// - Returns: An ephemeral `URLSessionConfiguration` that routes through the proxy.
    public static func ephemeralConfiguredForTor(socksEndpoint endpoint: HostPort) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFProxyTypeKey: kCFProxyTypeSOCKS,
            kCFStreamPropertySOCKSProxyHost: endpoint.host,
            kCFStreamPropertySOCKSProxyPort: endpoint.port,
            kCFStreamPropertySOCKSVersion: kCFStreamSocketSOCKSVersion5
        ]
        return config
    }
}

/// Convenience extension on TorClient for creating URLSession instances.
extension TorClient {
    
    /// Creates a URLSession configured to route traffic through this Tor instance.
    ///
    /// - Parameter ephemeral: If true, uses ephemeral configuration (no disk persistence).
    /// - Returns: A configured URLSession, or nil if SOCKS endpoint is not available.
    /// - Throws: `TorError.notStarted` if Tor is not running.
    public func makeURLSession(ephemeral: Bool = false) async throws -> URLSession {
        guard state.isOperational else {
            throw TorError.notStarted
        }
        
        guard let endpoint = socksEndpoint else {
            throw TorError.controlUnavailable
        }
        
        let config = ephemeral
            ? URLSessionConfiguration.ephemeralConfiguredForTor(socksEndpoint: endpoint)
            : URLSessionConfiguration.configuredForTor(socksEndpoint: endpoint)
        
        return URLSession(configuration: config)
    }
}

#endif
