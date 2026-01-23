import Foundation
import libtor

// MARK: - Tor Runner

/// Manages an embedded Tor instance using Swift 6 concurrency best practices
actor TorRunner {
    private var isRunning = false
    private var torTask: Task<Int32, Never>?
    private let dataDirectory: URL
    private let clock = ContinuousClock()
    
    init() {
        // Create temp directory for Tor data
        let tempDir = FileManager.default.temporaryDirectory
        dataDirectory = tempDir.appendingPathComponent("tor-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }
    
    /// Start Tor in background
    func start(socksPort: UInt16 = 9050) async throws {
        guard !isRunning else { return }
        isRunning = true
        
        print("📡 Starting Tor (SOCKS port: \(socksPort))...")
        
        let dataDir = dataDirectory // Capture for Sendable closure
        torTask = Task.detached {
            guard let config = tor_main_configuration_new() else {
                print("❌ Failed to create Tor configuration")
                return Int32(-1)
            }
            
            // Build command line arguments
            let args: [String] = [
                "tor",
                "--SocksPort", "\(socksPort)",
                "--DataDirectory", dataDir.path,
                "--Log", "notice stdout",
                "--DisableNetwork", "0"
            ]
            
            // Convert to C strings
            let cArgs = args.map { strdup($0) }
            defer { cArgs.forEach { free($0) } }
            
            var argv = cArgs.map { UnsafeMutablePointer(mutating: $0) }
            argv.append(nil)
            
            tor_main_configuration_set_command_line(config, Int32(args.count), &argv)
            
            print("🚀 Tor daemon starting...")
            let result = tor_run_main(config)
            
            tor_main_configuration_free(config)
            return result
        }
    }
    
    /// Wait for Tor to fully bootstrap by testing actual SOCKS5 connectivity
    func waitForBootstrap(socksPort: UInt16, timeout: Duration = .seconds(120)) async -> Bool {
        let deadline = clock.now + timeout
        
        // First wait for port to open (max 10 seconds)
        let portDeadline = clock.now + .seconds(10)
        while clock.now < portDeadline {
            if Self.checkPortOpen(port: socksPort) {
                break
            }
            try? await Task.sleep(for: .milliseconds(500))
            
            // Check for cancellation
            if Task.isCancelled { return false }
        }
        
        // Then wait for SOCKS5 to actually work (Tor bootstrapped)
        let startTime = clock.now
        while clock.now < deadline {
            if Self.testSOCKS5Connection(port: socksPort) {
                return true
            }
            
            try? await Task.sleep(for: .seconds(3))
            
            // Check for cancellation
            if Task.isCancelled { return false }
            
            let elapsed = startTime.duration(to: clock.now)
            print("⏳ Waiting for Tor to establish circuits... (\(Int(elapsed.components.seconds))s)")
        }
        return false
    }
    
    /// Check if port is open (nonisolated - pure I/O, no shared state)
    nonisolated private static func checkPortOpen(port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
    
    /// Test if SOCKS5 can actually route traffic (nonisolated - pure I/O)
    nonisolated private static func testSOCKS5Connection(port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard connected else { return false }
        
        // SOCKS5 greeting: version 5, 1 auth method, no auth
        var greeting: [UInt8] = [0x05, 0x01, 0x00]
        send(sock, &greeting, greeting.count, 0)
        
        // Read response
        var response = [UInt8](repeating: 0, count: 2)
        let bytesRead = recv(sock, &response, 2, 0)
        guard bytesRead == 2, response[0] == 0x05, response[1] == 0x00 else {
            return false
        }
        
        // SOCKS5 connect request to check.torproject.org:443
        let host = "check.torproject.org"
        var request: [UInt8] = [
            0x05,                    // Version
            0x01,                    // Connect
            0x00,                    // Reserved
            0x03,                    // Domain name
            UInt8(host.count)        // Domain length
        ]
        request.append(contentsOf: host.utf8)
        request.append(contentsOf: [0x01, 0xBB]) // Port 443 in big-endian
        
        send(sock, &request, request.count, 0)
        
        // Read connect response (with timeout)
        var connectResponse = [UInt8](repeating: 0, count: 10)
        
        // Set read timeout
        var tv = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        
        let connectBytesRead = recv(sock, &connectResponse, 10, 0)
        
        // Check if connection succeeded (response[1] == 0x00 means success)
        return connectBytesRead >= 2 && connectResponse[0] == 0x05 && connectResponse[1] == 0x00
    }
    
    deinit {
        torTask?.cancel()
        try? FileManager.default.removeItem(at: dataDirectory)
    }
}

// MARK: - SOCKS5 URL Fetch

/// Fetch URL through Tor SOCKS5 proxy
func fetchViaTor(url: URL, socksPort: UInt16 = 9050) async throws -> Data {
    let config = URLSessionConfiguration.default
    config.connectionProxyDictionary = [
        kCFProxyTypeKey: kCFProxyTypeSOCKS,
        kCFStreamPropertySOCKSProxyHost: "127.0.0.1",
        kCFStreamPropertySOCKSProxyPort: socksPort,
        kCFStreamPropertySOCKSVersion: kCFStreamSocketSOCKSVersion5
    ]
    
    let session = URLSession(configuration: config)
    let (data, response) = try await session.data(from: url)
    
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw URLError(.badServerResponse)
    }
    
    return data
}

// MARK: - Main

@main
struct TorDemo {
    static func main() async {
        print("=== Tor URL Fetch Demo ===")
        print()
        
        // Show version
        if let version = tor_api_get_provider_version() {
            print("📦 Tor version: \(String(cString: version))")
        }
        print()
        
        // Start Tor
        let tor = TorRunner()
        let socksPort: UInt16 = 19050 // Use non-standard port to avoid conflicts
        
        do {
            try await tor.start(socksPort: socksPort)
            
            // Wait for bootstrap
            print("⏳ Waiting for Tor to bootstrap (this may take 1-2 minutes)...")
            let bootstrapped = await tor.waitForBootstrap(socksPort: socksPort, timeout: .seconds(120))
            
            guard bootstrapped else {
                print("❌ Tor failed to bootstrap within timeout")
                return
            }
            
            print("✅ Tor bootstrapped successfully!")
            print()
            
            // Fetch clearnet URL via Tor
            let testURL = URL(string: "https://check.torproject.org/api/ip")!
            print("🌐 Fetching \(testURL) via Tor...")
            
            let data = try await fetchViaTor(url: testURL, socksPort: socksPort)
            
            if let json = String(data: data, encoding: .utf8) {
                print("📥 Response: \(json)")
                
                // Parse and verify
                if json.contains("\"IsTor\":true") || json.contains("\"IsTor\": true") {
                    print()
                    print("🎉 SUCCESS: Traffic is routing through Tor!")
                } else {
                    print()
                    print("⚠️  Response received but may not be through Tor")
                }
            }
            
            print()
            
            // Test .onion hidden service (Tor Project's official onion)
            let onionURL = URL(string: "http://2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion/")!
            print("🧅 Fetching \(onionURL) (hidden service)...")
            
            do {
                let onionData = try await fetchViaTor(url: onionURL, socksPort: socksPort)
                if let html = String(data: onionData, encoding: .utf8) {
                    // Just check we got some HTML back
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
            
        } catch {
            print("❌ Error: \(error)")
        }
        
        print()
        print("=== Demo complete ===")
    }
}
