//
//  HostPort.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Immutable `host` + `port` pair representing a TCP network endpoint.
///
/// swift-tor uses `HostPort` wherever the library crosses a TCP boundary:
/// the SOCKS5 proxy surfaced by ``TorClient/socksEndpoint``, the optional
/// control port accepted by `TorControlClient(host:port:)`, and the
/// forwarding target on an ``OnionPortTarget/tcp(host:port:)`` mapping. It
/// is a deliberately minimal value type — a `String` + `Int` pair with
/// printable formatting — rather than a validating type. Address families,
/// DNS resolution, and port-range enforcement are deferred to the POSIX
/// socket layer in ``ControlSocket`` and to Apple's CFNetwork proxy
/// resolver; a `HostPort` is simply a typed seat at those APIs.
///
/// The shape aligns with RFC 3986 authority components ([RFC 3986 §3.2.2](https://datatracker.ietf.org/doc/html/rfc3986#section-3.2.2))
/// and with SOCKS5's host-plus-port addressing model ([RFC 1928 §4](https://datatracker.ietf.org/doc/html/rfc1928#section-4)).
///
/// - Note: `HostPort` conforms to `Sendable` (value type, all fields
///   `Sendable`) and to `Hashable` (synthesised — both fields are
///   `Hashable`). Equality is case- and digit-exact; `"LocalHost"` and
///   `"localhost"` are distinct instances.
/// - Important: No validation is performed. Out-of-range ports, malformed
///   IPv6 literals, and unresolvable hostnames surface as
///   ``TorError/ioError(_:)`` at connection time — not at construction.
///
/// ## See Also
/// - ``TorClient/socksEndpoint``
/// - ``ControlSocket/init(endpoint:)``
/// - ``OnionPortTarget``
public struct HostPort: Sendable, Hashable, CustomStringConvertible {
    /// The host portion of the endpoint, interpreted exactly as written.
    ///
    /// Accepted forms mirror the POSIX `getaddrinfo(3)` + SOCKS5 address
    /// types: a dotted IPv4 literal (`"127.0.0.1"`), a DNS name (`"localhost"`,
    /// `"torproxy.internal"`), or a raw IPv6 literal (`"::1"`). **IPv6
    /// literals are not auto-bracketed by ``description``**, so callers
    /// producing URLs or proxy tuples from a `HostPort` must bracket the
    /// host themselves (e.g. `"[::1]:9050"`) per [RFC 3986 §3.2.2](https://datatracker.ietf.org/doc/html/rfc3986#section-3.2.2).
    ///
    /// - Stability: immutable (`let`) — changes require constructing a new
    ///   `HostPort`.
    /// - Typical values: `"127.0.0.1"` for SOCKS/control endpoints, a
    ///   `.onion` hostname when populating `OnionPortTarget`, or a local
    ///   `"localhost"` alias when a DNS lookup is cheap enough.
    public let host: String

    /// The TCP port number.
    ///
    /// Typed as `Int` for ergonomics; valid values are **1–65535**
    /// ([RFC 6335 §6](https://datatracker.ietf.org/doc/html/rfc6335#section-6)),
    /// but the initializer does not enforce the range. A value outside
    /// that range is accepted at construction and rejected by `connect(2)`
    /// when the endpoint is actually dialled, surfacing as
    /// ``TorError/ioError(_:)``.
    ///
    /// - Stability: immutable (`let`).
    /// - Typical values: `9050` (Tor SOCKS5 default), `9051` (Tor control
    ///   port default), `80` / `443` for onion-service forwarding targets.
    public let port: Int

    /// Memberwise initializer for the `host` and `port` pair.
    ///
    /// Assigns both fields verbatim; no canonicalisation, no validation.
    /// Construct once, compare freely — the value is `Hashable`/`Sendable`
    /// and safely crosses concurrency domains.
    ///
    /// - Parameters:
    ///   - host: Host component. See ``host`` for accepted forms.
    ///   - port: TCP port, typically 1–65535.
    ///
    /// - Note: If you always mean loopback, prefer ``localhost(_:)`` to
    ///   avoid repeating the literal `"127.0.0.1"` at call sites.
    /// - Important: Case and whitespace in `host` are preserved literally.
    ///   `HostPort(host: " localhost", port: 9050)` is **not** equal to
    ///   `HostPort(host: "localhost", port: 9050)`.
    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    /// Returns a loopback endpoint (`127.0.0.1:port`) for the given port.
    ///
    /// Convenience factory for the most common shape of `HostPort` inside
    /// swift-tor: Tor's SOCKS and control endpoints both live on the
    /// loopback interface, and the overwhelming majority of callers never
    /// need a non-loopback host. Using this factory makes it impossible
    /// to typo `"127.0.0.1"` at call sites and keeps intent explicit.
    ///
    /// - Parameter port: TCP port on 127.0.0.1.
    /// - Returns: A fresh `HostPort` with `host == "127.0.0.1"`.
    ///
    /// - Note: This factory always returns an **IPv4** loopback. If you
    ///   need IPv6 loopback (`::1`), construct the value explicitly via
    ///   ``init(host:port:)``. The two loopback families are distinct at
    ///   the kernel socket layer and will not unify on `connect(2)`.
    /// - Important: The string literal `"localhost"` is deliberately **not**
    ///   used here to avoid an unnecessary DNS lookup on Apple platforms.
    public static func localhost(_ port: Int) -> HostPort {
        HostPort(host: "127.0.0.1", port: port)
    }

    /// Returns `"host:port"` with no transformation of either component.
    ///
    /// Intended for log lines and error messages. The format is
    /// intentionally unquoted, unbracketed, and unescaped: `description`
    /// is not a URL authority component and must not be treated as one.
    ///
    /// - Returns: The string `"\(host):\(port)"`.
    ///
    /// - Important: For IPv6 literals the result is ambiguous (the colons
    /// in the address collide with the `host`/`port` separator). Callers
    /// producing URLs or proxy dictionaries from a `HostPort` with an
    /// IPv6 host must bracket the host themselves, e.g.
    /// `HostPort(host: "[::1]", port: 9050).description == "[::1]:9050"`.
    /// - SeeAlso: [RFC 3986 §3.2.2](https://datatracker.ietf.org/doc/html/rfc3986#section-3.2.2)
    /// on URI host syntax.
    public var description: String {
        "\(host):\(port)"
    }
}
