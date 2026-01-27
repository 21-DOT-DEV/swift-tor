//
//  TorState.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Represents the current state of a Tor instance.
public enum TorState: Sendable, Hashable, CustomStringConvertible {
    /// Tor has not been started.
    case idle
    
    /// Tor is in the process of starting.
    case starting
    
    /// Tor is running and operational.
    case running
    
    /// Tor is in the process of stopping.
    case stopping
    
    /// Tor has stopped.
    case stopped
    
    /// Tor encountered an error.
    case failed(TorError)
    
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
    
    /// Whether Tor is currently operational and can accept connections.
    public var isOperational: Bool {
        if case .running = self { return true }
        return false
    }
}

extension TorState: Equatable {
    public static func == (lhs: TorState, rhs: TorState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.starting, .starting),
             (.running, .running),
             (.stopping, .stopping),
             (.stopped, .stopped):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}
