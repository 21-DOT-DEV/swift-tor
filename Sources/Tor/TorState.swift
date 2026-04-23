//
//  TorState.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Six-case lifecycle enum describing an embedded Tor instance.
///
/// `TorState` is the coarse-grained state machine exposed by ``TorClient``
/// and ``TorSession``. Transitions are driven by the life cycle of
/// Tor's `tor_run_main()` thread plus observed control-protocol events
/// from control-spec.txt §4 (async events), summarised here as a finite
/// enum so SwiftUI and state-machine code can switch exhaustively.
///
/// Legal transitions (no other transition is reachable in production):
///
/// ```
///     .idle      → .starting
///     .starting  → .running   | .failed(_)
///     .running   → .stopping  | .failed(_)
///     .stopping  → .stopped   | .failed(_)
///     .stopped   → .starting
///     .failed(_) → .starting
/// ```
///
/// - Note: `TorState` conforms to `Sendable`, `Hashable`, and `Equatable`.
///   The `Equatable` conformance is **synthesised** via [SE-0185](https://github.com/swiftlang/swift-evolution/blob/master/proposals/0185-synthesize-equatable-hashable.md):
///   two `.failed(_)` states compare equal if and only if their inner
///   ``TorError`` values compare structurally equal (not by
///   `localizedDescription` string).
/// - Important: Bootstrap progress is **not** part of this enum. A
///   `.running` state only guarantees that the embedded control socket
///   is reachable — Tor may still be at 30% bootstrap. Use
///   ``TorEvent/bootstrap(progress:tag:summary:)`` or
///   ``TorSession/waitUntilBootstrapped(timeout:)-(Duration)`` to wait for
///   100% bootstrap.
///
/// ## Topics
///
/// ### States
/// - ``idle``
/// - ``starting``
/// - ``running``
/// - ``stopping``
/// - ``stopped``
/// - ``failed(_:)``
///
/// ### Queries
/// - ``isOperational``
/// - ``description``
public enum TorState: Sendable, Hashable, CustomStringConvertible {
    /// Initial state — no `tor_run_main()` thread has been launched.
    ///
    /// Freshly-constructed ``TorClient`` instances are in this state until
    /// ``TorClient/start()`` is called. Observing `.idle` after a
    /// previous run means the session was never restarted; the previous
    /// terminal state would have been `.stopped` or `.failed(_)`.
    case idle

    /// Transient state between ``TorClient/start()`` invocation and the
    /// control socket becoming reachable.
    ///
    /// `tor_run_main()` has been posted to its dedicated background thread
    /// and is doing the synchronous startup work (option parsing, data
    /// directory bootstrap, control socket bind). Duration is typically
    /// sub-second on warm caches. Bootstrap progress is **not** yet being
    /// reported — those events begin arriving once `.running` is reached.
    case starting

    /// The embedded control socket is ready and `tor_run_main()` is
    /// executing.
    ///
    /// Reaching `.running` guarantees: ``TorClient/socksEndpoint`` is
    /// non-`nil`, ``TorClient/control()`` returns a usable client, and
    /// ``TorEvent/bootstrap(progress:tag:summary:)`` events are flowing on ``TorSession/events``.
    /// It does **not** guarantee 100% bootstrap — guard-negotiation and
    /// consensus download are still in flight. ``TorState/isOperational``
    /// returns `true` exactly for this case.
    case running

    /// Transient state between ``TorClient/stop()`` and Tor's exit.
    ///
    /// The `SIGNAL SHUTDOWN` control command (control-spec.txt §3.7) has
    /// been dispatched and swift-tor is waiting for `tor_run_main()` to
    /// return. Duration is governed by Tor's internal shutdown grace
    /// period (default 30 s, tunable via `ShutdownWaitLength`). Most
    /// operations called against ``TorClient`` during this window throw
    /// ``TorError/notStarted``.
    case stopping

    /// Terminal state after a clean shutdown — all resources released.
    ///
    /// The `tor_run_main()` thread has returned, the control socket is
    /// closed, and `configuration.dataDirectory` has been removed if
    /// `configuration.ownsDataDirectory` is `true`. ``TorClient/start()``
    /// may be called again; it will re-enter `.starting` with a fresh
    /// data directory.
    case stopped

    /// Terminal/transient error state carrying the causal ``TorError``.
    ///
    /// Observed when `tor_run_main()` returns a non-zero exit status, the
    /// start pipeline throws, or an internal assertion fires. The
    /// associated value surfaces the underlying cause: typically
    /// ``TorError/startFailed(_:)`` or ``TorError/ioError(_:)``.
    /// `.failed(_)` is **transient** — a subsequent ``TorClient/start()``
    /// transitions back to `.starting`; state is not sticky.
    case failed(TorError)

    /// Short, lowercase identifier for the current case.
    ///
    /// Intended for log lines and human-readable UI labels. The string
    /// returned is stable across releases and matches the case name; for
    /// `.failed(_)` it wraps the associated ``TorError``'s
    /// `CustomStringConvertible` form inside `"failed(…)"` to keep the
    /// causal information visible at a glance.
    ///
    /// - Returns: `"idle"`, `"starting"`, `"running"`, `"stopping"`,
    ///   `"stopped"`, or `"failed(<error>)"`.
    public var description: String {
        switch self {
        case .idle: "idle"
        case .starting: "starting"
        case .running: "running"
        case .stopping: "stopping"
        case .stopped: "stopped"
        case .failed(let error): "failed(\(error))"
        }
    }

    /// `true` iff this state is ``running`` — i.e., Tor is accepting
    /// control commands.
    ///
    /// Useful as a guard for methods that depend on the control socket
    /// being reachable. Does **not** imply bootstrap completion (see the
    /// type-level `Important` note). Callers that need "ready to carry
    /// user traffic" semantics should additionally observe
    /// ``TorEvent/bootstrap(progress:tag:summary:)`` for `progress == 100`.
    ///
    /// - Returns: `true` for `.running`, `false` for every other case.
    public var isOperational: Bool {
        if case .running = self { return true }
        return false
    }
}
