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

/// Log levels used by Tor.
public enum TorLogLevel: String, Sendable, Hashable, Comparable, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case notice = "NOTICE"
    case warn = "WARN"
    case err = "ERR"
    
    private var severity: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .notice: return 2
        case .warn: return 3
        case .err: return 4
        }
    }
    
    public static func < (lhs: TorLogLevel, rhs: TorLogLevel) -> Bool {
        lhs.severity < rhs.severity
    }
}

/// Events emitted by a running Tor instance.
public enum TorEvent: Sendable {
    /// Bootstrap progress update.
    /// - Parameters:
    ///   - progress: Percentage complete (0-100).
    ///   - tag: Machine-readable bootstrap phase tag.
    ///   - summary: Human-readable description of the current phase.
    case bootstrap(progress: Int, tag: String, summary: String)
    
    /// Log message from Tor.
    /// - Parameters:
    ///   - level: The severity level of the log message.
    ///   - message: The log message content.
    case log(level: TorLogLevel, message: String)
    
    /// Tor state changed.
    /// - Parameter state: The new state.
    case stateChanged(TorState)
    
    /// A circuit was established or closed.
    /// - Parameters:
    ///   - id: The circuit ID.
    ///   - status: The circuit status (e.g., "BUILT", "CLOSED").
    case circuit(id: String, status: String)
    
    /// A stream event occurred.
    /// - Parameters:
    ///   - id: The stream ID.
    ///   - status: The stream status.
    ///   - target: The target address if available.
    case stream(id: String, status: String, target: String?)
}

/// Events that can be subscribed to via the control protocol.
public enum TorControlEvent: String, Sendable, Hashable, CaseIterable {
    case statusClient = "STATUS_CLIENT"
    case statusServer = "STATUS_SERVER"
    case statusGeneral = "STATUS_GENERAL"
    case notice = "NOTICE"
    case warn = "WARN"
    case err = "ERR"
    case debug = "DEBUG"
    case info = "INFO"
    case circuitStatus = "CIRC"
    case streamStatus = "STREAM"
    case bandwidthUsed = "BW"
    case newDescriptor = "NEWDESC"
    case addressMap = "ADDRMAP"
}

/// A parsed event message from the control protocol.
public struct TorControlEventMessage: Sendable {
    /// The event type.
    public let event: TorControlEvent
    
    /// The raw event data.
    public let data: String
    
    /// Parsed key-value pairs from the event, if applicable.
    public let attributes: [String: String]
    
    public init(event: TorControlEvent, data: String, attributes: [String: String] = [:]) {
        self.event = event
        self.data = data
        self.attributes = attributes
    }
}
