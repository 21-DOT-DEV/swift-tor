//
//  TorEvent.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Tor's five log-severity levels, surfaced as a typed, ordered enum.
///
/// Mirrors the severity keywords defined by control-spec.txt §4.1.10 and
/// Tor's `torrc` `Log` directive: `DEBUG` < `INFO` < `NOTICE` < `WARN` <
/// `ERR`. The raw values are the exact protocol strings, so callers can
/// round-trip a level through the control protocol without custom
/// encoding. `Comparable` is implemented by severity so that
/// `level >= .warn` is meaningful as a filter predicate.
///
/// - Note: Conformance is `Sendable` + `Hashable` + `Comparable` +
///   `CaseIterable`. Use `TorLogLevel.allCases` to render a dropdown or
///   drive a matrix test.
/// - Important: Tor emits a very high volume of `.debug` / `.info` events
///   during bootstrap. Filter at the subscription level (via
///   ``TorControlClient/subscribe(to:)``) rather than at the UI layer to
///   avoid pushing unnecessary data across the control socket.
///
/// ## Topics
///
/// ### Levels
/// - ``debug``
/// - ``info``
/// - ``notice``
/// - ``warn``
/// - ``err``
///
public enum TorLogLevel: String, Sendable, Hashable, Comparable, CaseIterable {
    /// High-volume developer diagnostics.
    ///
    /// Almost never wanted in production: Tor emits thousands of
    /// `DEBUG` lines per minute across normal operation. Enable only
    /// when reproducing a specific control-layer or circuit bug.
    case debug = "DEBUG"

    /// Routine operational information.
    ///
    /// Bootstrap phase transitions, guard selection, consensus
    /// download progress. Useful for observability dashboards but
    /// verbose enough that persistent disk logging is discouraged.
    case info = "INFO"

    /// Noteworthy but non-error events.
    ///
    /// Default log level for most Tor deployments: circuit closures,
    /// clock skew warnings, onion-service descriptor publication. A
    /// reasonable floor for end-user UI surfaces.
    case notice = "NOTICE"

    /// Recoverable problems and deprecation notices.
    ///
    /// Transient network failures, retryable directory fetch errors,
    /// and configuration warnings that Tor is working around. Worth
    /// surfacing to operators; not user-facing.
    case warn = "WARN"

    /// Fatal or near-fatal errors.
    ///
    /// Indicates Tor cannot continue a specific operation — e.g. a
    /// bound port cannot be allocated, crypto operations fail,
    /// descriptors are rejected. Frequently precedes
    /// ``TorState/failed(_:)``.
    case err = "ERR"

    /// Numeric severity used for `Comparable` ordering.
    private var severity: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .notice: return 2
        case .warn: return 3
        case .err: return 4
        }
    }

    /// Strict severity comparison: `.debug < .info < .notice < .warn < .err`.
    ///
    /// Enables predicates such as `level >= .warn` for log filtering
    /// and test assertions. Comparison is **not** lexicographic on the
    /// raw strings — `"DEBUG" < "ERR"` by ASCII but `.debug > .err` by
    /// severity; always use the typed enum for ordering semantics.
    ///
    /// - Parameters:
    ///   - lhs: Left operand.
    ///   - rhs: Right operand.
    /// - Returns: `true` if `lhs` has strictly lower severity than `rhs`.
    public static func < (lhs: TorLogLevel, rhs: TorLogLevel) -> Bool {
        lhs.severity < rhs.severity
    }
}

/// Lifecycle and protocol events surfaced by ``TorClient`` and
/// ``TorSession``.
///
/// `TorEvent` is the Swift-side projection of Tor's control-protocol
/// async events (control-spec.txt §4) plus swift-tor's own state
/// transitions. It flattens heterogeneous sources — bootstrap progress,
/// log messages, state changes, and circuit/stream status — into a
/// single `Sendable` enum so UI code can subscribe to one `AsyncStream`
/// and pattern-match once.
///
/// The enum does **not** cover every control-protocol event Tor can
/// emit; only the high-level events that map cleanly to end-user UX or
/// state machines are surfaced here. For the complete raw-event set,
/// subscribe via ``TorControlClient/subscribe(to:)`` and receive
/// ``TorControlEventMessage`` values directly.
///
/// - Note: Events are delivered in causal order per
///   ``TorSession/events``. A `.stateChanged(.running)` is never observed
///   before the `.stateChanged(.starting)` that preceded it.
/// - Important: The stream has no replay. Subscribers that start late
///   will miss earlier events — capture the initial state via
///   ``TorClient/state`` when opening the iterator.
///
/// ## Topics
///
/// ### Cases
/// - ``bootstrap(progress:tag:summary:)``
/// - ``log(level:message:)``
/// - ``stateChanged(_:)``
/// - ``circuit(id:status:)``
/// - ``stream(id:status:target:)``
public enum TorEvent: Sendable {
    /// Bootstrap progress update derived from Tor's
    /// `status/bootstrap-phase` GETINFO key.
    ///
    /// Emitted as Tor advances through guard selection, consensus
    /// download, and circuit build. `progress` is monotonic — callers
    /// can safely replace prior progress in a UI without reconciling
    /// ordering. Typical phases cited by `tag`: `starting`, `conn_dir`,
    /// `handshake_dir`, `onehop_create`, `loading_status`, `done`.
    ///
    /// - Parameters:
    ///   - progress: Percentage complete, 0–100 inclusive.
    ///   - tag: Machine-readable phase tag per control-spec.txt §4.1.11
    ///     (`BOOTSTRAP` event) suitable for state-machine key selection.
    ///   - summary: Human-readable phase description (localised by Tor).
    case bootstrap(progress: Int, tag: String, summary: String)

    /// A log line emitted by Tor at the specified severity.
    ///
    /// Corresponds to Tor's `DEBUG`/`INFO`/`NOTICE`/`WARN`/`ERR` async
    /// events (control-spec.txt §4.1.10). Subscription is controlled by
    /// ``TorControlClient/subscribe(to:)``; by default swift-tor
    /// subscribes only to `NOTICE` and higher unless otherwise requested.
    ///
    /// - Parameters:
    ///   - level: Severity of the log line.
    ///   - message: Tor-formatted message body. May include structured
    ///     `key=value` pairs that callers can parse ad hoc.
    case log(level: TorLogLevel, message: String)

    /// ``TorClient``'s ``TorState`` advanced to a new value.
    ///
    /// Driven by swift-tor internally — **not** by Tor's control
    /// protocol. The sequence respects the legal transition graph in
    /// ``TorState``; SwiftUI observers can drive their view model off
    /// this event alone without also reading ``TorClient/state``.
    ///
    /// - Parameter state: The new state after the transition.
    case stateChanged(TorState)

    /// A Tor circuit changed status (built, extended, closed, failed).
    ///
    /// Surfaces the `CIRC` async event from control-spec.txt §4.1.1.
    /// Fine-grained; subscribers interested only in reachability should
    /// prefer ``bootstrap(progress:tag:summary:)`` or
    /// ``stateChanged(_:)`` instead.
    ///
    /// - Parameters:
    ///   - id: Circuit identifier (positive integer, stringified).
    ///   - status: Lifecycle keyword per §4.1.1: `LAUNCHED`, `BUILT`,
    ///     `EXTENDED`, `FAILED`, `CLOSED`.
    case circuit(id: String, status: String)

    /// A Tor stream (connection) changed status.
    ///
    /// Surfaces the `STREAM` async event from control-spec.txt §4.1.2.
    /// Useful for surfacing which remote hosts user traffic is flowing
    /// to; pairs naturally with ``circuit(id:status:)`` when correlating
    /// streams to circuits.
    ///
    /// - Parameters:
    ///   - id: Stream identifier.
    ///   - status: Lifecycle keyword per §4.1.2: `NEW`, `NEWRESOLVE`,
    ///     `REMAP`, `SENTCONNECT`, `SENTRESOLVE`, `SUCCEEDED`, `FAILED`,
    ///     `CLOSED`, `DETACHED`.
    ///   - target: Target address (`host:port`) if Tor included it in
    ///     the event; `nil` for early-lifecycle events that have not yet
    ///     resolved a target.
    case stream(id: String, status: String, target: String?)
}

/// Raw-protocol subscription keywords accepted by `SETEVENTS`.
///
/// Each case maps 1:1 to a Tor control-protocol async event keyword
/// (control-spec.txt §4.1). Pass an array of these to
/// ``TorControlClient/subscribe(to:)`` to subscribe; Tor will then emit
/// `650` async replies carrying event payloads, which swift-tor decodes
/// into ``TorControlEventMessage`` values.
///
/// Unlike ``TorEvent`` — which is the curated, UI-friendly projection —
/// `TorControlEvent` is the full, untyped subscription vocabulary. Use it
/// when you need fine-grained or protocol-specific events that the
/// high-level stream does not surface.
///
/// - Note: Conformance is `Sendable` + `Hashable` + `CaseIterable`; the
///   raw value is the exact protocol keyword, so round-tripping through
///   the wire is lossless.
/// - Important: Subscribing to high-volume events (`DEBUG`, `INFO`, `BW`)
///   on a saturated link can back up Tor's control socket. Prefer
///   `NOTICE`+ and curate `BW` subscriptions to specific measurement
///   windows.
///
/// ## Topics
///
/// ### Status summaries
/// - ``statusClient``
/// - ``statusServer``
/// - ``statusGeneral``
///
/// ### Log severities
/// - ``debug``
/// - ``info``
/// - ``notice``
/// - ``warn``
/// - ``err``
///
/// ### Traffic & topology
/// - ``circuitStatus``
/// - ``streamStatus``
/// - ``bandwidthUsed``
/// - ``newDescriptor``
/// - ``addressMap``
public enum TorControlEvent: String, Sendable, Hashable, CaseIterable {
    /// `STATUS_CLIENT` — general client operation status.
    ///
    /// Per control-spec.txt §4.1.10. Emitted when Tor publishes client-
    /// side status summaries (e.g. bootstrap phase transitions, circuit
    /// establishment notifications, DNS timeout rates). Low-volume,
    /// high-signal — suitable for dashboards and automated health checks.
    case statusClient = "STATUS_CLIENT"

    /// `STATUS_SERVER` — relay-side operation status.
    ///
    /// Per control-spec.txt §4.1.10. Only meaningful when Tor is
    /// configured as a relay or bridge; embedded-client deployments of
    /// swift-tor will rarely receive these events. Covers reachability
    /// self-tests, DNS hijack warnings, and bandwidth self-measurement.
    case statusServer = "STATUS_SERVER"

    /// `STATUS_GENERAL` — global status affecting all Tor operation.
    ///
    /// Per control-spec.txt §4.1.10. Covers cross-cutting concerns:
    /// clock skew, consensus download failures, too-many-connections
    /// warnings, directory mirror unreachability. Subscribe when you
    /// need a single catch-all signal for "Tor is unhealthy".
    case statusGeneral = "STATUS_GENERAL"

    /// `NOTICE` — informational log lines at default verbosity.
    ///
    /// Per control-spec.txt §4.1.3. Equivalent to ``TorLogLevel/notice``
    /// but subscribed at the raw-protocol layer. Higher volume than
    /// `STATUS_*`; lower volume than `INFO`.
    case notice = "NOTICE"

    /// `WARN` — recoverable problem log lines.
    ///
    /// Per control-spec.txt §4.1.3. Equivalent to ``TorLogLevel/warn``
    /// but at the subscription layer. Typically subscribed by default —
    /// the cost is low and signal density is high.
    case warn = "WARN"

    /// `ERR` — fatal log lines.
    ///
    /// Per control-spec.txt §4.1.3. Equivalent to ``TorLogLevel/err``.
    /// Should always be subscribed: these events frequently precede a
    /// transition to ``TorState/failed(_:)``.
    case err = "ERR"

    /// `DEBUG` — developer-diagnostic log lines.
    ///
    /// Per control-spec.txt §4.1.3. Extremely high volume; subscribe
    /// only when reproducing a specific control-layer or circuit bug,
    /// and unsubscribe once the capture is complete.
    case debug = "DEBUG"

    /// `INFO` — routine operational log lines.
    ///
    /// Per control-spec.txt §4.1.3. High volume; useful for bootstrap
    /// and guard-selection diagnosis but not for steady-state
    /// observability.
    case info = "INFO"

    /// `CIRC` — per-circuit lifecycle events.
    ///
    /// Per control-spec.txt §4.1.1. Emitted at `LAUNCHED`, `BUILT`,
    /// `EXTENDED`, `FAILED`, and `CLOSED` transitions. Swift-tor
    /// surfaces the major transitions as ``TorEvent/circuit(id:status:)``.
    case circuitStatus = "CIRC"

    /// `STREAM` — per-stream lifecycle events.
    ///
    /// Per control-spec.txt §4.1.2. Tracks every TCP connection Tor
    /// carries, from `NEW` through `CLOSED`. Swift-tor surfaces the
    /// major transitions as ``TorEvent/stream(id:status:target:)``.
    case streamStatus = "STREAM"

    /// `BW` — per-second bandwidth usage totals.
    ///
    /// Per control-spec.txt §4.1.4. Emitted once per second as two
    /// bytes-read/bytes-written counters. Useful for dashboards; noisy
    /// for anything else.
    case bandwidthUsed = "BW"

    /// `NEWDESC` — new relay descriptors downloaded.
    ///
    /// Per control-spec.txt §4.1.6. Low-volume; emitted when the
    /// consensus is refreshed. Pair with ``addressMap`` when debugging
    /// relay-selection issues.
    case newDescriptor = "NEWDESC"

    /// `ADDRMAP` — address-mapping updates.
    ///
    /// Per control-spec.txt §4.1.7. Emitted when Tor adds, removes, or
    /// expires a DNS mapping (e.g. `MapAddress` torrc directives or
    /// `.exit` hostname resolutions). Useful for building visibility
    /// into what user traffic is routing where.
    case addressMap = "ADDRMAP"
}

/// A parsed 650-status async reply from the Tor control protocol.
///
/// `TorControlEventMessage` is the raw, typed representation of a single
/// `SETEVENTS` delivery. It carries the event kind, the verbatim payload
/// line Tor sent, and a lazily-parsed attribute dictionary for
/// `key=value` fields that appear in most events (circuit status,
/// bandwidth totals, etc.).
///
/// Most callers should subscribe to ``TorSession/events`` instead and
/// receive curated ``TorEvent`` values. Use `TorControlEventMessage`
/// when you need access to an event field that swift-tor has not yet
/// promoted into the high-level enum.
///
/// - Note: Conformance is `Sendable`; all three fields are value types
///   and safely cross concurrency domains.
/// - Important: `attributes` is **opportunistic** — the parser extracts
/// `key=value` and `key="quoted value"` pairs from `data` on a best-effort
/// basis per control-spec.txt §2.3. Events whose payload is not a
/// `key=value` list will have an empty dictionary and full content in
/// `data`.
///
/// ## Topics
///
/// ### Creating
/// - ``init(event:data:attributes:)``
///
/// ### Inspection
/// - ``event``
/// - ``data``
/// - ``attributes``
public struct TorControlEventMessage: Sendable {
    /// The protocol-level event kind carried by this message.
    ///
    /// Determined by the first token on the `650`-status line, looked up
    /// against ``TorControlEvent`` raw values. Pattern-match on this
    /// field to dispatch per-event handlers.
    public let event: TorControlEvent

    /// Tor's verbatim payload line after the event keyword.
    ///
    /// Everything following the keyword on the wire, with the trailing
    /// CRLF stripped. For multi-line events (`650+`), contains the
    /// joined body. Fall back to this field when ``attributes`` does not
    /// surface the information you need.
    public let data: String

    /// Opportunistically-parsed `key=value` attribute dictionary.
    ///
    /// Populated by ``ControlProtocolParser`` for events whose payload is
    /// a flat `key=value key2="quoted value"` sequence per
    /// control-spec.txt §2.3. Empty for events with purely positional
    /// payloads (`BW <read> <written>`, `CIRC <id> <status>`); treat
    /// ``data`` as authoritative in those cases.
    public let attributes: [String: String]

    /// Memberwise initialiser — usually called by the control-protocol
    /// parser, not end-user code.
    ///
    /// Construct a `TorControlEventMessage` directly when simulating
    /// events in tests or when deserialising from a persisted log.
    ///
    /// - Parameters:
    ///   - event: The protocol event kind.
    ///   - data: The raw payload line (without the leading keyword).
    ///   - attributes: Optional pre-parsed `key=value` attributes; pass
    ///     an empty dictionary (the default) if the payload is not a
    ///     flat attribute list.
    public init(event: TorControlEvent, data: String, attributes: [String: String] = [:]) {
        self.event = event
        self.data = data
        self.attributes = attributes
    }
}
