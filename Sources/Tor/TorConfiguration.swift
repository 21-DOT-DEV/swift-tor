//
//  TorConfiguration.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Policy for configuring a network port.
public enum PortPolicy: Sendable, Hashable, CustomStringConvertible {
    /// Let Tor choose an available port automatically.
    case ephemeral
    
    /// Use a specific port number.
    case fixed(Int)
    
    /// Disable this port entirely.
    case disabled
    
    public var description: String {
        switch self {
        case .ephemeral: return "auto"
        case .fixed(let port): return "\(port)"
        case .disabled: return "0"
        }
    }
    
    /// Returns the Tor configuration value for this port policy.
    var torConfigValue: String {
        switch self {
        case .ephemeral: return "auto"
        case .fixed(let port): return "\(port)"
        case .disabled: return "0"
        }
    }
}

/// Configuration for a Tor instance.
public struct TorConfiguration: Sendable {
    /// Path to the data directory where Tor stores its state.
    public var dataDirectory: String
    
    /// Optional separate directory for cached consensus and relay descriptors.
    ///
    /// If set, Tor will store cached-certs, cached-microdesc-consensus, and
    /// cached-microdescs files in this directory instead of the data directory.
    /// This allows caching to persist even when using ephemeral data directories.
    ///
    /// **Performance tip**: Reusing a cache directory across runs can reduce
    /// bootstrap time from ~40 seconds to ~5-10 seconds.
    public var cacheDirectory: String?
    
    /// SOCKS port configuration.
    public var socksPort: PortPolicy
    
    /// Whether to enable cookie authentication for the control connection.
    /// When using the embedded control socket, this is typically not needed.
    public var cookieAuthentication: Bool
    
    /// Optional password for control port authentication.
    /// Only used if cookie authentication is disabled.
    public var controlPassword: String?
    
    /// Additional command-line arguments to pass to Tor.
    public var extraArgs: [String]

    /// When `true`, `TorClient.stop()` removes `dataDirectory` after shutdown.
    ///
    /// Use this for per-session ephemeral instances where Tor state should
    /// not persist across restarts. Defaults to `false` to preserve backward
    /// compatibility with long-lived data directories.
    public var ownsDataDirectory: Bool

    /// Creates a Tor configuration with the specified options.
    /// - Parameters:
    ///   - dataDirectory: Path to the data directory.
    ///   - cacheDirectory: Optional separate cache directory for consensus data.
    ///   - socksPort: SOCKS port configuration. Defaults to `.ephemeral`.
    ///   - cookieAuthentication: Enable cookie auth. Defaults to `false` (control socket is pre-authenticated).
    ///   - controlPassword: Optional password for control auth.
    ///   - extraArgs: Additional Tor arguments.
    ///   - ownsDataDirectory: When `true`, `TorClient.stop()` removes `dataDirectory`. Defaults to `false`.
    public init(
        dataDirectory: String,
        cacheDirectory: String? = nil,
        socksPort: PortPolicy = .ephemeral,
        cookieAuthentication: Bool = false,
        controlPassword: String? = nil,
        extraArgs: [String] = [],
        ownsDataDirectory: Bool = false
    ) {
        self.dataDirectory = dataDirectory
        self.cacheDirectory = cacheDirectory
        self.socksPort = socksPort
        self.cookieAuthentication = cookieAuthentication
        self.controlPassword = controlPassword
        self.extraArgs = extraArgs
        self.ownsDataDirectory = ownsDataDirectory
    }
    
    /// Creates a default configuration using a temporary directory.
    /// - Returns: A configuration suitable for testing or ephemeral use.
    public static func makeDefault() -> TorConfiguration {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tor-\(UUID().uuidString)")
            .path
        return TorConfiguration(dataDirectory: tempDir)
    }

    /// Creates an ephemeral configuration whose data directory is auto-cleaned on stop.
    ///
    /// The returned configuration uses a fresh UUID-based temp directory for
    /// `dataDirectory` and sets `ownsDataDirectory = true` so the directory is
    /// removed automatically when `TorClient.stop()` returns.
    ///
    /// - Parameter cacheDirectory: Optional persistent cache directory (consensus
    ///   data) to retain across runs for faster re-bootstrap. Only the data
    ///   directory is removed on stop; the cache directory is preserved.
    /// - Returns: A configuration suitable for per-session embedded Tor usage.
    public static func ephemeral(cacheDirectory: String? = nil) -> TorConfiguration {
        let dataDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tor-\(UUID().uuidString)")
            .path
        return TorConfiguration(
            dataDirectory: dataDir,
            cacheDirectory: cacheDirectory,
            ownsDataDirectory: true
        )
    }
    
    /// Builds the command-line arguments for Tor.
    /// - Returns: An array of arguments to pass to `tor_main_configuration_set_command_line`.
    func buildArguments() -> [String] {
        var args = ["tor"]
        
        args.append(contentsOf: ["--DataDirectory", dataDirectory])
        args.append(contentsOf: ["--SocksPort", socksPort.torConfigValue])
        
        if let cacheDir = cacheDirectory {
            args.append(contentsOf: ["--CacheDirectory", cacheDir])
        }
        
        if cookieAuthentication {
            args.append(contentsOf: ["--CookieAuthentication", "1"])
        }
        
        if let password = controlPassword {
            args.append(contentsOf: ["--HashedControlPassword", password])
        }
        
        args.append(contentsOf: extraArgs)
        
        return args
    }
}
