//
//  Tor.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Swift-Tor: High-level Swift API for the Tor anonymity network
///
/// This library provides a Swift-native interface for embedding Tor
/// in iOS and macOS applications.
///
/// ## Overview
///
/// The Tor module provides:
/// - ``TorClient``: Main actor for managing an embedded Tor instance
/// - ``TorConfiguration``: Configuration options for Tor
/// - ``TorControlClient``: Client for the Tor control protocol
/// - Onion service management via ``OnionService``
///
/// ## Basic Usage
///
/// ```swift
/// let config = TorConfiguration.makeDefault()
/// let client = TorClient(configuration: config)
/// try await client.start()
/// try await client.waitUntilBootstrapped()
///
/// // Create an onion service
/// let control = try await client.control()
/// let service = try await control.addOnion(
///     key: .newV3(discardPrivateKey: true),
///     ports: [.toLocalPort(80, localPort: 8080)]
/// )
/// print("Onion address: \(service.onionAddress)")
/// ```

@_exported import libtor
