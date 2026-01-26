//
//  IntegrationTests.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import Tor

/// Integration tests that require a real Tor network connection.
///
/// These tests are gated by the `TOR_INTEGRATION_TESTS` environment variable.
/// To run them:
/// ```
/// TOR_INTEGRATION_TESTS=1 swift test --filter IntegrationTests
/// ```
///
/// **Warning**: These tests take 1-3 minutes to run due to Tor bootstrap time.
@Suite("Integration Tests", .enabled(if: ProcessInfo.processInfo.environment["TOR_INTEGRATION_TESTS"] != nil))
struct IntegrationTests {
    
    /// Shared cache directory for faster subsequent test runs.
    static let cacheDirectory: String = {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("tor-test-cache")
            .path
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }()
    
    /// Creates a test configuration with caching enabled.
    func makeTestConfiguration() -> TorConfiguration {
        let dataDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tor-test-\(UUID().uuidString)")
            .path
        return TorConfiguration(
            dataDirectory: dataDir,
            cacheDirectory: Self.cacheDirectory,
            socksPort: .ephemeral
        )
    }
    
    // MARK: - TorClient Lifecycle Tests
    
    @Test("TorClient starts and bootstraps successfully")
    func testTorClientBootstrap() async throws {
        let client = TorClient(configuration: makeTestConfiguration())
        
        try await client.start()
        
        // Should be in starting or running state
        let state = await client.state
        #expect(state == .starting || state == .running)
        
        // Wait for bootstrap (3 minute timeout for cold cache)
        try await client.waitUntilBootstrapped(timeout: .seconds(180))
        
        // Should have SOCKS endpoint
        let endpoint = await client.socksEndpoint
        #expect(endpoint != nil)
        #expect(endpoint!.port > 0)
        
        // Clean shutdown
        await client.stop()
        
        let finalState = await client.state
        #expect(finalState == .stopped)
    }
    
    @Test("TorClient state transitions are correct")
    func testTorClientStateTransitions() async throws {
        let client = TorClient(configuration: makeTestConfiguration())
        
        // Initial state
        var state = await client.state
        #expect(state == .idle)
        
        // Start
        try await client.start()
        state = await client.state
        #expect(state == .starting || state == .running)
        
        // Wait for running
        try await client.waitUntilBootstrapped(timeout: .seconds(180))
        state = await client.state
        #expect(state == .running)
        
        // Stop
        await client.stop()
        state = await client.state
        #expect(state == .stopped)
    }
    
    @Test("TorClient rejects double start")
    func testTorClientDoubleStart() async throws {
        let client = TorClient(configuration: makeTestConfiguration())
        
        try await client.start()
        
        // Second start should throw
        await #expect(throws: TorError.self) {
            try await client.start()
        }
        
        await client.stop()
    }
    
    // MARK: - Control Protocol Tests
    
    @Test("TorControlClient getInfo returns valid data")
    func testControlGetInfo() async throws {
        let client = TorClient(configuration: makeTestConfiguration())
        try await client.start()
        try await client.waitUntilBootstrapped(timeout: .seconds(180))
        
        let control = try await client.control()
        
        // Get version
        let version = try await control.getInfo("version")
        #expect(version != nil)
        #expect(version!.contains("Tor"))
        
        // Get bootstrap status
        let status = try await control.getBootstrapStatus()
        #expect(status != nil)
        #expect(status!.progress == 100)
        
        await client.stop()
    }
    
    // MARK: - Onion Service Tests
    
    @Test("Create and delete ephemeral onion service")
    func testOnionServiceLifecycle() async throws {
        let client = TorClient(configuration: makeTestConfiguration())
        try await client.start()
        try await client.waitUntilBootstrapped(timeout: .seconds(180))
        
        let control = try await client.control()
        
        // Create onion service
        let service = try await control.addOnion(
            key: .newV3(discardPrivateKey: true),
            ports: [.toLocalPort(80, localPort: 8080)]
        )
        
        #expect(!service.serviceID.isEmpty)
        #expect(service.onionAddress.hasSuffix(".onion"))
        #expect(service.privateKey == nil) // DiscardPK was set
        
        // Delete onion service
        try await control.delOnion(service)
        
        await client.stop()
    }
    
    @Test("Create onion service with private key returned")
    func testOnionServiceWithKey() async throws {
        let client = TorClient(configuration: makeTestConfiguration())
        try await client.start()
        try await client.waitUntilBootstrapped(timeout: .seconds(180))
        
        let control = try await client.control()
        
        // Create onion service without discarding key
        let service = try await control.addOnion(
            key: .newV3(discardPrivateKey: false),
            ports: [.toLocalPort(443, localPort: 8443)]
        )
        
        #expect(!service.serviceID.isEmpty)
        #expect(service.privateKey != nil)
        #expect(service.privateKey!.contains("ED25519-V3"))
        
        // Clean up
        try await control.delOnion(service)
        await client.stop()
    }
    
    @Test("Delete non-existent onion service throws error")
    func testDeleteNonExistentOnionService() async throws {
        let client = TorClient(configuration: makeTestConfiguration())
        try await client.start()
        try await client.waitUntilBootstrapped(timeout: .seconds(180))
        
        let control = try await client.control()
        
        // Try to delete a non-existent service
        await #expect(throws: TorError.self) {
            try await control.delOnion("nonexistentserviceid1234567890abcdef")
        }
        
        await client.stop()
    }
    
    // MARK: - Network Tests (Apple only)
    
    #if canImport(CFNetwork)
    @Test("URLSession fetches via Tor SOCKS proxy")
    func testURLSessionViaTor() async throws {
        let client = TorClient(configuration: makeTestConfiguration())
        try await client.start()
        try await client.waitUntilBootstrapped(timeout: .seconds(180))
        
        let session = try await client.makeURLSession()
        
        // Fetch Tor check API
        let url = URL(string: "https://check.torproject.org/api/ip")!
        let (data, response) = try await session.data(from: url)
        
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 200)
        
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"IsTor\":true") || json.contains("\"IsTor\": true"))
        
        await client.stop()
    }
    #endif
}
