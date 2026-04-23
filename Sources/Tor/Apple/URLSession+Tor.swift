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

/// Apple-only extensions for routing `URLSession` traffic through a
/// SOCKS5 proxy (typically a running ``TorClient``).
///
/// These helpers are gated by `#if canImport(CFNetwork)` because they
/// rely on the CFNetwork proxy-dictionary keys
/// (`kCFProxyTypeSOCKS`, `kCFStreamPropertySOCKSProxyHost`,
/// `kCFStreamPropertySOCKSProxyPort`, `kCFStreamPropertySOCKSVersion`)
/// that Apple exposes only on macOS, iOS, tvOS, watchOS, and
/// visionOS. On Linux the helpers are not compiled at all — apps
/// must either use an Apple-only codepath or integrate a SOCKS5
/// proxy client directly.
///
/// The configuration follows Apple's documented proxy-dictionary
/// shape, see [URLSessionConfiguration.connectionProxyDictionary](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/1411499-connectionproxydictionary).
extension URLSessionConfiguration {
    
    /// Build a persistent `URLSessionConfiguration` that routes every
    /// HTTP/HTTPS request through a SOCKS5 proxy.
    ///
    /// Starts from `URLSessionConfiguration.default` (which persists
    /// cookies, caches, and credentials to disk) and installs a
    /// SOCKS5 proxy dictionary pointing at `endpoint`. Suitable for
    /// long-lived sessions where Apple's default URL loading
    /// behaviour — HTTP pipelining, URL cache, cookie storage — is
    /// desired.
    ///
    /// ### Example
    ///
    /// ```swift
    /// let client = TorClient(configuration: .ephemeral())
    /// try await client.start()
    /// try await client.waitUntilBootstrapped()
    /// let config = URLSessionConfiguration.configuredForTor(
    ///     socksEndpoint: await client.socksEndpoint!
    /// )
    /// let session = URLSession(configuration: config)
    /// let (data, _) = try await session.data(
    ///     from: URL(string: "https://check.torproject.org/api/ip")!
    /// )
    /// ```
    ///
    /// - Parameter endpoint: SOCKS5 proxy endpoint, typically
    ///   ``TorClient/socksEndpoint``.
    /// - Returns: A configuration with the SOCKS5 proxy installed.
    ///   All other defaults of `URLSessionConfiguration.default` are
    ///   preserved.
    ///
    /// - Important: The returned configuration **persists cookies,
    ///   caches, and credentials to disk** via the default shared
    ///   containers. For privacy-sensitive sessions, use
    ///   ``ephemeralConfiguredForTor(socksEndpoint:)`` instead.
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
    
    /// Build an ephemeral `URLSessionConfiguration` that routes every
    /// HTTP/HTTPS request through a SOCKS5 proxy.
    ///
    /// Starts from `URLSessionConfiguration.ephemeral` (no disk
    /// persistence of cookies, caches, or credentials) and installs
    /// the same SOCKS5 proxy dictionary as
    /// ``configuredForTor(socksEndpoint:)``. Preferred for
    /// one-shot or privacy-sensitive traffic where session state
    /// should not survive process exit.
    ///
    /// - Parameter endpoint: SOCKS5 proxy endpoint, typically
    ///   ``TorClient/socksEndpoint``.
    /// - Returns: An ephemeral configuration with the SOCKS5 proxy
    ///   installed.
    ///
    /// - Note: Ephemeral sessions still share Apple's in-memory URL
    ///   cache for the process lifetime; subsequent requests for the
    ///   same URL may short-circuit. Set `config.urlCache = nil` if
    ///   strict no-cache behaviour is required.
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

/// Convenience on ``TorClient`` for one-step `URLSession` wiring
/// against this instance's SOCKS endpoint.
extension TorClient {
    
    /// Return a ready-to-use `URLSession` that routes every request
    /// through this Tor instance's SOCKS5 proxy.
    ///
    /// Gates on ``TorClient/state`` being ``TorState/running`` and
    /// ``TorClient/socksEndpoint`` being non-`nil`, then delegates
    /// to `URLSessionConfiguration.configuredForTor(socksEndpoint:)`
    /// (or `URLSessionConfiguration.ephemeralConfiguredForTor(socksEndpoint:)`
    /// when `ephemeral` is `true`). Avoids the boilerplate of
    /// unwrapping `socksEndpoint` at every call site.
    ///
    /// - Parameter ephemeral: When `true`, uses the ephemeral
    ///   configuration (no disk persistence). Defaults to `false`.
    /// - Returns: A configured `URLSession` backed by the SOCKS5
    ///   proxy at ``socksEndpoint``.
    /// - Throws: ``TorError/notStarted`` when ``state`` is not
    ///   operational; ``TorError/controlUnavailable`` when the SOCKS
    ///   endpoint has not yet been discovered.
    ///
    /// - Important: Only call after
    ///   ``waitUntilBootstrapped(timeout:)`` has returned; until
    ///   Tor reaches 100% bootstrap, traffic through the returned
    ///   session will fail with `NSURLErrorNetworkConnectionLost`
    ///   or similar.
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
