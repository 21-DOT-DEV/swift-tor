// snippet.hide
import Foundation
import Tor

@main
struct CachedBootstrap {
    static func main() async throws {
        try await run()
    }

    static func run() async throws {
// snippet.end

// Reuse a persistent cache directory across runs so the second and
// subsequent boots reuse Tor's consensus + microdescriptor cache and
// reach 100% bootstrap in 5–10 seconds instead of the cold-boot 30–60
// seconds. The data directory itself is still ephemeral (UUID-suffixed
// temp); only `cacheDirectory` persists between runs.
let cache = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("swift-tor-cache", isDirectory: true)

let client = TorClient(configuration: .ephemeral(cacheDirectory: cache.path))

try await client.start()
try await client.waitUntilBootstrapped()

print("bootstrap complete; cache reused from \(cache.path)")

await client.stop()

// snippet.hide
    }
}
// snippet.end
