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

/// Key-generation policy for an onion service (`ADD_ONION` first argument).
///
/// Maps 1:1 to the KeyType/KeyBlob syntax in control-spec.txt §3.27
/// (`ADD_ONION`). Two real choices are supported: ask Tor to generate a
/// fresh v3 key (``newV3(discardPrivateKey:)``) or supply an existing
/// ED25519-V3 private key to re-adopt a previously-registered service
/// (``providedV3(_:)``).
///
/// Only v3 is modelled — v2 (RSA-1024) was deprecated upstream in July
/// 2021 (Tor 0.4.6) and removed in 0.4.7, and is out of scope for
/// swift-tor.
///
/// - Note: Conformance is `Sendable`. The enum is not `Hashable` by
///   design: ``providedV3(_:)`` carries private-key material, and
///   pattern-matching or comparison on secrets is a security smell
///   better handled by the caller explicitly.
/// - Important: Private keys are ED25519 expanded secrets per
///   rend-spec-v3 §2.5 — the blob format Tor emits via `ADD_ONION`
///   responses. Do not attempt to construct them by hand; round-trip
///   through Tor or Apple's `CryptoKit.Curve25519.Signing`.
///
/// ## Topics
///
/// ### Cases
/// - ``newV3(discardPrivateKey:)``
/// - ``providedV3(_:)``
public enum OnionKeySpec: Sendable {
    /// Ask Tor to generate a fresh v3 onion service key pair.
    ///
    /// Corresponds to `ADD_ONION NEW:ED25519-V3` in control-spec.txt
    /// §3.27. Tor returns the fresh private key in the
    /// `ADD_ONION` reply **unless** `discardPrivateKey` is `true`, in
    /// which case the `DiscardPK` flag is added and no key material
    /// ever leaves Tor.
    ///
    /// - Parameter discardPrivateKey: When `true`, Tor generates the
    ///   key internally and omits it from the reply (`DiscardPK` flag).
    ///   Suitable for single-session ephemeral services. Default
    ///   `false` returns the private key for later re-adoption via
    ///   ``providedV3(_:)``.
    case newV3(discardPrivateKey: Bool = false)

    /// Re-adopt a previously-registered v3 service by its private key.
    ///
    /// Corresponds to `ADD_ONION ED25519-V3:<key>` in control-spec.txt
    /// §3.27. The blob must be exactly the string Tor handed back in
    /// an earlier `ADD_ONION` reply or via `GETINFO onions/current`.
    ///
    /// - Parameter key: The ED25519-V3 private key in Tor's
    ///   base64-encoded expanded-secret form (rend-spec-v3 §2.5).
    /// - Important: Treat the key as a secret. Persisting it to disk
    ///   or logs compromises the onion identity; use Keychain on Apple
    ///   platforms.
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

/// Where an onion service should forward inbound connections.
///
/// Corresponds to the `Target` field of an `ADD_ONION` port mapping in
/// control-spec.txt §3.27. Two target shapes are modelled: a TCP `host:port`
/// tuple on the local machine, or a Unix domain socket path. Pick the TCP
/// form for typical web-server integration; the Unix form when forwarding
/// into a socket-only backend (nginx FastCGI, Prometheus exporters, etc.).
///
/// - Note: Conformance is `Sendable` + `Hashable`. Hashability is safe
///   here — both payloads are public configuration, not secrets.
/// - Important: Tor does **not** validate the target at registration
///   time. Bad hosts / missing Unix paths surface as connection refusals
///   when a client dials the `.onion` address.
///
/// ## Topics
///
/// ### Cases
/// - ``tcp(host:port:)``
/// - ``unix(path:)``
public enum OnionPortTarget: Sendable, Hashable {
    /// Forward to a TCP endpoint.
    ///
    /// Typical use: `tcp(host: "127.0.0.1", port: 8080)` to forward to
    /// a local HTTP server. Non-loopback hosts are allowed but rarely
    /// desirable — routing onion traffic outside the machine defeats
    /// a key property of hidden services.
    ///
    /// - Parameters:
    ///   - host: Host the Tor process can reach via the kernel stack.
    ///   - port: TCP port on `host`.
    case tcp(host: String, port: Int)

    /// Forward to a Unix domain socket on the local filesystem.
    ///
    /// Renders to Tor's `unix:<path>` target form. The socket must
    /// exist at the time inbound connections arrive; Tor creates no
    /// file system entries on your behalf. Useful for integrating with
    /// backend daemons that accept connections on a named socket only.
    ///
    /// - Parameter path: Absolute filesystem path to the Unix socket.
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

/// A single virtual-port → target mapping advertised by an onion service.
///
/// Corresponds to one `Port=<virtualPort>,<target>` entry in an
/// `ADD_ONION` command (control-spec.txt §3.27). One
/// ``OnionService`` can carry multiple mappings — e.g. port 80 to a web
/// server, port 443 to the same server for TLS termination — by passing
/// an array of these to
/// ``TorControlClient/addOnion(key:ports:detach:)``.
///
/// - Note: Conformance is `Sendable` + `Hashable` so collections of
///   mappings can be deduplicated and compared verbatim.
/// - Important: The virtual port lives in the `.onion` namespace (what
///   clients dial); the target lives in the process's kernel address
///   space. They are independent and do not need to match.
///
/// ## Topics
///
/// ### Creating
/// - ``init(virtualPort:target:)``
/// - ``toLocalPort(_:localPort:)``
///
/// ### Inspection
/// - ``virtualPort``
/// - ``target``
public struct OnionPortMapping: Sendable, Hashable {
    /// The TCP port exposed on the `.onion` address.
    ///
    /// Dialled by Tor clients as `<serviceID>.onion:<virtualPort>`.
    /// Typical values follow well-known conventions: `80` for plain
    /// HTTP, `443` for HTTPS, `22` for SSH, or an application-specific
    /// port for bespoke protocols.
    ///
    /// - Stability: immutable.
    public let virtualPort: Int

    /// Where Tor should forward connections that arrive on
    /// ``virtualPort``.
    ///
    /// Either an IPv4/IPv6 TCP endpoint or a Unix domain socket, per
    /// ``OnionPortTarget``. Usually loopback (`127.0.0.1:<local>`)
    /// when the onion service fronts a locally-running backend.
    ///
    /// - Stability: immutable.
    public let target: OnionPortTarget

    /// Construct a mapping from an explicit virtual port and target.
    ///
    /// Use when you need a non-loopback target or a Unix-socket
    /// destination. For the common case of forwarding to `127.0.0.1`,
    /// prefer the ``toLocalPort(_:localPort:)`` factory.
    ///
    /// - Parameters:
    ///   - virtualPort: Port exposed on the `.onion` address.
    ///   - target: Forwarding destination.
    public init(virtualPort: Int, target: OnionPortTarget) {
        self.virtualPort = virtualPort
        self.target = target
    }

    /// Convenience factory for loopback TCP mappings.
    ///
    /// Expands to
    /// `OnionPortMapping(virtualPort: virtualPort, target: .tcp(host: "127.0.0.1", port: localPort))`.
    /// Covers the overwhelmingly common case of an onion service
    /// fronting a locally-running HTTP, SSH, or application server.
    ///
    /// - Parameters:
    ///   - virtualPort: Port dialled on the `.onion` address.
    ///   - localPort: TCP port on `127.0.0.1` to forward to.
    /// - Returns: A mapping with ``target`` set to
    ///   ``OnionPortTarget/tcp(host:port:)`` at `127.0.0.1:<localPort>`.
    public static func toLocalPort(_ virtualPort: Int, localPort: Int) -> OnionPortMapping {
        OnionPortMapping(virtualPort: virtualPort, target: .tcp(host: "127.0.0.1", port: localPort))
    }
    
    /// Returns the port specification for the ADD_ONION command.
    var portSpec: String {
        "Port=\(virtualPort),\(target.targetString)"
    }
}

/// A successfully-created onion service, as returned by `ADD_ONION`.
///
/// Value-type record carrying the service identifier, an optional
/// private key (present iff ``OnionKeySpec/newV3(discardPrivateKey:)``
/// was called with `discardPrivateKey: false`), and the creation
/// timestamp. Constructed by ``TorControlClient/addOnion(key:ports:detach:)``
/// from the parsed `ADD_ONION` reply; callers can also construct one
/// directly for tests or persisted state replay.
///
/// Per rend-spec-v3 §6, a v3 service identifier is a 56-character
/// base32-encoded string (without the `.onion` suffix). Combine with
/// ``onionAddress`` for the fully-qualified address clients dial.
///
/// - Note: Conformance is `Sendable`. Deliberately **not** `Hashable`:
///   ``privateKey`` carries secret material, and the creation
///   timestamp would poison any hash.
/// - Important: ``privateKey`` is secret material. Never log, diff, or
///   serialise it to stdout. Persist only via Keychain (Apple) or an
///   equivalent credential store.
///
/// ## Topics
///
/// ### Creating
/// - ``init(serviceID:privateKey:createdAt:)``
///
/// ### Inspection
/// - ``serviceID``
/// - ``onionAddress``
/// - ``privateKey``
/// - ``createdAt``
public struct OnionService: Sendable {
    /// The 56-character v3 service identifier (without `.onion`).
    ///
    /// Base32-encoded public key hash per rend-spec-v3 §6. Stable for
    /// the lifetime of the key — re-adopting the same private key via
    /// ``OnionKeySpec/providedV3(_:)`` yields the same `serviceID`.
    ///
    /// - Stability: immutable.
    public let serviceID: String

    /// Base64-encoded ED25519-V3 private key, or `nil` if discarded.
    ///
    /// Populated when `ADD_ONION` was called **without** `DiscardPK`.
    /// Persist in a secure store to later re-adopt the service via
    /// ``OnionKeySpec/providedV3(_:)``. `nil` indicates the key was
    /// generated with `discardPrivateKey: true` and cannot be recovered.
    ///
    /// - Important: Secret material — see the type-level `Important`
    ///   note on storage.
    public let privateKey: String?

    /// Wall-clock time at which this value was constructed.
    ///
    /// Defaults to `Date()` at init time. Useful for TTL tracking in
    /// long-running sessions that create many short-lived services.
    /// Does **not** survive a Tor restart — ``TorControlClient`` does
    /// not retrieve the original creation time when re-adopting a
    /// service.
    ///
    /// - Stability: immutable.
    public let createdAt: Date

    /// Fully-qualified `.onion` address: `"<serviceID>.onion"`.
    ///
    /// Convenience for interpolation into URLs and connection strings.
    /// A Tor-aware client dialling this address traverses the Tor
    /// network to reach whatever ``OnionPortMapping/target`` was
    /// registered for the requested port.
    ///
    /// - Returns: A string of the form `"<serviceID>.onion"`.
    public var onionAddress: String {
        "\(serviceID).onion"
    }

    /// Memberwise initialiser for test fixtures and replay.
    ///
    /// Most callers receive `OnionService` values from
    /// ``TorControlClient/addOnion(key:ports:detach:)`` rather than
    /// constructing them by hand. Construct directly when seeding
    /// persisted state into a new ``TorClient``, building golden test
    /// fixtures, or unit-testing code that consumes `OnionService`.
    ///
    /// - Parameters:
    ///   - serviceID: The 56-character v3 identifier.
    ///   - privateKey: Optional key blob. Pass `nil` (the default) for
    ///     services whose key was discarded.
    ///   - createdAt: Creation timestamp. Defaults to `Date()`.
    public init(serviceID: String, privateKey: String? = nil, createdAt: Date = Date()) {
        self.serviceID = serviceID
        self.privateKey = privateKey
        self.createdAt = createdAt
    }
}
