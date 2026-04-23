//
//  TorSession.swift
//  swift-tor
//
//  Copyright (c) 2025 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Minimal lifecycle interface for driving (or mocking) an embedded Tor
/// instance.
///
/// `TorSession` is the seam between swift-tor's concrete ``TorClient`` actor
/// and downstream code that wants to exercise Tor's lifecycle without
/// paying the real-world cost of it. A production conformer launches
/// `tor_run_main()` on a dedicated thread, negotiates with the Tor network
/// (guard selection, consensus download, circuit build — typically
/// 30–60 s), and exposes the SOCKS endpoint when complete. A test
/// conformer returns a fabricated endpoint immediately, pushes synthetic
/// ``TorEvent`` values through its ``events`` stream, and never touches
/// the network.
///
/// The surface is deliberately narrow: one method each for start/stop/wait,
/// one async-get property for the SOCKS endpoint, and one stream property
/// for lifecycle events. Anything richer (`GETINFO`, `addOnion`, URLSession
/// proxy helpers) lives on ``TorClient`` directly and is out of scope for
/// mocking through this protocol.
///
/// - Note: Conformance is `Sendable` — all methods are `async` (or `async
///   throws`) and all properties are `async` getters, so implementations
///   are free to use actor isolation, `Mutex`, or any other serialisation
///   strategy for internal state.
/// - Important: Mock conformers should preserve causal ordering: a call to
///   ``waitUntilBootstrapped(timeout:)-(Duration)`` must observe at least
///   one ``start()`` before returning successfully, otherwise downstream
///   state machines that assume "bootstrapped implies started" will drift.
///
/// ## Topics
///
/// ### Lifecycle
/// - ``start()``
/// - ``stop()``
/// - ``waitUntilBootstrapped(timeout:)-(Duration)``
/// - ``waitUntilBootstrapped()``
///
/// ### Observing state
/// - ``socksEndpoint``
/// - ``events``
public protocol TorSession: Sendable {
    /// Start the underlying Tor instance.
    ///
    /// In a production conformer this creates the data directory, hands
    /// `torrc`-equivalent configuration to `tor_main_configuration_new()`,
    /// runs `tor_run_main()` on a dedicated background thread, and resolves
    /// once the embedded control socket is reachable — but **before** the
    /// Tor network bootstrap has made progress. Pair with
    /// ``waitUntilBootstrapped(timeout:)-(Duration)`` to block until Tor
    /// is actually usable for relaying traffic.
    ///
    /// Mock conformers typically resolve this immediately or fail fast
    /// per their test scenario.
    ///
    /// - Throws: An implementation-defined error if the instance cannot be
    ///   started. Production conformer throws ``TorError/alreadyStarted``
    ///   if invoked while Tor is running or starting, and
    ///   ``TorError/startFailed(_:)`` if `tor_run_main()` returns an error.
    func start() async throws

    /// Block until Tor reports 100% bootstrap progress, or fail after
    /// `timeout`.
    ///
    /// Bootstrap progress is driven by the Tor control-protocol
    /// `status/bootstrap-phase` `GETINFO` key (control-spec.txt §3.9) and
    /// surfaces as ``TorEvent/bootstrap(progress:tag:summary:)`` on the ``events`` stream.
    /// Typical cold-boot bootstrap on a public guard takes 30–60 seconds;
    /// a warm boot with a reused `cacheDirectory` can complete in 5–10
    /// seconds (see `TorConfiguration.cacheDirectory` performance tip).
    ///
    /// - Parameter timeout: Maximum `Duration` to wait before throwing.
    /// - Throws: ``TorError/timeout`` when `timeout` elapses before 100%
    ///   bootstrap is reached, and ``TorError/notStarted`` if the session
    ///   is idle/stopped when invoked.
    ///
    /// - Note: Progress is strictly monotonic — an event at 75% implies
    ///   every lower-percentage event has already been delivered.
    func waitUntilBootstrapped(timeout: Duration) async throws

    /// Stop the Tor instance and release any resources.
    ///
    /// Stopping is best-effort and non-throwing: if Tor is already idle,
    /// stopped, or in `.failed`, this is a no-op. A running production
    /// conformer sends `SIGNAL SHUTDOWN` through its embedded control
    /// client (per control-spec.txt §3.7), waits for `tor_run_main()` to
    /// return, closes the control socket, and optionally removes the data
    /// directory when `configuration.ownsDataDirectory` is true.
    ///
    /// - Important: After this call returns, the ``events`` stream is
    ///   terminated (no more values are emitted) and ``socksEndpoint``
    ///   reverts to `nil`. Calling ``start()`` again on the same instance
    ///   is supported and creates a fresh data directory when
    ///   `configuration` specifies an ephemeral path.
    func stop() async

    /// Tor's local SOCKS5 proxy endpoint, `nil` until the port is known.
    ///
    /// Becomes non-`nil` shortly after ``start()`` resolves, when the
    /// production conformer has negotiated an ephemeral TCP port with the
    /// embedded Tor process (or used the fixed port from
    /// `TorConfiguration.socksPort`). The endpoint is safe to hand to
    /// `URLSessionConfiguration.configuredForTor(socksEndpoint:)` on
    /// Apple platforms or to any other SOCKS5-aware client per
    /// [RFC 1928](https://datatracker.ietf.org/doc/html/rfc1928).
    ///
    /// - Stability: `host` is `127.0.0.1` and stable for the session;
    ///   `port` depends on `TorConfiguration.socksPort` and is chosen once.
    /// - Typical value: `HostPort(host: "127.0.0.1", port: 58432)` with an
    ///   ephemeral port, or `HostPort(host: "127.0.0.1", port: 9050)` with
    ///   a fixed port.
    var socksEndpoint: HostPort? { get async }

    /// Back-pressure-aware async stream of ``TorEvent`` values for this
    /// session.
    ///
    /// Each access returns a **fresh** subscriber stream — conformers are
    /// expected to multiplex events to all live subscribers, so two
    /// consumers see identical sequences (no fan-in, no replay of past
    /// events). Conformers must complete the stream exactly once, when
    /// ``stop()`` fully releases resources.
    ///
    /// - Stability: values are delivered in causal order; a
    ///   `.bootstrap(progress: 100)` event is never observed before some
    ///   `.stateChanged(.starting)` event.
    /// - Typical use: subscribe in a background `Task` that logs, updates
    ///   a SwiftUI `@Observable` state model, or applies backoff when
    ///   ``TorEvent/stateChanged(_:)`` reports `.failed(_)`.
    /// - Important: Subscribers that stop consuming will eventually cause
    ///   the conformer to apply back-pressure or drop events — the
    ///   buffering policy is implementation-defined. Always consume or
    ///   explicitly cancel the task holding the iterator.
    var events: AsyncStream<TorEvent> { get async }
}

extension TorSession {
    /// Wait up to the default 120-second bootstrap window.
    ///
    /// Convenience shorthand for the overwhelmingly common case in which
    /// the caller has no opinion about the timeout: 120 seconds is long
    /// enough to cover cold boots on slow connections but short enough
    /// that failure surfaces well before the user gives up. Forwards
    /// directly to ``waitUntilBootstrapped(timeout:)-(Duration)`` with
    /// `.seconds(120)`.
    ///
    /// - Throws: ``TorError/timeout`` if bootstrap exceeds 120 seconds,
    ///   ``TorError/notStarted`` if the session is not running.
    ///
    /// - Note: For CI jobs, tests, or interactive UIs that want to show
    ///   a spinner timeout sooner, call the full
    ///   ``waitUntilBootstrapped(timeout:)-(Duration)`` with a tighter
    ///   `Duration`.
    public func waitUntilBootstrapped() async throws {
        try await waitUntilBootstrapped(timeout: .seconds(120))
    }
}

// MARK: - TorClient conformance

/// Declare ``TorClient``'s retroactive conformance to ``TorSession``.
///
/// All protocol requirements are already satisfied by ``TorClient``'s
/// primary declaration (same method names, signatures, and actor isolation),
/// so the extension is intentionally empty. Keep it present so the
/// conformance is visible at the module boundary — dependency-injected
/// call sites refer to `any TorSession`, not to the concrete actor.
extension TorClient: TorSession {}
