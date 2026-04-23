# Getting Started with swift-tor

@Metadata {
    @TitleHeading("Article")
}

A task-oriented walkthrough of swift-tor: add the dependency, start an embedded Tor instance, route SOCKS5 traffic, publish a v3 onion service, and shut down cleanly.

## Overview

This article assumes Swift 6.1, macOS 15+ or iOS 18+, and a project that uses the Swift Package Manager. Linux (Ubuntu 22.04+) is supported with the same source. Each section pairs a short prose explanation with a runnable `Snippets/` example you can `swift run` from the package root.

### Adding swift-tor to your project

Add `swift-tor` as a package dependency. Until the project cuts a tagged release, track `branch: "main"` so consumers stay aligned with the audited HEAD.

```swift
.package(url: "https://github.com/21-DOT-DEV/swift-tor.git", branch: "main")
```

Then list `Tor` (the idiomatic Swift API) or `libtor` (raw C bindings) in the `dependencies:` of any target that needs them. Most callers only need `Tor`.

### Starting Tor and waiting for bootstrap

``TorClient`` is an `actor` that owns one embedded Tor process. Construct it from a ``TorConfiguration``, call ``TorClient/start()`` to spin up the embedded `tor_run_main()` thread, then ``TorClient/waitUntilBootstrapped(timeout:)`` to block until Tor reports 100% bootstrap progress.

The Tor Project documents bootstrap as the multi-phase handshake during which Tor downloads the network consensus and authenticates a relay path; see the [Tor Project bootstrap reference](https://support.torproject.org/connecting/connecting-2/) for the user-facing explanation of the phases.

@Snippet(path: "swift-tor/Snippets/BasicClient")

### Faster bootstraps with `cacheDirectory`

Cold bootstraps on a public guard typically complete in 30–60 seconds. Persisting Tor's consensus and microdescriptor cache across runs cuts subsequent bootstraps to roughly 5–10 seconds. Pass a stable directory path to ``TorConfiguration/ephemeral(cacheDirectory:)`` and reuse it on every launch; the data directory itself stays ephemeral.

@Snippet(path: "swift-tor/Snippets/CachedBootstrap")

### Creating an ephemeral onion service

Onion services let a program expose a TCP endpoint reachable only through the Tor network at a `.onion` address, with built-in Ed25519 authentication of the service's public key (rend-spec-v3 §2.5). swift-tor publishes services through ``TorControlClient/addOnion(key:ports:detach:)``, which serialises Tor's [`ADD_ONION` command (control-spec.txt §3.27)](https://spec.torproject.org/control-spec/) and parses the reply.

The snippet below creates a single-session service that forwards `.onion:80` to `127.0.0.1:8080`, **discards** the private key (so the service cannot be re-published after the control connection closes), and prints the resulting `.onion` address.

> Warning: When `discardPrivateKey: false`, the returned ``OnionService/privateKey`` is secret material. Never log it, commit it to source control, or write it to stdout. Persist it via Apple Keychain (Keychain Services) or a comparable credential store on Linux. See <doc:ProductionConsiderations> for the full key-handling guidance.

@Snippet(path: "swift-tor/Snippets/EphemeralOnion")

### Apple-only: routing URLSession via Tor

On Apple platforms, swift-tor offers a one-step `URLSession` helper that bridges through CFNetwork's proxy-dictionary API. The helper is guarded by `#if canImport(CFNetwork)` because the underlying [`URLSessionConfiguration.connectionProxyDictionary`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/1411499-connectionproxydictionary) and `kCFStreamPropertySOCKSProxy*` keys are unavailable on Linux. On Linux, integrate any third-party SOCKS5-aware HTTP client against ``TorClient/socksEndpoint``.

@Snippet(path: "swift-tor/Snippets/URLSessionOverTor")

### Next steps

For control-protocol depth (`GETINFO`, `SETCONF`, `SETEVENTS`, raw `SIGNAL`, the full ADD_ONION/DEL_ONION lifecycle), read <doc:ControlProtocolGuide>. For pre-1.0 caveats, threat-model boundaries, and key-handling discipline, read <doc:ProductionConsiderations>.

## See Also

- <doc:ControlProtocolGuide>
- <doc:ProductionConsiderations>
- ``TorClient``
- ``TorConfiguration``
