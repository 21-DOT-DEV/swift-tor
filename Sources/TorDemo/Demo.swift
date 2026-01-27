//
//  Demo.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Tor

// MARK: - Main

@main
struct TorDemo {
    static func main() async {
        print("=== Tor Demo ===")
        print()
        
        // Show version
        if let version = tor_api_get_provider_version() {
            print("📦 Tor version: \(String(cString: version))")
        }
        print()
        
        // Create Tor client with persistent cache for faster subsequent bootstraps
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tor-demo-\(ProcessInfo.processInfo.processIdentifier)")
            .path
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tor-cache")
            .path
        
        // Create cache directory if needed
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        
        let config = TorConfiguration(
            dataDirectory: tempDir,
            cacheDirectory: cacheDir,  // Reused across runs for faster bootstrap
            socksPort: .ephemeral
        )
        print("📁 Cache directory: \(cacheDir)")
        let client = TorClient(configuration: config)
        
        do {
            // Start Tor
            print("📡 Starting Tor...")
            try await client.start()
            
            print("⏳ Waiting for Tor to bootstrap (this may take 1-2 minutes)...")
            
            // Monitor bootstrap progress (only print when it changes)
            var lastProgress = -1
            let progressTask = Task {
                for await event in await client.events {
                    if case .bootstrap(let progress, _, let summary) = event {
                        if progress != lastProgress {
                            lastProgress = progress
                            print("   [\(progress)%] \(summary)")
                        }
                    }
                }
            }
            
            try await client.waitUntilBootstrapped(timeout: .seconds(180))
            progressTask.cancel()
            
            print()
            print("✅ Tor bootstrapped successfully!")
            
            if let endpoint = await client.socksEndpoint {
                print("🔌 SOCKS proxy: \(endpoint)")
            }
            print()
            
#if canImport(CFNetwork)
            // Create a URLSession routed through Tor (Apple platforms only)
            let session = try await client.makeURLSession()
            
            // Fetch clearnet URL via Tor
            let testURL = URL(string: "https://check.torproject.org/api/ip")!
            print("🌐 Fetching \(testURL) via Tor...")
            
            let (data, _) = try await session.data(from: testURL)
            
            if let json = String(data: data, encoding: .utf8) {
                print("📥 Response: \(json)")
                
                if json.contains("\"IsTor\":true") || json.contains("\"IsTor\": true") {
                    print()
                    print("🎉 SUCCESS: Traffic is routing through Tor!")
                } else {
                    print()
                    print("⚠️  Response received but may not be through Tor")
                }
            }
            
            print()
            
            // Test .onion hidden service
            let onionURL = URL(string: "http://2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion/")!
            print("🧅 Fetching \(onionURL) (hidden service)...")
            
            do {
                let (onionData, _) = try await session.data(from: onionURL)
                if let html = String(data: onionData, encoding: .utf8) {
                    if html.contains("Tor Project") || html.contains("<html") {
                        print("📥 Received \(onionData.count) bytes from .onion")
                        print()
                        print("🎉 SUCCESS: .onion hidden service accessible!")
                    } else {
                        print("📥 Received response but content unexpected")
                    }
                }
            } catch {
                print("⚠️  .onion fetch failed: \(error.localizedDescription)")
            }
            
            print()
#else
            // On Linux, URLSession SOCKS proxy support requires CFNetwork
            print("ℹ️  URLSession SOCKS proxy routing requires Apple platforms")
            print("   Use the SOCKS endpoint directly with your preferred HTTP client")
            print()
#endif
            
            // Demo: Create an ephemeral onion service
            print("🧅 Creating ephemeral onion service...")
            
            let control = try await client.control()
            let service = try await control.addOnion(
                key: .newV3(discardPrivateKey: true),
                ports: [.toLocalPort(80, localPort: 8080)]
            )
            
            print("✅ Onion service created!")
            print("   Address: \(service.onionAddress)")
            print("   Port mapping: 80 -> 127.0.0.1:8080")
            print()
            
            // Delete the onion service
            print("🗑️  Deleting onion service...")
            try await control.delOnion(service)
            print("✅ Onion service deleted!")
            
            print()
            
            // Stop Tor
            print("🛑 Stopping Tor...")
            await client.stop()
            print("✅ Tor stopped!")
            
        } catch {
            print("❌ Error: \(error)")
        }
        
        print()
        print("=== Demo complete ===")
    }
}
