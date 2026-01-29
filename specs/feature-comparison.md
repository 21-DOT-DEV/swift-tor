# swift-tor Feature Comparison & Draft APIs

**Date**: 2026-01-27  
**Purpose**: Evaluate potential features with complexity, platform support, and draft APIs

---

## Feature Comparison Matrix

| Feature | macOS | Linux | iOS | Complexity | Dependencies | Priority |
|---------|:-----:|:-----:|:---:|:----------:|--------------|:--------:|
| **Tor Client** | ✅ | ✅ | ✅ | — | — | — |
| **Onion Services** | ✅ | ✅ | ✅ | — | — | — |
| **Snowflake Client** | ✅ | ✅ | ✅ | L | WebRTC, SOCKS5 server | High |
| **obfs4 Client** | ✅ | ✅ | ⚠️ | M | None (unmanaged PT) | Medium |
| **Relay Mode** | ✅ | ✅ | ❌ | S | Public IP, ports | Medium |
| **Bridge Mode** | ✅ | ✅ | ❌ | S | Public IP, ports | Medium |
| **DNS over Tor** | ✅ | ✅ | ✅ | S | None | High |
| **Bootstrap Events** | ✅ | ✅ | ✅ | S | None | High |
| **Circuit Isolation** | ✅ | ✅ | ✅ | S | None | Medium |
| **Bandwidth Metrics** | ✅ | ✅ | ✅ | S | None | Low |
| **HSv3 Client Auth** | ✅ | ✅ | ✅ | M | Keychain | Medium |
| **Onion-Location** | ✅ | ✅ | ✅ | M | URL handling | Low |
| **Exit Relay** | ⚠️ | ⚠️ | ❌ | M | Operator expertise | Deferred |

**Legend**:
- ✅ Fully supported
- ⚠️ Supported with caveats
- ❌ Not possible
- **S** = Small (1-2 days), **M** = Medium (3-5 days), **L** = Large (1-3 weeks)

---

## Detailed Feature Analysis

### 1. Snowflake Client Transport

**Complexity**: Large  
**Platforms**: macOS ✅, Linux ✅, iOS ✅  
**Dependencies**: WebRTC library, local SOCKS5 server, broker HTTP client

**What It Does**: Connects to Tor network through WebRTC, bypassing censorship firewalls.

**Implementation Approach**:
- Unmanaged PT: Tor connects to local SOCKS5 server
- SOCKS5 server tunnels through WebRTC data channel
- WebRTC negotiated via Snowflake broker

**Draft API**:

```swift
// Configuration
public struct SnowflakeConfiguration: Sendable {
    /// Snowflake broker URL
    public var brokerURL: URL
    
    /// STUN servers for ICE
    public var stunServers: [String]
    
    /// Optional domain fronting host
    public var frontDomain: String?
    
    /// Maximum concurrent peers
    public var maxPeers: Int
    
    public static var `default`: SnowflakeConfiguration {
        SnowflakeConfiguration(
            brokerURL: URL(string: "https://snowflake-broker.torproject.net/")!,
            stunServers: ["stun:stun.l.google.com:19302"],
            frontDomain: nil,
            maxPeers: 1
        )
    }
}

// Client
public actor SnowflakeClient {
    public enum State: Sendable {
        case idle
        case connecting
        case connected(peerCount: Int)
        case failed(Error)
    }
    
    /// Current connection state
    public var state: State { get async }
    
    /// State change stream
    public var stateStream: AsyncStream<State> { get }
    
    /// Local SOCKS5 port for Tor to connect to
    public var socksPort: Int { get async }
    
    /// Start Snowflake transport
    public func start() async throws
    
    /// Stop Snowflake transport
    public func stop() async
}

// TorConfiguration integration
extension TorConfiguration {
    /// Create configuration using Snowflake transport
    public static func withSnowflake(
        dataDirectory: String,
        snowflake: SnowflakeConfiguration = .default,
        bridgeFingerprints: [String]? = nil
    ) -> TorConfiguration
}

// Convenience on TorClient
extension TorClient {
    /// Start Tor with Snowflake transport
    public static func startWithSnowflake(
        dataDirectory: String,
        snowflake: SnowflakeConfiguration = .default
    ) async throws -> TorClient
}
```

**Usage Example**:

```swift
// Simple usage
let client = try await TorClient.startWithSnowflake(
    dataDirectory: "/tmp/tor-data"
)
try await client.waitUntilBootstrapped()

// Advanced usage
let snowflake = SnowflakeClient(configuration: .default)
try await snowflake.start()

let config = TorConfiguration(
    dataDirectory: "/tmp/tor-data",
    socksPort: .ephemeral,
    useBridges: true,
    clientTransportPlugins: [
        .snowflake(port: await snowflake.socksPort)
    ],
    bridges: [.snowflake()]
)

let client = TorClient(configuration: config)
try await client.start()
```

---

### 2. obfs4 Client Transport

**Complexity**: Medium  
**Platforms**: macOS ✅, Linux ✅, iOS ⚠️ (unmanaged only)  
**Dependencies**: External obfs4proxy binary (managed) or pre-running SOCKS5 (unmanaged)

**What It Does**: Obfuscates Tor traffic to look like random noise, evading DPI.

**iOS Caveat**: Cannot exec obfs4proxy binary. Would need:
- Pre-bundled obfs4 implementation in Swift/C, OR
- Unmanaged PT pointing to external proxy

**Draft API**:

```swift
public enum PluggableTransport: Sendable {
    /// Managed PT - launches external binary (macOS/Linux only)
    case managed(name: String, path: String, options: [String: String])
    
    /// Unmanaged PT - connects to existing SOCKS proxy
    case unmanaged(name: String, socksVersion: SocksVersion, address: String, port: Int)
    
    public enum SocksVersion: Sendable {
        case socks4
        case socks5
    }
}

public struct BridgeLine: Sendable {
    public var transport: String?
    public var address: String
    public var port: Int
    public var fingerprint: String?
    public var options: [String: String]
    
    /// Parse from standard bridge line format
    public init(parsing line: String) throws
    
    /// obfs4 bridge
    public static func obfs4(
        address: String,
        port: Int,
        fingerprint: String,
        cert: String,
        iatMode: Int = 0
    ) -> BridgeLine
    
    /// Snowflake bridge (uses Snowflake transport)
    public static func snowflake(
        fingerprint: String? = nil
    ) -> BridgeLine
}

// TorConfiguration additions
extension TorConfiguration {
    /// Enable bridge mode
    public var useBridges: Bool
    
    /// Bridge lines to use
    public var bridges: [BridgeLine]
    
    /// Client transport plugins
    public var clientTransportPlugins: [PluggableTransport]
}
```

**Usage Example**:

```swift
// Managed PT (macOS/Linux)
let config = TorConfiguration(
    dataDirectory: dataDir,
    socksPort: .ephemeral,
    useBridges: true,
    clientTransportPlugins: [
        .managed(
            name: "obfs4",
            path: "/usr/local/bin/obfs4proxy",
            options: [:]
        )
    ],
    bridges: [
        .obfs4(
            address: "192.0.2.1",
            port: 443,
            fingerprint: "ABCD1234...",
            cert: "base64cert..."
        )
    ]
)

// Unmanaged PT (iOS-compatible)
let config = TorConfiguration(
    dataDirectory: dataDir,
    socksPort: .ephemeral,
    useBridges: true,
    clientTransportPlugins: [
        .unmanaged(
            name: "obfs4",
            socksVersion: .socks5,
            address: "127.0.0.1",
            port: 9999
        )
    ],
    bridges: [
        .obfs4(address: "192.0.2.1", port: 443, fingerprint: "...", cert: "...")
    ]
)
```

---

### 3. DNS over Tor

**Complexity**: Small  
**Platforms**: macOS ✅, Linux ✅, iOS ✅  
**Dependencies**: None (uses existing control protocol)

**What It Does**: Resolve DNS queries through Tor, preventing DNS leaks.

**Draft API**:

```swift
extension TorControlClient {
    /// Resolve a hostname through Tor
    /// - Parameter hostname: The hostname to resolve
    /// - Returns: Resolved IP addresses
    public func resolve(_ hostname: String) async throws -> [String]
    
    /// Reverse resolve an IP address through Tor
    /// - Parameter address: The IP address to reverse resolve
    /// - Returns: Hostname if found
    public func resolveReverse(_ address: String) async throws -> String?
}

// Convenience on TorClient
extension TorClient {
    /// Resolve hostname through Tor
    public func resolve(_ hostname: String) async throws -> [String] {
        let control = try await control()
        return try await control.resolve(hostname)
    }
}
```

**Usage Example**:

```swift
let client = TorClient(configuration: .makeDefault())
try await client.start()
try await client.waitUntilBootstrapped()

// Resolve through Tor
let addresses = try await client.resolve("example.com")
print("Resolved: \(addresses)")  // ["93.184.216.34"]

// Reverse lookup
let hostname = try await client.resolve(reverse: "93.184.216.34")
print("Hostname: \(hostname ?? "unknown")")
```

**Implementation** (control protocol):

```swift
func resolve(_ hostname: String) async throws -> [String] {
    // Send: RESOLVE hostname
    // Response: 250 hostname=IP or 250-hostname=IP1\n250 hostname=IP2
    let response = try await sendCommand("RESOLVE \(hostname)")
    return parseResolveResponse(response)
}
```

---

### 4. Bootstrap Events

**Complexity**: Small  
**Platforms**: macOS ✅, Linux ✅, iOS ✅  
**Dependencies**: None (extends existing event handling)

**What It Does**: Provides detailed, structured bootstrap progress events.

**Draft API**:

```swift
public struct BootstrapStatus: Sendable {
    /// Progress percentage (0-100)
    public let progress: Int
    
    /// Bootstrap phase tag (e.g., "handshake", "circuit_create")
    public let tag: String
    
    /// Human-readable summary
    public let summary: String
    
    /// Warning message if bootstrap is slow
    public let warning: String?
    
    /// Recommended action for warnings
    public let recommendation: String?
    
    /// Whether bootstrap has completed
    public var isComplete: Bool { progress == 100 }
}

public enum BootstrapPhase: String, Sendable, CaseIterable {
    case starting = "starting"
    case connectingToRelay = "conn"
    case handshake = "handshake"
    case requestingNetworkStatus = "onehop_create"
    case loadingNetworkStatus = "requesting_status"
    case loadingAuthorityCertificates = "loading_keys"
    case requestingDescriptors = "requesting_descriptors"
    case loadingDescriptors = "loading_descriptors"
    case connectingToEntryGuard = "conn_or"
    case handshakeWithEntryGuard = "handshake_or"
    case establishingCircuit = "circuit_create"
    case done = "done"
}

extension TorClient {
    /// Stream of bootstrap status updates
    public var bootstrapStream: AsyncStream<BootstrapStatus> { get }
    
    /// Current bootstrap status
    public var bootstrapStatus: BootstrapStatus? { get async }
}
```

**Usage Example**:

```swift
let client = TorClient(configuration: .makeDefault())
try await client.start()

// Stream bootstrap progress
for await status in client.bootstrapStream {
    print("[\(status.progress)%] \(status.summary)")
    
    if let warning = status.warning {
        print("⚠️ \(warning)")
        if let rec = status.recommendation {
            print("   Suggestion: \(rec)")
        }
    }
    
    if status.isComplete {
        break
    }
}

print("✅ Tor bootstrapped!")
```

---

### 5. Circuit Isolation

**Complexity**: Small  
**Platforms**: macOS ✅, Linux ✅, iOS ✅  
**Dependencies**: None (SOCKS port configuration)

**What It Does**: Ensures different connections use different Tor circuits for privacy.

**Draft API**:

```swift
public struct SocksPortConfiguration: Sendable {
    /// Port number or ephemeral
    public var port: PortPolicy
    
    /// Isolate by destination address
    public var isolateDestAddr: Bool
    
    /// Isolate by destination port
    public var isolateDestPort: Bool
    
    /// Isolate by SOCKS auth credentials
    public var isolateSOCKSAuth: Bool
    
    /// Isolate by client address
    public var isolateClientAddr: Bool
    
    /// Keep circuits alive while streams are attached
    public var keepAliveIsolateSOCKSAuth: Bool
    
    /// Disallow .onion address resolution via SOCKS5
    public var onionTrafficOnly: Bool
    
    public static var `default`: SocksPortConfiguration {
        SocksPortConfiguration(
            port: .ephemeral,
            isolateDestAddr: true,
            isolateDestPort: false,
            isolateSOCKSAuth: true,
            isolateClientAddr: false,
            keepAliveIsolateSOCKSAuth: true,
            onionTrafficOnly: false
        )
    }
    
    /// Configuration for maximum isolation
    public static var maxIsolation: SocksPortConfiguration {
        SocksPortConfiguration(
            port: .ephemeral,
            isolateDestAddr: true,
            isolateDestPort: true,
            isolateSOCKSAuth: true,
            isolateClientAddr: true,
            keepAliveIsolateSOCKSAuth: true,
            onionTrafficOnly: false
        )
    }
}

extension TorConfiguration {
    /// SOCKS port with isolation settings
    public var socksPortConfiguration: SocksPortConfiguration
}
```

**Usage Example**:

```swift
// Each destination gets its own circuit
let config = TorConfiguration(
    dataDirectory: dataDir,
    socksPortConfiguration: .maxIsolation
)

// Custom isolation
var isolation = SocksPortConfiguration.default
isolation.isolateDestPort = true  // Different circuit per destination port
isolation.onionTrafficOnly = true // Only allow .onion addresses

let config = TorConfiguration(
    dataDirectory: dataDir,
    socksPortConfiguration: isolation
)
```

---

### 6. Relay Mode

**Complexity**: Small  
**Platforms**: macOS ✅, Linux ✅, iOS ❌  
**Dependencies**: Public IP, open ports, port forwarding

**What It Does**: Runs Tor as a relay, contributing bandwidth to the network.

**Draft API**:

```swift
public struct RelayConfiguration: Sendable {
    /// Onion Router port (must be reachable from internet)
    public var orPort: PortPolicy
    
    /// Optional directory port
    public var dirPort: PortPolicy?
    
    /// Relay nickname (3-19 alphanumeric chars)
    public var nickname: String
    
    /// Contact email for relay operators
    public var contactInfo: String
    
    /// Enable bridge mode (unlisted relay for censored users)
    public var bridgeRelay: Bool
    
    /// Allow exit traffic (NOT RECOMMENDED for embedded)
    public var exitRelay: Bool
    
    /// Exit policy (only if exitRelay is true)
    public var exitPolicy: [ExitPolicyRule]?
    
    /// Bandwidth rate limit
    public var bandwidthRate: Int?
    
    /// Bandwidth burst limit
    public var bandwidthBurst: Int?
    
    /// Accounting settings for monthly bandwidth caps
    public var accountingMax: String?
    public var accountingStart: String?
}

public struct ExitPolicyRule: Sendable {
    public enum Action: String, Sendable {
        case accept
        case reject
    }
    
    public var action: Action
    public var address: String  // "*" for any, or CIDR
    public var ports: String    // "*", single port, or range "80-443"
    
    public static func accept(_ address: String = "*", ports: String) -> ExitPolicyRule
    public static func reject(_ address: String = "*", ports: String) -> ExitPolicyRule
    
    /// Default reduced exit policy (web only)
    public static var reducedExit: [ExitPolicyRule] {
        [
            .accept(ports: "80"),
            .accept(ports: "443"),
            .reject(ports: "*")
        ]
    }
}

public struct RelayStatus: Sendable {
    /// Is ORPort reachable from internet
    public var isReachable: Bool
    
    /// Has descriptor been published
    public var descriptorPublished: Bool
    
    /// Fingerprint (after key generation)
    public var fingerprint: String?
    
    /// Bandwidth observed
    public var bandwidthObserved: Int?
    
    /// Uptime in seconds
    public var uptime: Int
}

extension TorConfiguration {
    /// Relay configuration (nil for client-only mode)
    public var relay: RelayConfiguration?
}

extension TorClient {
    /// Current relay status (nil if not running as relay)
    public var relayStatus: RelayStatus? { get async }
    
    /// Stream of relay status updates
    public var relayStatusStream: AsyncStream<RelayStatus> { get }
}
```

**Usage Example**:

```swift
#if os(macOS) || os(Linux)
let config = TorConfiguration(
    dataDirectory: "/var/lib/tor",
    socksPort: .fixed(9050),
    relay: RelayConfiguration(
        orPort: .fixed(9001),
        nickname: "MySwiftRelay",
        contactInfo: "operator@example.com",
        bridgeRelay: false,
        exitRelay: false
    )
)

let client = TorClient(configuration: config)
try await client.start()

// Monitor relay status
for await status in client.relayStatusStream {
    if status.isReachable && status.descriptorPublished {
        print("✅ Relay is active! Fingerprint: \(status.fingerprint ?? "pending")")
        break
    } else if !status.isReachable {
        print("⚠️ ORPort not reachable - check firewall/port forwarding")
    }
}
#endif
```

---

### 7. Bandwidth Metrics

**Complexity**: Small  
**Platforms**: macOS ✅, Linux ✅, iOS ✅  
**Dependencies**: None (control protocol)

**What It Does**: Exposes traffic statistics for monitoring.

**Draft API**:

```swift
public struct BandwidthMetrics: Sendable {
    /// Bytes read since Tor started
    public var bytesRead: UInt64
    
    /// Bytes written since Tor started
    public var bytesWritten: UInt64
    
    /// Current read rate (bytes/sec, 1-second average)
    public var readRate: UInt64
    
    /// Current write rate (bytes/sec, 1-second average)
    public var writeRate: UInt64
}

public struct CircuitMetrics: Sendable {
    /// Number of established circuits
    public var circuitCount: Int
    
    /// Number of pending circuits
    public var pendingCircuits: Int
    
    /// Number of active streams
    public var streamCount: Int
}

extension TorClient {
    /// Current bandwidth metrics
    public var bandwidthMetrics: BandwidthMetrics { get async throws }
    
    /// Current circuit metrics
    public var circuitMetrics: CircuitMetrics { get async throws }
    
    /// Stream of bandwidth updates (emitted every second)
    public var bandwidthStream: AsyncStream<BandwidthMetrics> { get }
}
```

**Usage Example**:

```swift
// One-time query
let bw = try await client.bandwidthMetrics
print("Traffic: \(bw.bytesRead / 1024)KB down, \(bw.bytesWritten / 1024)KB up")
print("Rate: \(bw.readRate / 1024)KB/s down, \(bw.writeRate / 1024)KB/s up")

// Continuous monitoring
for await metrics in client.bandwidthStream {
    print("↓ \(metrics.readRate / 1024)KB/s  ↑ \(metrics.writeRate / 1024)KB/s")
}
```

---

### 8. HSv3 Client Auth

**Complexity**: Medium  
**Platforms**: macOS ✅, Linux ✅, iOS ✅  
**Dependencies**: Keychain (optional, for secure storage)

**What It Does**: Authenticate to private onion services that require client authorization.

**Draft API**:

```swift
public struct OnionClientAuth: Sendable {
    /// Onion address (without .onion suffix)
    public var onionAddress: String
    
    /// x25519 private key (base32 encoded)
    public var privateKey: String
    
    /// Optional friendly name
    public var nickname: String?
    
    /// Create from .auth_private file format
    public init(parsing authPrivateLine: String) throws
    
    /// Generate new keypair
    public static func generate(for onionAddress: String) -> (clientAuth: OnionClientAuth, publicKey: String)
}

extension TorConfiguration {
    /// Directory containing .auth_private files
    public var clientOnionAuthDir: String?
}

extension TorControlClient {
    /// Add client auth credential at runtime
    public func addOnionClientAuth(_ auth: OnionClientAuth) async throws
    
    /// Remove client auth credential
    public func removeOnionClientAuth(for onionAddress: String) async throws
    
    /// List configured client auths
    public func listOnionClientAuth() async throws -> [OnionClientAuth]
}
```

**Usage Example**:

```swift
// From .auth_private file
let auth = try OnionClientAuth(
    parsing: "descriptor:x25519:ABCDEF..."
)

let control = try await client.control()
try await control.addOnionClientAuth(auth)

// Now can connect to the private onion service
let session = try await client.makeURLSession()
let (data, _) = try await session.data(from: URL(string: "http://\(auth.onionAddress).onion/")!)

// Or configure via directory
let config = TorConfiguration(
    dataDirectory: dataDir,
    socksPort: .ephemeral,
    clientOnionAuthDir: "/path/to/auth/keys/"
)
```

---

## Implementation Priority Recommendation

### Phase 1: Quick Wins (1-2 weeks)

| Feature | Effort | Value | Notes |
|---------|--------|-------|-------|
| DNS over Tor | S | High | Prevents DNS leaks |
| Bootstrap Events | S | High | Better UX |
| Bandwidth Metrics | S | Medium | Monitoring |
| Circuit Isolation | S | Medium | Privacy improvement |

### Phase 2: Core Censorship (3-4 weeks)

| Feature | Effort | Value | Notes |
|---------|--------|-------|-------|
| PT Configuration API | S | High | Foundation for transports |
| obfs4 Client | M | High | Simpler than Snowflake |

### Phase 3: Snowflake (4-6 weeks)

| Feature | Effort | Value | Notes |
|---------|--------|-------|-------|
| Snowflake Client | L | Very High | Censorship circumvention |

### Phase 4: Advanced (2-4 weeks)

| Feature | Effort | Value | Notes |
|---------|--------|-------|-------|
| HSv3 Client Auth | M | Medium | Private onion services |
| Relay Mode | S | Medium | Network contribution |
| Bridge Mode | S | Medium | Help censored users |

---

## Appendix: Control Protocol Commands

| Feature | Control Command | Notes |
|---------|-----------------|-------|
| DNS over Tor | `RESOLVE hostname` | Async response |
| Bootstrap | `GETINFO status/bootstrap-phase` | Or subscribe to events |
| Bandwidth | `GETINFO traffic/read`, `traffic/written` | Cumulative bytes |
| Circuits | `GETINFO circuit-status` | List all circuits |
| Relay Status | `GETINFO status/reachability-succeeded/or` | Boolean |
| Client Auth | `ONION_CLIENT_AUTH_ADD`, `_REMOVE`, `_VIEW` | Runtime management |

---

*Document generated for feature planning. APIs are drafts subject to refinement during implementation.*
