# swift-tor
 
 Swift package that embeds Tor (`libtor`) and provides a Swift-concurrency-first API (`TorClient`), plus Tor control protocol utilities (including ephemeral onion service management).
 
 ## Features
 
 - **Embedded Tor**: run Tor in-process (via the `libtor` product)
 - **High-level API**: `TorClient` actor to start/stop Tor and observe events
 - **Control protocol**: `TorControlClient` for `GETINFO`, `SIGNAL`, `ADD_ONION`, `DEL_ONION`, etc.
 - **Onion services**: create/delete ephemeral v3 onion services
 - **Caching**: optional `cacheDirectory` to reuse consensus/descriptor cache across runs
 - **Apple-only networking helper**: `URLSessionConfiguration` + `TorClient.makeURLSession()` (guarded by `canImport(CFNetwork)`)
 
 ## Platforms
 
 - **macOS**: 13+
 - **iOS**: 16+
 - **tvOS**: 16+
 - **watchOS**: 9+
 - **visionOS**: 1+
 
 ## Installation
 
 This package uses Swift Package Manager.
 
 ### Xcode
 
 1. Go to `File > Add Packages...`
 2. Enter the package URL: `https://github.com/21-DOT-DEV/swift-tor`
 3. Select the desired version
 
 ### Package.swift
 
 Add the dependency:
 
 ```swift
 .package(url: "https://github.com/21-DOT-DEV/swift-tor", from: "0.1.0"),
 ```
 
 Then add `Tor` as a dependency:
 
 ```swift
 .target(
     name: "MyApp",
     dependencies: [
         .product(name: "Tor", package: "swift-tor")
     ]
 )
 ```
 
 ## Quick Start (Basic)
 
 Start Tor, wait for bootstrap, and get a SOCKS endpoint:
 
 ```swift
 import Tor
 
 let config = TorConfiguration.makeDefault()
 let client = TorClient(configuration: config)
 
 try await client.start()
 try await client.waitUntilBootstrapped()
 
 let socks = await client.socksEndpoint
 ```
 
 ### Faster bootstraps with `cacheDirectory`
 
 Reusing a `cacheDirectory` across runs can significantly reduce bootstrap time.
 
 ```swift
 import Tor
 import Foundation
 
 let tempDataDir = FileManager.default.temporaryDirectory
     .appendingPathComponent("tor-data-\(UUID().uuidString)")
     .path
 
 let cacheDir = FileManager.default.temporaryDirectory
     .appendingPathComponent("tor-cache")
     .path
 
 try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
 
 let config = TorConfiguration(
     dataDirectory: tempDataDir,
     cacheDirectory: cacheDir,
     socksPort: .ephemeral
 )
 
 let client = TorClient(configuration: config)
 try await client.start()
 try await client.waitUntilBootstrapped()
 ```
 
 ### Apple-only: URLSession via Tor
 
 ```swift
 #if canImport(CFNetwork)
 let session = try await client.makeURLSession()
 let (data, _) = try await session.data(from: URL(string: "https://check.torproject.org/api/ip")!)
 #endif
 ```
 
 ## Quick Start (Advanced)
 
 Use the control protocol to manage onion services:
 
 ```swift
 import Tor
 
 let control = try await client.control()
 
 let service = try await control.addOnion(
     key: .newV3(discardPrivateKey: true),
     ports: [.toLocalPort(80, localPort: 8080)]
 )
 
 print(service.onionAddress)
 
 try await control.delOnion(service)
 ```
 
 ## Demo
 
 Run the bundled demo:
 
 ```bash
 swift run TorDemo
 ```
 
 The demo starts Tor, fetches a clearnet URL via Tor, fetches an `.onion`, and creates/deletes an ephemeral onion service.
 
 ## Testing
 
 Run unit tests:
 
 ```bash
 swift test
 ```
 
 Integration tests are **env-gated** and skipped by default:
 
 ```bash
 TOR_INTEGRATION_TESTS=1 swift test --filter IntegrationTests
 ```
 
 ## Roadmap
 
 - **Linux support**: planned (not yet supported by the current package manifest/CI)
 
 ## Security & Privacy Notes
 
 - Tor can’t “fix” unsafe application behavior. Review the Tor Project guidance on staying anonymous.
 - Avoid logging sensitive information (credentials, onion private keys, etc.).
 - Consider your threat model; Tor integration is only one part of privacy/security.
 
 ## License
 
 This project is licensed under the MIT License. See `LICENSE`.
 
 Tor source code is vendored in `Vendor/tor` and is subject to its own license(s). See `Vendor/tor/LICENSE`.