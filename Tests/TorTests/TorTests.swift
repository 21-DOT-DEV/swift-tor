//
//  TorTests.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Testing
import libtor
@testable import Tor

/// Tor Tests
/// Note: tor_main_configuration_new() crashes in Swift Testing due to
/// unknown interaction between the test harness and Tor's C code.
/// The API works correctly when called from regular Swift code.
@Suite("Tor Tests", .serialized)
struct TorTests {
    
    @Test("tor_api_get_provider_version returns version string")
    func testProviderVersion() {
        let version = tor_api_get_provider_version()
        #expect(version != nil)
        
        if let version = version {
            let str = String(cString: version)
            print("Tor provider version: \(str)")
            #expect(str.contains("tor"))
        }
    }
    
    @Test("tor_main_configuration_new creates configuration")
    func testConfigurationNew() {
        let config = tor_main_configuration_new()
        #expect(config != nil)
        
        if let config = config {
            print("Configuration created successfully")
            tor_main_configuration_free(config)
            print("Configuration freed successfully")
        }
    }
}

// MARK: - Core Types Tests

@Suite("TorConfiguration Tests")
struct TorConfigurationTests {
    
    @Test("makeDefault creates valid configuration")
    func testMakeDefault() {
        let config = TorConfiguration.makeDefault()
        #expect(!config.dataDirectory.isEmpty)
        #expect(config.dataDirectory.contains("tor-"))
    }
    
    @Test("buildArguments includes required options")
    func testBuildArguments() {
        let config = TorConfiguration(
            dataDirectory: "/tmp/tor-test",
            socksPort: .fixed(9050)
        )
        let args = config.buildArguments()
        
        #expect(args.contains("tor"))
        #expect(args.contains("--DataDirectory"))
        #expect(args.contains("/tmp/tor-test"))
        #expect(args.contains("--SocksPort"))
        #expect(args.contains("9050"))
    }
    
    @Test("buildArguments includes cacheDirectory when set")
    func testBuildArgumentsWithCacheDirectory() {
        let config = TorConfiguration(
            dataDirectory: "/tmp/tor-data",
            cacheDirectory: "/persistent/tor-cache",
            socksPort: .ephemeral
        )
        let args = config.buildArguments()
        
        #expect(args.contains("--CacheDirectory"))
        #expect(args.contains("/persistent/tor-cache"))
    }
    
    @Test("buildArguments excludes cacheDirectory when nil")
    func testBuildArgumentsWithoutCacheDirectory() {
        let config = TorConfiguration(
            dataDirectory: "/tmp/tor-data",
            socksPort: .ephemeral
        )
        let args = config.buildArguments()
        
        #expect(!args.contains("--CacheDirectory"))
    }
    
    @Test("PortPolicy descriptions are correct")
    func testPortPolicyDescriptions() {
        #expect(PortPolicy.ephemeral.description == "auto")
        #expect(PortPolicy.fixed(9050).description == "9050")
        #expect(PortPolicy.disabled.description == "0")
    }

    // MARK: - ownsDataDirectory + ephemeral()

    @Test("Default init sets ownsDataDirectory to false")
    func testDefaultInitDoesNotOwnDataDirectory() {
        let config = TorConfiguration(dataDirectory: "/tmp/test-fixed")
        #expect(config.ownsDataDirectory == false)
    }

    @Test("makeDefault does not own the data directory")
    func testMakeDefaultDoesNotOwnDataDirectory() {
        let config = TorConfiguration.makeDefault()
        #expect(config.ownsDataDirectory == false)
    }

    @Test("ephemeral owns its data directory")
    func testEphemeralOwnsDataDirectory() {
        let config = TorConfiguration.ephemeral()
        #expect(config.ownsDataDirectory == true)
    }

    @Test("ephemeral produces a unique data directory per call")
    func testEphemeralPathsAreUnique() {
        let a = TorConfiguration.ephemeral()
        let b = TorConfiguration.ephemeral()
        #expect(a.dataDirectory != b.dataDirectory)
    }

    @Test("ephemeral data directory lives under the temporary directory")
    func testEphemeralPathIsInTempDir() {
        let config = TorConfiguration.ephemeral()
        let tempDir = FileManager.default.temporaryDirectory.path
        #expect(config.dataDirectory.hasPrefix(tempDir))
    }

    @Test("ephemeral propagates an explicit cache directory")
    func testEphemeralPropagatesCacheDirectory() {
        let config = TorConfiguration.ephemeral(cacheDirectory: "/var/cache/tor-test")
        #expect(config.cacheDirectory == "/var/cache/tor-test")
    }

    @Test("ephemeral has a nil cache directory by default")
    func testEphemeralDefaultsNilCacheDirectory() {
        let config = TorConfiguration.ephemeral()
        #expect(config.cacheDirectory == nil)
    }

    @Test("ownsDataDirectory flag is mutable after init")
    func testOwnsDataDirectoryIsMutable() {
        var config = TorConfiguration(dataDirectory: "/tmp/test-mut")
        #expect(config.ownsDataDirectory == false)
        config.ownsDataDirectory = true
        #expect(config.ownsDataDirectory == true)
    }
}

@Suite("TorState Tests")
struct TorStateTests {
    
    @Test("isOperational returns true only for running state")
    func testIsOperational() {
        #expect(!TorState.idle.isOperational)
        #expect(!TorState.starting.isOperational)
        #expect(TorState.running.isOperational)
        #expect(!TorState.stopping.isOperational)
        #expect(!TorState.stopped.isOperational)
        #expect(!TorState.failed(.timeout).isOperational)
    }
    
    @Test("states are equatable")
    func testEquatable() {
        #expect(TorState.idle == TorState.idle)
        #expect(TorState.running == TorState.running)
        #expect(TorState.idle != TorState.running)
    }
}

@Suite("HostPort Tests")
struct HostPortTests {
    
    @Test("localhost creates correct endpoint")
    func testLocalhost() {
        let endpoint = HostPort.localhost(9050)
        #expect(endpoint.host == "127.0.0.1")
        #expect(endpoint.port == 9050)
    }
    
    @Test("description formats correctly")
    func testDescription() {
        let endpoint = HostPort(host: "example.com", port: 443)
        #expect(endpoint.description == "example.com:443")
    }
}

@Suite("OnionService Tests")
struct OnionServiceTests {
    
    @Test("onionAddress appends .onion suffix")
    func testOnionAddress() {
        let service = OnionService(serviceID: "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad")
        #expect(service.onionAddress == "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion")
    }
    
    @Test("OnionKeySpec generates correct key types")
    func testOnionKeySpec() {
        #expect(OnionKeySpec.newV3().keyType == "NEW:ED25519-V3")
        #expect(OnionKeySpec.newV3(discardPrivateKey: true).flags == ["DiscardPK"])
        #expect(OnionKeySpec.newV3(discardPrivateKey: false).flags.isEmpty)
        #expect(OnionKeySpec.providedV3("testkey").keyType == "ED25519-V3:testkey")
    }
    
    @Test("OnionPortMapping creates correct port spec")
    func testOnionPortMapping() {
        let mapping = OnionPortMapping.toLocalPort(80, localPort: 8080)
        #expect(mapping.virtualPort == 80)
        #expect(mapping.portSpec == "Port=80,127.0.0.1:8080")
    }
}

@Suite("TorLogLevel Tests")
struct TorLogLevelTests {
    
    @Test("log levels are comparable")
    func testComparable() {
        #expect(TorLogLevel.debug < TorLogLevel.info)
        #expect(TorLogLevel.info < TorLogLevel.notice)
        #expect(TorLogLevel.notice < TorLogLevel.warn)
        #expect(TorLogLevel.warn < TorLogLevel.err)
    }
}
