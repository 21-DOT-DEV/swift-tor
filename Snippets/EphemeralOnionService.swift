// snippet.hide
import Foundation
import Tor

@main
struct EphemeralOnionService {
    static func main() async throws {
        try await run()
    }

    static func run() async throws {
// snippet.end

// Publish an ephemeral v3 onion service that forwards inbound port 80
// traffic on the .onion address to a local HTTP server on 127.0.0.1:8080.
// The key is discarded, so this service cannot be re-published after the
// control connection closes — ideal for single-session use.
let client = TorClient(configuration: .ephemeral())
try await client.start()
try await client.waitUntilBootstrapped()

let control = try await client.control()
let service = try await control.addOnion(
    key: .newV3(discardPrivateKey: true),
    ports: [.toLocalPort(80, localPort: 8080)]
)

print("Service URL: \(service.serviceID).onion")

await client.stop()

// snippet.hide
    }
}
// snippet.end
