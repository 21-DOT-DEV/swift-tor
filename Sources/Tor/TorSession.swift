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

/// Minimal interface implemented by ``TorClient``, carved out for dependency
/// injection and testability.
///
/// Consumers can provide test doubles that avoid spinning up a real Tor
/// process — useful for exercising view-model state machines, race conditions,
/// and failure paths without the 30–60 s bootstrap cost or network access.
///
/// `TorClient` conforms directly, so most callers can continue to use it
/// unchanged. Only swap in a custom conformer when you need to inject
/// deterministic behavior (e.g. blocking bootstrap, synthesized events,
/// forced start errors).
public protocol TorSession: Sendable {
    /// Start the underlying Tor instance.
    ///
    /// - Throws: An implementation-defined error if start fails.
    func start() async throws

    /// Wait until Tor reports 100% bootstrap progress.
    ///
    /// - Parameter timeout: Maximum time to wait before throwing.
    /// - Throws: An implementation-defined timeout error.
    func waitUntilBootstrapped(timeout: Duration) async throws

    /// Stop the Tor instance and release any resources.
    func stop() async

    /// The SOCKS proxy endpoint, available after bootstrap completes.
    ///
    /// Nil until Tor has started AND selected its SOCKS port.
    var socksEndpoint: HostPort? { get async }

    /// Stream of lifecycle events (bootstrap progress, state changes, logs).
    ///
    /// Each call returns a fresh stream; multiple subscribers are supported.
    var events: AsyncStream<TorEvent> { get async }
}

extension TorSession {
    /// Wait up to the default 120 s bootstrap window.
    ///
    /// Convenience for the common case where the caller doesn't need a
    /// custom timeout.
    public func waitUntilBootstrapped() async throws {
        try await waitUntilBootstrapped(timeout: .seconds(120))
    }
}

// MARK: - TorClient conformance

extension TorClient: TorSession {}
