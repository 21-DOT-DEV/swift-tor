// snippet.hide
import Foundation
import Tor

@main
struct ControlProtocolQuery {
    static func main() async throws {
        try await run()
    }

    static func run() async throws {
// snippet.end

// Demonstrate direct Tor control-protocol access via `TorControlClient`.
// The embedded control socket is pre-authenticated, so the client is
// immediately ready to issue `GETINFO` queries and `SIGNAL` commands.
//
// `newIdentity()` sends `SIGNAL NEWNYM`, asking Tor to build fresh
// circuits — useful to rotate exit nodes between anonymized sessions.
let client = TorClient(configuration: .ephemeral())
try await client.start()
try await client.waitUntilBootstrapped()

let control = try await client.control()

let version = try await control.getInfo("version")
print("tor version: \(version ?? "unknown")")

try await control.newIdentity()
print("requested new circuits")

await client.stop()

// snippet.hide
    }
}
// snippet.end
