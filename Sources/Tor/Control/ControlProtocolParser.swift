//
//  ControlProtocolParser.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// A fully-parsed Tor control-protocol reply, ready for business logic.
///
/// Represents the result of parsing one or more raw lines from
/// ``ControlSocket/readReply()`` into a single semantic unit per
/// control-spec.txt §2.3: a numeric status code, the content lines
/// (stripped of the `NNN<sep>` prefix), and an optional verbatim data
/// block (for `NNN+` replies terminated by a sole `.`).
///
/// - Note: Conformance is `Sendable` + `Equatable`; synthesised
///   equality compares `statusCode`, `lines` (element-wise), and `data`
///   verbatim.
/// - Important: `ControlReply` makes no claim about whether a reply
///   is semantically valid for the command that elicited it — only
///   that the wire format parsed. Per-command parsers
///   (``ControlProtocolParser/parseAddOnionResponse(_:)-(ControlReply)``
///   et al.) validate payload shape on top.
///
/// ## Topics
///
/// ### Core fields
/// - ``statusCode``
/// - ``lines``
/// - ``data``
///
/// ### Classification
/// - ``isSuccess``
/// - ``isError``
/// - ``message``
///
/// ### Structured access
/// - ``keyValuePairs``
///
/// ### Creating
/// - ``init(statusCode:lines:data:)``
public struct ControlReply: Sendable, Equatable {
    /// The numeric status code of the reply (control-spec.txt §2.3).
    ///
    /// Typical values: `250`/`251` for success, `5xx` for command-level
    /// errors, `650` for async events. See ``TorError/controlProtocolError(code:message:)``
    /// for the full enumeration of error codes swift-tor surfaces.
    ///
    /// - Stability: immutable.
    public let statusCode: Int

    /// The reply content lines, with the status-code prefix stripped.
    ///
    /// For multi-line replies, the array contains one element per
    /// content line in receive order. For single-line replies the
    /// array has exactly one element. The status-code prefix
    /// (`"250-"`, `"250 "`, `"250+"`) is **not** preserved — consumers
    /// that need it should inspect ``statusCode`` directly.
    ///
    /// - Stability: immutable.
    public let lines: [String]

    /// Verbatim data-block contents from a `NNN+` reply, if any.
    ///
    /// Populated only when the reply used the data-block form
    /// (`250+data=...`). Inner lines are joined with `\n`, with
    /// leading `.` dot-stuffing undone per control-spec.txt §2.3. `nil`
    /// for ordinary single-line / continuation replies.
    ///
    /// - Stability: immutable.
    public let data: String?

    /// `true` when the status code is in the 2xx range.
    ///
    /// Classifies `statusCode` against the HTTP-like convention used
    /// by Tor's control protocol: 2xx = success, 4xx/5xx = error,
    /// 6xx = asynchronous event. Prefer this over direct
    /// `statusCode == 250` comparisons so `251` replies ("command
    /// accepted but operation unnecessary") aren't treated as errors.
    public var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }

    /// `true` when the status code is 4xx or 5xx.
    ///
    /// Deliberately excludes 6xx async events — those are not
    /// replies to commands and should be routed through
    /// ``ControlProtocolParser/parseAsyncEvent(_:)`` instead.
    public var isError: Bool {
        statusCode >= 400
    }

    /// The first content line, or an empty string for empty replies.
    ///
    /// Convenience accessor for single-line replies where
    /// `lines[0]` is the only meaningful payload. For multi-line
    /// replies, prefer iterating over ``lines`` directly.
    ///
    /// - Returns: `lines.first ?? ""`.
    public var message: String {
        lines.first ?? ""
    }

    /// Extract `KEY=VALUE` pairs from ``lines`` into a dictionary.
    ///
    /// Splits each line on the **first** `=` character; keys and
    /// values are unquoted. For values with internal `=` characters
    /// (e.g. base64-padded keys) the full tail including additional
    /// `=` is preserved verbatim. Lines without an `=` are skipped
    /// silently — use ``lines`` directly when positional parsing is
    /// required.
    ///
    /// - Returns: A dictionary mapping each `KEY` to its `VALUE`.
    ///
    /// - Note: Unlike
    ///   ``ControlProtocolParser/parseAttributes(_:)``, this accessor
    ///   does **not** handle quoted values — it's intended for the
    ///   simple `KEY=VALUE` shape used by `GETINFO` replies, not for
    ///   async-event attribute parsing.
    public var keyValuePairs: [String: String] {
        var result: [String: String] = [:]
        for line in lines {
            if let equalIndex = line.firstIndex(of: "=") {
                let key = String(line[..<equalIndex])
                let value = String(line[line.index(after: equalIndex)...])
                result[key] = value
            }
        }
        return result
    }

    /// Memberwise initialiser — usually invoked by parsers, not by
    /// application code.
    ///
    /// Construct a `ControlReply` directly when replaying a persisted
    /// transcript in tests or when driving a mock control client.
    ///
    /// - Parameters:
    ///   - statusCode: The numeric status code.
    ///   - lines: The content lines (without status-code prefix).
    ///   - data: Optional data-block payload. Defaults to `nil`.
    public init(statusCode: Int, lines: [String], data: String? = nil) {
        self.statusCode = statusCode
        self.lines = lines
        self.data = data
    }
}

/// Namespace enum holding all stateless control-protocol parsing routines.
///
/// Every method is `static` — the enum exists only as a namespace, never
/// instantiated. Callers invoke
/// ``ControlProtocolParser/parseReply(_:)`` to turn the raw lines from
/// ``ControlSocket/readReply()`` into a ``ControlReply``, then route
/// through type-specific helpers like
/// ``ControlProtocolParser/parseAddOnionResponse(_:)-(ControlReply)``
/// or ``ControlProtocolParser/parseGetInfoResponse(_:)`` for semantic
/// decoding.
///
/// The reply formats swift-tor decodes follow control-spec.txt §2.3:
/// **single-line** (`250 OK\r\n`), **multi-line continuation**
/// (`250-line1\r\n250-line2\r\n250 OK\r\n`), **data block**
/// (`250+key=\r\nbody-line-1\r\n.\r\n250 OK\r\n`), and **async event**
/// (`650 EVENT_TYPE payload\r\n`).
///
/// - Note: The parser is allocation-light but not zero-allocation — it
///   slices `String` views of the input lines. For tight loops over
///   thousands of events per second, prefer direct attribute access on
///   the raw lines.
/// - Important: All `parse*` methods are safe to call concurrently and
///   deterministic: same input, same output.
///
/// ## Topics
///
/// ### Replies
/// - ``parseReply(_:)``
/// - ``parseSingleLine(_:)``
///
/// ### Structured decoders
/// - ``parseBootstrapStatus(_:)``
/// - ``parseAddOnionResponse(_:)-(ControlReply)``
/// - ``parseAddOnionResponse(_:)-([String])``
/// - ``parseGetInfoResponse(_:)``
///
/// ### Async events
/// - ``parseAsyncEvent(_:)``
///
/// ### Primitives
/// - ``parseAttributes(_:)``
public enum ControlProtocolParser {
    
    /// Parse an array of raw reply lines into a ``ControlReply``.
    ///
    /// Iterates once over `rawLines`, classifying each by its fourth
    /// byte (`' '`, `-`, or `+`) per control-spec.txt §2.3:
    /// - `' '` closes the reply and all preceding lines are accumulated
    /// - `-` continues the reply for another line
    /// - `+` opens a data block terminated by a sole `.` line;
    ///   dot-stuffed lines have the leading `.` removed
    ///
    /// The first three bytes must parse as a decimal status code; the
    /// first observed code becomes ``ControlReply/statusCode``.
    ///
    /// - Parameter rawLines: Lines emitted by
    ///   ``ControlSocket/readReply()`` in order.
    /// - Returns: A fully-populated ``ControlReply``.
    /// - Throws: ``TorError/invalidResponse(_:)`` if the lines are
    ///   empty, malformed, missing a status code, or use an unknown
    ///   separator byte.
    public static func parseReply(_ rawLines: [String]) throws -> ControlReply {
        guard !rawLines.isEmpty else {
            throw TorError.invalidResponse("Empty reply")
        }
        
        var lines: [String] = []
        var data: String? = nil
        var statusCode: Int? = nil
        var inDataBlock = false
        var dataLines: [String] = []
        
        for rawLine in rawLines {
            if inDataBlock {
                if rawLine == "." {
                    inDataBlock = false
                    data = dataLines.joined(separator: "\n")
                } else {
                    // Handle dot-stuffing: lines starting with "." have it removed
                    let line = rawLine.hasPrefix(".") ? String(rawLine.dropFirst()) : rawLine
                    dataLines.append(line)
                }
                continue
            }
            
            guard rawLine.count >= 3 else {
                throw TorError.invalidResponse("Line too short: \(rawLine)")
            }
            
            let codeStr = String(rawLine.prefix(3))
            guard let code = Int(codeStr) else {
                throw TorError.invalidResponse("Invalid status code: \(codeStr)")
            }
            
            if statusCode == nil {
                statusCode = code
            }
            
            let separatorIndex = rawLine.index(rawLine.startIndex, offsetBy: 3)
            let separator = rawLine.count > 3 ? rawLine[separatorIndex] : " "
            let content = rawLine.count > 4 ? String(rawLine[rawLine.index(after: separatorIndex)...]) : ""
            
            switch separator {
            case "-":
                // Continuation line
                lines.append(content)
            case "+":
                // Data block follows
                lines.append(content)
                inDataBlock = true
                dataLines = []
            case " ":
                // Final line
                lines.append(content)
            default:
                throw TorError.invalidResponse("Invalid separator: \(separator)")
            }
        }
        
        guard let finalCode = statusCode else {
            throw TorError.invalidResponse("No status code found")
        }
        
        return ControlReply(statusCode: finalCode, lines: lines, data: data)
    }
    
    /// Convenience: parse exactly one reply line.
    ///
    /// Wraps ``parseReply(_:)`` for the common case of a single-line
    /// reply (`"250 OK"`, `"515 Authentication failed"`). Avoids the
    /// array boilerplate at call sites.
    ///
    /// - Parameter line: A single reply line as returned by
    ///   ``ControlSocket/readLine()``.
    /// - Returns: A ``ControlReply`` with a single entry in
    ///   ``ControlReply/lines``.
    /// - Throws: ``TorError/invalidResponse(_:)`` if the line does
    ///   not parse.
    public static func parseSingleLine(_ line: String) throws -> ControlReply {
        try parseReply([line])
    }
}

// MARK: - Bootstrap Parsing

/// Parsed `BOOTSTRAP` status line per control-spec.txt §4.1.11.
///
/// Tor emits bootstrap progress both as responses to
/// `GETINFO status/bootstrap-phase` and as async `STATUS_CLIENT` events
/// carrying a `BOOTSTRAP` payload. Both shapes share the same attribute
/// vocabulary: `PROGRESS`, `TAG`, `SUMMARY`, and optional `WARNING` /
/// `REASON` fields for degraded progress. `BootstrapStatus` is the
/// typed projection callers actually consume — see
/// ``TorClient/waitUntilBootstrapped(timeout:)`` and
/// ``TorEvent/bootstrap(progress:tag:summary:)``.
///
/// - Note: Conformance is `Sendable` + `Equatable`.
/// - Important: `progress` is monotonic within a single session — Tor
///   never retreats to a lower percentage. Subscribers may safely
///   replace prior UI without reordering.
///
/// ## Topics
///
/// ### Progress
/// - ``progress``
/// - ``isComplete``
///
/// ### Classification
/// - ``tag``
/// - ``summary``
///
/// ### Degraded progress
/// - ``warning``
/// - ``reason``
///
/// ### Creating
/// - ``init(progress:tag:summary:warning:reason:)``
public struct BootstrapStatus: Sendable, Equatable {
    /// Bootstrap percentage, `0–100` inclusive.
    ///
    /// Monotonically non-decreasing over a single bootstrap run.
    /// `100` indicates Tor is fully reachable for user traffic; lower
    /// values indicate in-flight progress.
    ///
    /// - Stability: immutable.
    public let progress: Int

    /// Machine-readable phase tag per control-spec.txt §4.1.11.
    ///
    /// Stable across Tor versions and suitable for switching in
    /// state-machine code. Examples: `"starting"`, `"conn_dir"`,
    /// `"handshake_dir"`, `"loading_status"`, `"done"`.
    ///
    /// - Stability: immutable.
    public let tag: String

    /// Human-readable, Tor-localised phase summary.
    ///
    /// Free-form English sentence suitable for progress UI. Not
    /// stable across Tor versions — do not pattern-match against
    /// this string; use ``tag`` for stable phase detection.
    ///
    /// - Stability: immutable.
    public let summary: String

    /// Optional warning keyword for a stalled bootstrap.
    ///
    /// Populated when Tor reports degraded progress (e.g.
    /// `"IDENTITY_MISMATCH"`, `"CONNECTION_FAILED"`). `nil` on
    /// healthy progress events. Pair with ``reason`` for the
    /// human-readable explanation.
    ///
    /// - Stability: immutable.
    public let warning: String?

    /// Optional free-form explanation accompanying ``warning``.
    ///
    /// Rendered by Tor in English and intended for logs / dashboards,
    /// not for programmatic dispatch.
    ///
    /// - Stability: immutable.
    public let reason: String?

    /// `true` if ``progress`` has reached 100%.
    ///
    /// Convenience used by
    /// ``TorClient/waitUntilBootstrapped(timeout:)`` to know when to
    /// resolve. Defined as `progress >= 100` to tolerate Tor
    /// reporting `100` exactly or a slightly-over reading from a
    /// buggy build.
    public var isComplete: Bool {
        progress >= 100
    }

    /// Memberwise initialiser — typically invoked by
    /// ``ControlProtocolParser/parseBootstrapStatus(_:)``.
    ///
    /// Construct directly when driving a mock control client or
    /// replaying persisted transcripts in tests.
    ///
    /// - Parameters:
    ///   - progress: 0–100 percentage.
    ///   - tag: Machine-readable phase tag.
    ///   - summary: Human-readable summary.
    ///   - warning: Optional warning keyword.
    ///   - reason: Optional warning explanation.
    public init(progress: Int, tag: String, summary: String, warning: String? = nil, reason: String? = nil) {
        self.progress = progress
        self.tag = tag
        self.summary = summary
        self.warning = warning
        self.reason = reason
    }
}

extension ControlProtocolParser {
    
    /// Parse a `BOOTSTRAP` status line into a ``BootstrapStatus``.
    ///
    /// Handles both forms that carry bootstrap progress:
    ///
    /// - A `GETINFO status/bootstrap-phase` response body such as
    ///   `NOTICE BOOTSTRAP PROGRESS=75 TAG=loading_descriptors SUMMARY="Loading relay descriptors"`.
    /// - A `STATUS_CLIENT` async event payload starting with
    ///   `BOOTSTRAP`.
    ///
    /// Uses ``parseAttributes(_:)`` internally to lift the `KEY=VALUE`
    /// and `KEY="quoted value"` fields from the line.
    ///
    /// - Parameter line: A line expected to contain a `BOOTSTRAP`
    ///   keyword plus attribute fields.
    /// - Returns: A populated ``BootstrapStatus``, or `nil` when the
    ///   line does not contain `BOOTSTRAP` or is missing required
    ///   attributes (`PROGRESS`, `TAG`).
    ///
    /// - Note: Returns `nil` rather than throwing so callers can
    ///   cheaply filter a stream of status lines and keep only the
    ///   bootstrap-shaped ones.
    public static func parseBootstrapStatus(_ line: String) -> BootstrapStatus? {
        guard line.contains("BOOTSTRAP") else {
            return nil
        }
        
        let attributes = parseAttributes(line)
        
        guard let progressStr = attributes["PROGRESS"],
              let progress = Int(progressStr),
              let tag = attributes["TAG"] else {
            return nil
        }
        
        let summary = attributes["SUMMARY"] ?? ""
        let warning = attributes["WARNING"]
        let reason = attributes["REASON"]
        
        return BootstrapStatus(
            progress: progress,
            tag: tag,
            summary: summary,
            warning: warning,
            reason: reason
        )
    }
    
    /// Lift `KEY=VALUE` and `KEY="quoted value"` attributes into a
    /// dictionary.
    ///
    /// Walks the input left-to-right, skipping whitespace, finding each
    /// `=` that separates a key from a value, and handling quoted
    /// values with backslash-escape expansion (`\"` → `"`, `\\` → `\`).
    /// Keys are the literal characters up to the `=` sign; keys that
    /// contain unescaped whitespace are silently dropped.
    ///
    /// This is the primary building block for async-event payload
    /// parsing (`BOOTSTRAP`, `CIRC`, `STREAM`), matching
    /// control-spec.txt §2.3's attribute-value syntax.
    ///
    /// - Parameter line: The line to parse. Any prefix up to the
    ///   first `KEY=` is ignored; extra tokens are skipped.
    /// - Returns: Dictionary mapping each key to its decoded value.
    ///
    /// - Important: The parser is deliberately lenient — malformed
    ///   entries are dropped, not thrown. Callers that need strict
    ///   validation must verify the returned keys explicitly.
    public static func parseAttributes(_ line: String) -> [String: String] {
        var result: [String: String] = [:]
        
        // Use a regex-like approach: find all KEY=VALUE or KEY="VALUE" patterns
        var index = line.startIndex
        
        while index < line.endIndex {
            // Skip whitespace
            while index < line.endIndex && line[index].isWhitespace {
                index = line.index(after: index)
            }
            
            guard index < line.endIndex else { break }
            
            // Find the next '=' to locate a key
            var keyEnd = index
            while keyEnd < line.endIndex && line[keyEnd] != "=" && line[keyEnd] != " " {
                keyEnd = line.index(after: keyEnd)
            }
            
            // If we hit a space before '=', this is a plain word - skip it
            if keyEnd >= line.endIndex || line[keyEnd] == " " {
                index = keyEnd
                continue
            }
            
            // We found '=', extract the key
            let key = String(line[index..<keyEnd])
            index = line.index(after: keyEnd) // Move past '='
            
            guard index < line.endIndex else { break }
            
            // Parse value (quoted or unquoted)
            let value: String
            if line[index] == "\"" {
                // Quoted value
                index = line.index(after: index) // Move past opening quote
                var valueEnd = index
                var escaped = false
                
                while valueEnd < line.endIndex {
                    let char = line[valueEnd]
                    if escaped {
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == "\"" {
                        break
                    }
                    valueEnd = line.index(after: valueEnd)
                }
                
                value = String(line[index..<valueEnd])
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
                
                // Move past closing quote
                if valueEnd < line.endIndex {
                    index = line.index(after: valueEnd)
                } else {
                    index = valueEnd
                }
            } else {
                // Unquoted value (ends at space or end of string)
                var valueEnd = index
                while valueEnd < line.endIndex && !line[valueEnd].isWhitespace {
                    valueEnd = line.index(after: valueEnd)
                }
                value = String(line[index..<valueEnd])
                index = valueEnd
            }
            
            result[key] = value
        }
        
        return result
    }
}

// MARK: - ADD_ONION Response Parsing

/// Decoded fields of an `ADD_ONION` success reply
/// (control-spec.txt §3.27).
///
/// Tor emits `ServiceID=<id>` on success, optionally followed by a
/// `PrivateKey=<type>:<blob>` line when the command was issued
/// **without** the `DiscardPK` flag. This struct carries just those
/// two fields; higher-level code wraps them into an ``OnionService``
/// value along with a creation timestamp.
///
/// - Note: Conformance is `Sendable` + `Equatable`.
/// - Important: ``privateKey`` is secret material. Never log or
///   serialise it unprotected — see ``OnionService/privateKey`` for
///   storage guidance.
///
/// ## Topics
///
/// ### Fields
/// - ``serviceID``
/// - ``privateKey``
///
/// ### Creating
/// - ``init(serviceID:privateKey:)``
public struct AddOnionResponse: Sendable, Equatable {
    /// The v3 service ID (56-char base32, no `.onion` suffix).
    ///
    /// Extracted from the `ServiceID=` line of the reply.
    /// Equivalent to ``OnionService/serviceID``.
    ///
    /// - Stability: immutable.
    public let serviceID: String

    /// The private key blob, or `nil` when `DiscardPK` was set.
    ///
    /// Extracted from the `PrivateKey=` line when present (never
    /// returned by Tor when `DiscardPK` was included in the
    /// request). Format is `<KeyType>:<KeyBlob>` verbatim — round-
    /// tripping through ``OnionKeySpec/providedV3(_:)`` requires
    /// passing only the `<KeyBlob>` suffix.
    ///
    /// - Stability: immutable.
    /// - Important: Secret material. Treat as a credential.
    public let privateKey: String?

    /// Memberwise initialiser. Typically invoked by
    /// ``ControlProtocolParser/parseAddOnionResponse(_:)-(ControlReply)``.
    ///
    /// - Parameters:
    ///   - serviceID: The v3 service identifier.
    ///   - privateKey: Optional private-key blob; defaults to `nil`.
    public init(serviceID: String, privateKey: String? = nil) {
        self.serviceID = serviceID
        self.privateKey = privateKey
    }
}

extension ControlProtocolParser {
    
    /// Decode an already-parsed ``ControlReply`` into an
    /// ``AddOnionResponse``.
    ///
    /// Expects the success-shape reply documented in
    /// control-spec.txt §3.27:
    ///
    /// ```
    /// 250-ServiceID=<onion_address_without_.onion>
    /// 250-PrivateKey=<key_type>:<key_blob>   (optional, when !DiscardPK)
    /// 250 OK
    /// ```
    ///
    /// Lifts `ServiceID` and optional `PrivateKey` off
    /// ``ControlReply/keyValuePairs``. Failure replies surface as
    /// ``TorError/controlProtocolError(code:message:)`` so callers
    /// can branch on the underlying Tor error code (550 / 554 /
    /// etc.).
    ///
    /// - Parameter reply: The parsed reply from an `ADD_ONION`
    ///   command.
    /// - Returns: A decoded ``AddOnionResponse``.
    /// - Throws: ``TorError/controlProtocolError(code:message:)`` on
    ///   non-success replies; ``TorError/invalidResponse(_:)`` if a
    ///   success reply is missing the required `ServiceID`.
    public static func parseAddOnionResponse(_ reply: ControlReply) throws -> AddOnionResponse {
        guard reply.isSuccess else {
            throw TorError.controlProtocolError(
                code: reply.statusCode,
                message: reply.message
            )
        }
        
        let kv = reply.keyValuePairs
        
        guard let serviceID = kv["ServiceID"] else {
            throw TorError.invalidResponse("ADD_ONION response missing ServiceID")
        }
        
        let privateKey = kv["PrivateKey"]
        
        return AddOnionResponse(serviceID: serviceID, privateKey: privateKey)
    }
    
    /// Decode an `ADD_ONION` response directly from raw reply lines.
    ///
    /// Composes ``parseReply(_:)`` and
    /// ``parseAddOnionResponse(_:)-(ControlReply)``. Useful when a
    /// caller holds the raw lines (from a persisted transcript or a
    /// mock socket) and doesn't want to parse in two steps.
    ///
    /// - Parameter rawLines: Raw reply lines produced by
    ///   ``ControlSocket/readReply()``.
    /// - Returns: A decoded ``AddOnionResponse``.
    /// - Throws: Errors from both underlying parsers.
    public static func parseAddOnionResponse(_ rawLines: [String]) throws -> AddOnionResponse {
        let reply = try parseReply(rawLines)
        return try parseAddOnionResponse(reply)
    }
}

// MARK: - GETINFO Response Parsing

extension ControlProtocolParser {
    
    /// Decode a `GETINFO` reply into a `[key: value]` dictionary.
    ///
    /// `GETINFO` replies share a common wire shape
    /// (control-spec.txt §3.9):
    ///
    /// ```
    /// 250-key1=value1
    /// 250-key2=value2
    /// 250 OK
    /// ```
    ///
    /// This method lifts every `key=value` line off
    /// ``ControlReply/keyValuePairs`` and returns the dictionary
    /// directly. Non-success replies throw so callers see Tor's
    /// reply code and diagnostic text.
    ///
    /// - Parameter reply: The control reply to decode.
    /// - Returns: A `[key: value]` dictionary with one entry per
    ///   `key=value` line in ``ControlReply/lines``.
    /// - Throws: ``TorError/controlProtocolError(code:message:)`` on
    ///   non-success replies.
    public static func parseGetInfoResponse(_ reply: ControlReply) throws -> [String: String] {
        guard reply.isSuccess else {
            throw TorError.controlProtocolError(
                code: reply.statusCode,
                message: reply.message
            )
        }
        
        return reply.keyValuePairs
    }
}

// MARK: - Async Event Parsing

extension ControlProtocolParser {
    
    /// Decode a `650`-status async-event line into a typed message.
    ///
    /// Control-spec.txt §4.1 defines async events in the form
    /// `650 EVENT_TYPE <payload>`, delivered any time after
    /// `SETEVENTS` subscription. This method splits the line into
    /// the event keyword and payload, looks up the keyword in
    /// ``TorControlEvent``, and runs the payload through
    /// ``parseAttributes(_:)`` to populate
    /// ``TorControlEventMessage/attributes``.
    ///
    /// Unknown event keywords are preserved verbatim but mapped to
    /// ``TorControlEvent/statusGeneral`` so the raw `data` is still
    /// available for diagnostic purposes.
    ///
    /// - Parameter line: A line beginning with `650 `.
    /// - Returns: A decoded ``TorControlEventMessage``, or `nil`
    ///   when the line does not begin with `650` or is empty after
    ///   the status prefix.
    ///
    /// - Note: This parser deliberately does **not** throw on
    ///   unknown events — forward-compatibility with future Tor
    ///   releases depends on tolerating unrecognised keywords.
    public static func parseAsyncEvent(_ line: String) -> TorControlEventMessage? {
        guard line.hasPrefix("650") else {
            return nil
        }
        
        let content = line.dropFirst(4) // Drop "650 " or "650-"
        guard !content.isEmpty else {
            return nil
        }
        
        // Find the event type (first word)
        let parts = content.split(separator: " ", maxSplits: 1)
        guard let eventTypeStr = parts.first else {
            return nil
        }
        
        let eventType = String(eventTypeStr)
        let data = parts.count > 1 ? String(parts[1]) : ""
        
        // Try to match to known event type
        guard let event = TorControlEvent(rawValue: eventType) else {
            // Unknown event type, still parse it
            return TorControlEventMessage(
                event: .statusGeneral,
                data: String(content),
                attributes: parseAttributes(data)
            )
        }
        
        return TorControlEventMessage(
            event: event,
            data: data,
            attributes: parseAttributes(data)
        )
    }
}
