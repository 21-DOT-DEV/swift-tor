//
//  TorError.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Canonical error surface for every swift-tor failure mode.
///
/// `TorError` consolidates every expected failure across the embedded
/// Tor process lifecycle, the control protocol, onion-service management,
/// and low-level I/O into a single `Sendable`/`Hashable` enum — callers
/// can `switch` exhaustively in one place instead of catching heterogeneous
/// `Error` conformers from `Foundation`, `POSIX`, and the control layer.
/// Associated-value payloads are `String` (or a `(code: Int, message: String)`
/// tuple) so the concrete details of each failure are carried through
/// without requiring downstream code to know the underlying machinery.
///
/// Cases are grouped by concern: **Lifecycle** covers
/// ``alreadyStarted``, ``notStarted``, and ``startFailed(_:)``;
/// **Control protocol** covers ``controlUnavailable``,
/// ``controlAuthFailed(_:)``, and ``controlProtocolError(code:message:)``;
/// **Onion service** covers ``invalidServiceID(_:)`` and
/// ``serviceAlreadyExists(_:)``; and **General** covers
/// ``timeout``, ``invalidResponse(_:)``, ``ioError(_:)``, and
/// ``resourceExhausted(_:)``.
///
/// - Note: Conformance is `Error` + `Sendable` + `Hashable` +
///   `CustomStringConvertible`. `Hashable` is synthesised via
///   [SE-0185](https://github.com/swiftlang/swift-evolution/blob/master/proposals/0185-synthesize-equatable-hashable.md)
///   across structural payloads, so two errors are equal iff both their
///   cases and their associated strings/codes match verbatim.
/// - Important: `TorError` does **not** yet conform to `LocalizedError`.
///   Apple UI code that expects `error.localizedDescription` will fall
///   back to the case name, not the human-readable ``description``. Bridge
///   explicitly via `"\(error)"` when rendering for users.
///
/// ## Topics
///
/// ### Lifecycle
/// - ``alreadyStarted``
/// - ``notStarted``
/// - ``startFailed(_:)``
///
/// ### Control protocol
/// - ``controlUnavailable``
/// - ``controlAuthFailed(_:)``
/// - ``controlProtocolError(code:message:)``
///
/// ### Onion services
/// - ``invalidServiceID(_:)``
/// - ``serviceAlreadyExists(_:)``
///
/// ### General
/// - ``timeout``
/// - ``invalidResponse(_:)``
/// - ``ioError(_:)``
/// - ``resourceExhausted(_:)``
///
/// ### Rendering
/// - ``description``
public enum TorError: Error, Sendable, Hashable, CustomStringConvertible {
    // MARK: - Lifecycle Errors

    /// ``TorClient/start()`` was called on a session already in
    /// `.starting` or `.running`.
    ///
    /// Raised defensively — double-starting is almost always a caller bug
    /// (e.g. retry logic that forgot to check ``TorState``). Recover by
    /// awaiting the existing session or calling ``TorClient/stop()`` first.
    case alreadyStarted

    /// An operation requiring a running Tor instance was invoked against
    /// an idle/stopped/failed session.
    ///
    /// Typical sources: ``TorClient/waitUntilBootstrapped(timeout:)``,
    /// ``TorClient/control()``, ``TorClient/makeURLSession(ephemeral:)``
    /// on Apple platforms. Fix by calling ``TorClient/start()`` first.
    case notStarted

    /// Tor's `tor_run_main()` returned non-zero during start or the
    /// start pipeline threw before the control socket became reachable.
    ///
    /// The payload carries Tor's own diagnostic text (e.g. port collision,
    /// missing data-directory permissions, malformed torrc). Not retryable
    /// without a config change. Surfaces as ``TorState/failed(_:)``.
    case startFailed(String)

    // MARK: - Control Errors

    /// ``TorClient/control()`` was called but no control client is bound.
    ///
    /// Raised when ``TorClient`` is idle or stopped, or when the embedded
    /// control socket failed to authenticate during start. Distinct from
    /// ``notStarted``: the session may be running but control-less if
    /// `tor_main_configuration_setup_control_socket()` failed.
    case controlUnavailable

    /// A `AUTHENTICATE` command was rejected by Tor (reply code 515).
    ///
    /// Causes: wrong cookie file, invalid `HashedControlPassword`, or the
    /// null-auth fallback attempted while `AUTHENTICATE_COOKIE_REQUIRED`
    /// is enabled. See control-spec.txt §3.5. The payload carries Tor's
    /// response text. Not retryable without credential change.
    case controlAuthFailed(String)

    /// Tor returned a non-success reply to a control command.
    ///
    /// The `code` is the three-digit numeric reply code per
    /// control-spec.txt §2.3 ([Replies](https://spec.torproject.org/control-spec/replies.html)):
    /// 250/251 = success (never raised here), 510 = unrecognized command,
    /// 512 = syntax error in argument, 513 = unrecognized argument, 514 =
    /// auth required, 515 = bad auth, 550 = unspecified Tor error,
    /// 552 = unrecognized entity, 553 = invalid config value,
    /// 554 = invalid descriptor, 555 = unmanaged entity, 650 = async event
    /// (also not raised here; flows to ``TorEvent`` instead).
    /// `message` carries Tor's free-form diagnostic text.
    case controlProtocolError(code: Int, message: String)

    // MARK: - Onion Service Errors

    /// The supplied `.onion` service ID failed validation.
    ///
    /// Raised by ``TorControlClient/delOnion(_:)-(String)`` when the ID
    /// does not look like a valid v3 address. Payload carries the offending
    /// input verbatim for debugging. Per rend-spec-v3 §6, a valid v3 ID
    /// is a 56-character base32-encoded string (exclusive of `.onion`).
    case invalidServiceID(String)

    /// `ADD_ONION` against a pre-existing service ID (Tor reply 550 or 554).
    ///
    /// Happens when a caller re-imports a private key for a service that
    /// is already active on this control connection. Either adopt the
    /// existing service via ``TorControlClient/getInfo(_:)-(String)`` or
    /// call ``TorControlClient/delOnion(_:)-(String)`` first.
    case serviceAlreadyExists(String)

    // MARK: - General Errors

    /// A bounded wait elapsed without the awaited condition being met.
    ///
    /// Most commonly raised by
    /// ``TorClient/waitUntilBootstrapped(timeout:)`` when Tor does not
    /// reach 100% bootstrap inside the supplied `Duration`. Control-socket
    /// `readLine()` also raises this when `setSocketTimeout` is active.
    /// Retryable in principle, but long timeouts usually indicate a
    /// networking or consensus-download problem.
    case timeout

    /// A control-protocol reply or async event could not be parsed.
    ///
    /// Raised by ``ControlProtocolParser`` when a reply line violates
    /// control-spec.txt §2.3 (short line, missing status prefix, unclosed
    /// multi-line). The payload carries the offending line (or a summary)
    /// for debugging. Should be treated as a bug in swift-tor or a Tor
    /// version mismatch — not a user-recoverable error.
    case invalidResponse(String)

    /// A POSIX I/O operation against the control socket or data directory
    /// failed.
    ///
    /// Payload carries a combined description of the syscall + `errno`
    /// string (e.g. `"read: Connection reset by peer"`). Most commonly
    /// seen when Tor exits during an active control command or the data
    /// directory becomes unwritable. Not generally retryable; inspect the
    /// payload for classification.
    case ioError(String)

    /// Tor reported resource exhaustion (Tor reply 451) — out of file
    /// descriptors, memory, or entry guards.
    ///
    /// Rarely raised in practice. Payload is Tor's diagnostic string.
    /// Callers may choose to back off and retry, but the underlying
    /// resource pressure is usually system-wide and requires operator
    /// intervention.
    case resourceExhausted(String)

    /// Human-readable, stable string representation of this error.
    ///
    /// Each case renders to a concise English sentence suitable for log
    /// lines, CLI diagnostics, and fallback UI labels. Strings are
    /// deliberately **stable across minor releases** — do not pattern-match
    /// against them; pattern-match against the enum case instead.
    ///
    /// - Returns: A short sentence describing the error. Associated-value
    ///   cases include their payload in a sensible template
    ///   (e.g. `"Tor failed to start: <reason>"`).
    ///
    /// - Important: This is **not** a `LocalizedError.errorDescription`;
    ///   Apple UI surfaces that call `error.localizedDescription` will
    ///   fall back to the opaque case name. Render via `"\(error)"` or
    ///   `error.description` when user-facing copy is needed.
    public var description: String {
        switch self {
        case .alreadyStarted:
            return "Tor is already started"
        case .notStarted:
            return "Tor has not been started"
        case .startFailed(let reason):
            return "Tor failed to start: \(reason)"
        case .controlUnavailable:
            return "Control connection is not available"
        case .controlAuthFailed(let reason):
            return "Control authentication failed: \(reason)"
        case .controlProtocolError(let code, let message):
            return "Control protocol error \(code): \(message)"
        case .invalidServiceID(let id):
            return "Invalid service ID: \(id)"
        case .serviceAlreadyExists(let id):
            return "Service already exists: \(id)"
        case .timeout:
            return "Operation timed out"
        case .invalidResponse(let detail):
            return "Invalid response: \(detail)"
        case .ioError(let detail):
            return "I/O error: \(detail)"
        case .resourceExhausted(let detail):
            return "Resource exhausted: \(detail)"
        }
    }
}
