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

/// Three-way policy describing how Tor should bind a configurable port.
///
/// `PortPolicy` is the typed counterpart to the port-number argument that
/// appears on Tor's `SocksPort`, `ControlPort`, and related torrc options
/// (tor.1.txt). Rather than force callers to pass magic integers
/// (`0` to disable, `auto` to let Tor pick), the enum models the three
/// real choices and renders to the correct torrc token on demand via its
/// ``description``.
///
/// - Note: Conformance is `Sendable` + `Hashable` + `CustomStringConvertible`.
///   The rendered string `description` is **deliberately identical** to the
///   torrc token so you can interpolate directly into configuration
///   strings; programmatic tests should pattern-match on the enum cases.
/// - Important: Only swift-tor's SOCKS port currently uses this type. The
///   control port is always bound by `tor_main_configuration_setup_control_socket()`
///   and is not configurable via `PortPolicy`.
///
/// ## Topics
///
/// ### Policies
/// - ``ephemeral``
/// - ``fixed(_:)``
/// - ``disabled``
///
/// ### Rendering
/// - ``description``
public enum PortPolicy: Sendable, Hashable, CustomStringConvertible {
    /// Let Tor pick any unused TCP port on the loopback interface.
    ///
    /// Renders to torrc token `"auto"`. The chosen port surfaces as
    /// ``TorClient/socksEndpoint`` once Tor reaches ``TorState/running``.
    /// Default for ``TorConfiguration/socksPort`` because it avoids port
    /// collisions in test suites and multi-instance deployments.
    case ephemeral

    /// Bind the SOCKS port to an exact TCP port number.
    ///
    /// Renders to the literal integer. Use when downstream code expects
    /// a fixed endpoint (e.g. `9050`, the well-known Tor SOCKS default).
    /// Tor fails to start with a port-in-use error if another process
    /// already holds the port — surfaces as ``TorError/startFailed(_:)``.
    case fixed(Int)

    /// Disable the port entirely.
    ///
    /// Renders to torrc token `"0"` (Tor's convention for "no binding").
    /// Use for embedded deployments that perform all traffic routing
    /// through the control protocol and need no SOCKS interface.
    case disabled

    /// Torrc-compatible rendering of this policy.
    ///
    /// Identical to the token appended to the `--SocksPort` command-line
    /// argument: `"auto"`, `"<n>"`, or `"0"`. Stable across releases; safe
    /// to embed in persisted configuration files.
    ///
    /// - Returns: `"auto"`, the fixed port as a decimal string, or `"0"`.
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

/// Value-type configuration passed to ``TorClient`` at construction time.
///
/// `TorConfiguration` is the Swift-side projection of the subset of
/// torrc options swift-tor exposes to callers. All fields map either to
/// a torrc directive (`DataDirectory`, `CacheDirectory`, `SocksPort`,
/// `CookieAuthentication`, `HashedControlPassword` — see tor.1.txt) or to
/// a swift-tor-only convenience (``ownsDataDirectory``, ``extraArgs``).
/// The struct is `var`-mutable on purpose: construct a baseline via
/// ``makeDefault()`` or ``ephemeral(cacheDirectory:)`` and then override
/// individual fields without using an explicit builder.
///
/// - Note: Conformance is `Sendable` — every field is a value type and
///   safely crosses concurrency domains. The struct is **not**
///   `Equatable`; mutations through an `inout` binding replace the whole
///   value via COW.
/// - Important: Once a ``TorClient`` is constructed, its `configuration`
///   is frozen for the life of that session. Mutating the original
///   struct does not affect a running Tor instance; changes take effect
///   only on the next start.
///
/// ## Topics
///
/// ### Core paths
/// - ``dataDirectory``
/// - ``cacheDirectory``
/// - ``ownsDataDirectory``
///
/// ### Ports & auth
/// - ``socksPort``
/// - ``cookieAuthentication``
/// - ``controlPassword``
///
/// ### Extras
/// - ``extraArgs``
///
/// ### Construction
/// - ``init(dataDirectory:cacheDirectory:socksPort:cookieAuthentication:controlPassword:extraArgs:ownsDataDirectory:)``
/// - ``makeDefault()``
/// - ``ephemeral(cacheDirectory:)``
public struct TorConfiguration: Sendable {
    /// Filesystem path where Tor will store persistent state.
    ///
    /// Maps to torrc `DataDirectory` (tor.1.txt). Tor creates
    /// subdirectories for keys (`keys/`), cached network state
    /// (`cached-*`), and lock files. The directory is created if it does
    /// not exist — the parent must be writable by the current process.
    ///
    /// - Typical values: a UUID-suffixed path under
    ///   `FileManager.default.temporaryDirectory` for per-session use
    ///   (see ``ephemeral(cacheDirectory:)``), or a stable app-scoped
    ///   path under `Application Support` / `.local/share` for
    ///   long-running clients.
    /// - Important: Never point multiple concurrent Tor instances at the
    ///   same `dataDirectory` — Tor enforces a lockfile and the second
    ///   process will fail to start with
    ///   ``TorError/startFailed(_:)``.
    public var dataDirectory: String

    /// Optional separate path for cached consensus and descriptor files.
    ///
    /// Maps to torrc `CacheDirectory` (tor.1.txt). When set, Tor stores
    /// `cached-certs`, `cached-microdesc-consensus`, and related files
    /// here instead of under ``dataDirectory``, allowing the consensus
    /// cache to outlive an ephemeral data directory.
    ///
    /// - Performance: reusing a warm cache across runs drops cold-boot
    ///   bootstrap time from ~30–60 seconds to ~5–10 seconds. For CI and
    ///   interactive apps this is the single most impactful optimisation.
    /// - Important: The cache directory is **never** deleted by
    ///   ``TorClient/stop()``, even when ``ownsDataDirectory`` is `true`.
    ///   Manage its lifecycle at the application layer.
    public var cacheDirectory: String?

    /// Policy for Tor's SOCKS5 listener port.
    ///
    /// Maps to torrc `SocksPort` (tor.1.txt). See ``PortPolicy`` for the
    /// three-way choice. Defaults to ``PortPolicy/ephemeral`` — the
    /// chosen port surfaces as ``TorClient/socksEndpoint`` once Tor
    /// reaches ``TorState/running``.
    public var socksPort: PortPolicy

    /// Request Tor to bind a cookie-authenticated control port.
    ///
    /// Maps to torrc `CookieAuthentication` (tor.1.txt). **Not normally
    /// needed** for embedded deployments: swift-tor uses
    /// `tor_main_configuration_setup_control_socket()` to obtain a
    /// pre-authenticated control socket, which bypasses cookie/password
    /// auth entirely. Set this only when exposing an external control
    /// port over TCP.
    ///
    /// Defaults to `false`. See control-spec.txt §3.5 for the cookie
    /// authentication handshake.
    public var cookieAuthentication: Bool

    /// Optional password used when `HashedControlPassword` is configured.
    ///
    /// Maps to torrc `HashedControlPassword` (tor.1.txt). The supplied
    /// value **must already be hashed** (use `tor --hash-password <pw>`
    /// to produce the `16:<hex>` form). Used only when
    /// ``cookieAuthentication`` is `false` AND a caller is dialling an
    /// external control port; the embedded pre-authenticated socket
    /// ignores this field.
    ///
    /// - Important: Do not commit this value to source control. Inject
    ///   from Keychain (Apple) or environment variables (Linux).
    public var controlPassword: String?

    /// Escape hatch for torrc directives swift-tor does not yet model.
    ///
    /// Every element is appended verbatim to the argv passed to
    /// `tor_main_configuration_set_command_line()`. Pairs are expressed
    /// as two elements — `["--ClientUseIPv6", "1"]` — since Tor parses
    /// the argv directly without quote handling.
    ///
    /// - Important: No validation is performed. A typo reaches Tor's
    ///   parser and surfaces as ``TorError/startFailed(_:)``.
    public var extraArgs: [String]

    /// If `true`, ``TorClient/stop()`` removes ``dataDirectory`` after
    /// Tor exits.
    ///
    /// Swift-tor-only convenience; no corresponding torrc option. Lets
    /// callers bind an ephemeral session to a UUID-suffixed temp
    /// directory and know that a clean ``TorClient/stop()`` will leave no
    /// state on disk — ideal for tests, CLI one-shots, and privacy-
    /// sensitive UI sessions.
    ///
    /// - Defaults to `false` to preserve backward compatibility with
    ///   long-lived data directories. ``ephemeral(cacheDirectory:)``
    ///   sets this to `true`.
    /// - Important: Only ``dataDirectory`` is removed; ``cacheDirectory``
    ///   is preserved so its warm-cache benefit survives across sessions.
    public var ownsDataDirectory: Bool

    /// Memberwise initialiser with sensible defaults for every field.
    ///
    /// Construct a `TorConfiguration` directly when the convenience
    /// factories (``makeDefault()``, ``ephemeral(cacheDirectory:)``) do
    /// not fit — e.g. a stable app-scoped data directory combined with a
    /// fixed `9050` SOCKS port for downstream compatibility. All
    /// optional parameters default to the values that most embedded
    /// deployments want; override only what you need to change.
    ///
    /// - Parameters:
    ///   - dataDirectory: Required filesystem path for Tor state. See
    ///     ``dataDirectory`` for collision rules.
    ///   - cacheDirectory: Optional consensus-cache path for warm-boot
    ///     performance; defaults to `nil` (cache lives inside
    ///     `dataDirectory`).
    ///   - socksPort: SOCKS port policy. Defaults to ``PortPolicy/ephemeral``.
    ///   - cookieAuthentication: Enable torrc `CookieAuthentication`.
    ///     Defaults to `false` — the embedded control socket is
    ///     pre-authenticated so this is rarely needed.
    ///   - controlPassword: Optional `HashedControlPassword` value.
    ///   - extraArgs: Escape-hatch argv pairs; defaults to `[]`.
    ///   - ownsDataDirectory: Whether to delete `dataDirectory` on
    ///     ``TorClient/stop()``. Defaults to `false`.
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
    
    /// Returns a configuration rooted at a fresh UUID-suffixed temp
    /// directory.
    ///
    /// Convenience factory for tests and throwaway sessions: generates a
    /// new `FileManager.default.temporaryDirectory/tor-<UUID>` path and
    /// leaves ``ownsDataDirectory`` at its default `false`. Prefer
    /// ``ephemeral(cacheDirectory:)`` if you want the directory cleaned
    /// up on ``TorClient/stop()``.
    ///
    /// - Returns: A `TorConfiguration` with a unique `dataDirectory`,
    ///   ephemeral SOCKS port, and no cache directory.
    ///
    /// - Note: Two calls in quick succession produce distinct
    ///   configurations — UUIDs guarantee no directory collision even
    ///   when parallel tests race to construct clients.
    public static func makeDefault() -> TorConfiguration {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tor-\(UUID().uuidString)")
            .path
        return TorConfiguration(dataDirectory: tempDir)
    }

    /// Returns a fully self-cleaning ephemeral configuration, optionally
    /// keeping a warm cache.
    ///
    /// Intended for per-session embedded Tor usage where the caller wants
    /// zero residual state on disk after ``TorClient/stop()`` returns.
    /// Internally: UUID-suffixed temp directory, ``ownsDataDirectory`` set
    /// to `true`, and ``cacheDirectory`` optionally pointed at a
    /// caller-owned warm cache.
    ///
    /// - Parameter cacheDirectory: Optional persistent cache path. The
    ///   cache is **not** removed on stop, so this is the single most
    ///   effective way to drop subsequent bootstrap times from ~40s to
    ///   ~5–10s.
    /// - Returns: A `TorConfiguration` that fully disposes of its data
    ///   directory on shutdown while optionally reusing a warm cache.
    ///
    /// - Important: The cache directory is shared across sessions and
    ///   must survive process death. Store it under a stable
    ///   app-scoped path (not `tmp`).
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
