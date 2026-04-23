[![Apple Platforms](https://github.com/21-DOT-DEV/swift-tor/actions/workflows/apple-builds.yml/badge.svg)](https://github.com/21-DOT-DEV/swift-tor/actions/workflows/apple-builds.yml) [![Docker Builds](https://github.com/21-DOT-DEV/swift-tor/actions/workflows/docker-builds.yml/badge.svg)](https://github.com/21-DOT-DEV/swift-tor/actions/workflows/docker-builds.yml) [![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F21-DOT-DEV%2Fswift-tor%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/21-DOT-DEV/swift-tor) [![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F21-DOT-DEV%2Fswift-tor%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/21-DOT-DEV/swift-tor)

# swift-tor
 
 Swift package that embeds Tor (`libtor`) and provides a Swift-concurrency-first API (`TorClient`), plus Tor control protocol utilities (including ephemeral onion service management).

## Contents

- [Features](#features)
- [Platforms](#platforms)
- [Installation](#installation)
- [Quick Start (Basic)](#quick-start-basic)
- [Creating a Hidden Service](#creating-a-hidden-service)
- [Demo](#demo)
- [Testing](#testing)
- [Roadmap](#roadmap)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)
 
 ## Features
 
 - **Embedded Tor**: run Tor in-process (via the `libtor` product)
 - **High-level API**: `TorClient` actor to start/stop Tor and observe events
 - **Control protocol**: `TorControlClient` for `GETINFO`, `SIGNAL`, `ADD_ONION`, `DEL_ONION`, etc.
 - **Onion services**: create/delete ephemeral v3 onion services
 - **Caching**: optional `cacheDirectory` to reuse consensus/descriptor cache across runs
 - **Apple-only networking helper**: `URLSessionConfiguration` + `TorClient.makeURLSession()` (guarded by `canImport(CFNetwork)`)
 
 ## Platforms
 
 - **macOS**: 15+
 - **iOS**: 18+
 - **Linux**: Ubuntu 22.04+ (via Docker)
 
> [!IMPORTANT]  
> **tvOS/watchOS/visionOS are not supported.** Tor's codebase relies on UNIX process primitives (`fork`, `execve`, `daemon`, `setuid`) that Apple prohibits on these platforms. These restrictions are enforced at the App Store review level and would cause runtime crashes.
 
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

> [!WARNING]  
> This package is pre-1.0 ([SemVer major version zero](https://semver.org/#spec-item-4)). The public API is not stable and may change with any release. Pin a version using `exact:` to avoid unexpected breaking changes.

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

> [!TIP]  
> Reusing a `cacheDirectory` across runs can significantly reduce bootstrap time.
 
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

> [!NOTE]  
> This helper requires `CFNetwork` and is only available on Apple platforms.

```swift
 #if canImport(CFNetwork)
 let session = try await client.makeURLSession()
 let (data, _) = try await session.data(from: URL(string: "https://check.torproject.org/api/ip")!)
 #endif
 ```
 
 ## Creating a Hidden Service

Create an ephemeral v3 onion service that forwards traffic to a local server:

```swift
import Tor

// Start Tor first
let client = TorClient(configuration: .makeDefault())
try await client.start()
try await client.waitUntilBootstrapped()

// Get the control client
let control = try await client.control()

// Create an ephemeral onion service
// - Maps port 80 on the .onion to localhost:8080
// - Private key is discarded (service won't survive restart)
let service = try await control.addOnion(
    key: .newV3(discardPrivateKey: true),
    ports: [.toLocalPort(80, localPort: 8080)]
)

print("🧅 Hidden service running at: \(service.onionAddress)")
// e.g., "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"

// Your local HTTP server on port 8080 is now accessible via Tor!
// Users can reach it at: http://<serviceID>.onion/

// When done, clean up
try await control.delOnion(service)
await client.stop()
```

### Persistent Hidden Services

To create a hidden service that survives restarts, keep the private key:

```swift
// Create service and get the private key
let service = try await control.addOnion(
    key: .newV3(discardPrivateKey: false),  // Keep the key
    ports: [.toLocalPort(443, localPort: 8443)]
)

// Save service.privateKey securely for later use
let privateKey = service.privateKey!  // e.g., "ED25519-V3:base64..."

// Later, recreate the same .onion address:
let restoredService = try await control.addOnion(
    key: .providedV3(privateKey),
    ports: [.toLocalPort(443, localPort: 8443)]
)
// restoredService.onionAddress == service.onionAddress
```

> [!WARNING]  
> Store private keys securely (e.g., Keychain on Apple platforms). Anyone with the private key controls the .onion address.
 
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
 
 - **Linux support**: ✅ complete (Phase 1)
 - **Remove libbsd dependency**: ✅ complete (Phase 2)
 - **iOS Target Refactor**: 🔜 planned (Phase 3)
 - **Binary Size Optimization**: 🔜 planned (Phase 3.5)
 
See [roadmap.md](.specify/memory/roadmap.md) for full details.
 
 ## Security

For information on reporting security vulnerabilities in swift-tor, see [SECURITY.md](SECURITY.md). For other 21-DOT-DEV projects, see the [organization Security Policy](https://github.com/21-DOT-DEV/.github/blob/main/SECURITY.md).

> [!CAUTION]  
> Tor can't "fix" unsafe application behavior. Review the [Tor Project guidance](https://support.torproject.org/) on staying anonymous. Avoid logging sensitive information (credentials, onion private keys). Consider your threat model — Tor integration is only one part of privacy/security.

 ## Contributing

Contributions welcome! Please read the [21-DOT-DEV contributing guidelines](https://github.com/21-DOT-DEV/.github/blob/main/CONTRIBUTING.md) for general workflow. For swift-tor specific guidance and AI-assisted development, see [AGENTS.md](AGENTS.md).

 ## License
 
 This project is licensed under the MIT License. See `LICENSE`.
 
 Tor source code is vendored in `Vendor/tor` and is subject to its own license(s). See `Vendor/tor/LICENSE`.