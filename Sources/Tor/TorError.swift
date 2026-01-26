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

/// Errors that can occur when working with Tor.
public enum TorError: Error, Sendable, Hashable, CustomStringConvertible {
    // MARK: - Lifecycle Errors
    
    /// Tor is already started.
    case alreadyStarted
    
    /// Tor has not been started.
    case notStarted
    
    /// Tor failed to start.
    case startFailed(String)
    
    // MARK: - Control Errors
    
    /// The control connection is not available.
    case controlUnavailable
    
    /// Authentication with the control port failed.
    case controlAuthFailed(String)
    
    /// The control protocol returned an error.
    case controlProtocolError(code: Int, message: String)
    
    // MARK: - Onion Service Errors
    
    /// The specified service ID is invalid.
    case invalidServiceID(String)
    
    /// An onion service with this ID already exists.
    case serviceAlreadyExists(String)
    
    // MARK: - General Errors
    
    /// The operation timed out.
    case timeout
    
    /// Received an invalid or unexpected response.
    case invalidResponse(String)
    
    /// An I/O error occurred.
    case ioError(String)
    
    /// Resources are exhausted.
    case resourceExhausted(String)
    
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
