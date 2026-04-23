// snippet.hide
import Foundation
import Tor

@main
struct BasicClient {
    static func main() async throws {
        try await run()
    }

    static func run() async throws {
// snippet.end

// Boot an embedded Tor instance with an ephemeral data directory,
// wait for the Tor network bootstrap to complete, and print the SOCKS5
// endpoint the caller can route traffic through.
let client = TorClient(configuration: .ephemeral())

try await client.start()
try await client.waitUntilBootstrapped()

if let socks = await client.socksEndpoint {
    print("SOCKS5 reachable at \(socks.host):\(socks.port)")
}

await client.stop()

// snippet.hide
    }
}
// snippet.end
