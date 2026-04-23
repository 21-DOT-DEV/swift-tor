// snippet.hide
import Foundation
import Tor

@main
struct URLSessionOverTor {
    static func main() async throws {
        try await run()
    }

    static func run() async throws {
#if canImport(CFNetwork)
// snippet.end

// Route an `URLSession` through a running Tor instance's SOCKS5 proxy
// using the Apple-only `makeURLSession()` helper. The returned session
// inherits all defaults of `URLSessionConfiguration.default` but adds a
// `connectionProxyDictionary` pointing at Tor's local SOCKS endpoint.
//
// This snippet is guarded by `#if canImport(CFNetwork)` because the
// helper relies on CFNetwork proxy dictionary keys, which are not
// available on Linux.
let client = TorClient(configuration: .ephemeral())
try await client.start()
try await client.waitUntilBootstrapped()

let session = try await client.makeURLSession(ephemeral: true)
let (data, _) = try await session.data(from: URL(string: "https://check.torproject.org/api/ip")!)
print(String(decoding: data, as: UTF8.self))

await client.stop()

// snippet.hide
#endif
    }
}
// snippet.end
