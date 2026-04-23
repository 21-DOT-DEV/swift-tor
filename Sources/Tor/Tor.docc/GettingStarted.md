# Getting Started

A task-oriented walkthrough of swift-tor: start a Tor instance, wait for bootstrap, route traffic, and shut down cleanly.

## Overview

This guide walks through the overwhelmingly common swift-tor flow: construct a ``TorClient``, start the embedded Tor process, wait for it to bootstrap to the Tor network, use it for SOCKS5 proxy traffic or direct control-protocol commands, then stop it cleanly. Every step is `Sendable`, every wait is bounded, and no state is left on disk when the session ends (provided you start from ``TorConfiguration/ephemeral(cacheDirectory:)``).

### Configure and start

`TorConfiguration` is a value type; start from one of the convenience factories and override the fields you care about. The ephemeral factory produces a self-cleaning configuration \u2014 UUID-suffixed temp directory for Tor state, `ownsDataDirectory: true` so the directory disappears on ``TorClient/stop()``.

@Snippet(path: "swift-tor/Snippets/BasicTorClient")

`start()` resolves as soon as the embedded control socket is reachable, which happens before Tor has completed bootstrap. Pair it with ``TorClient/waitUntilBootstrapped(timeout:)`` to block until Tor can actually carry traffic. Cold bootstraps complete in 30\u201360 seconds on a public guard; supplying ``TorConfiguration/cacheDirectory`` across runs drops that to 5\u201310 seconds.

### Use the SOCKS5 proxy

Once ``TorClient/socksEndpoint`` is non-`nil`, hand it to any SOCKS5-aware client. On Apple platforms, swift-tor offers a one-step `URLSession` helper that bridges through CFNetwork's proxy-dictionary API:

@Snippet(path: "swift-tor/Snippets/URLSessionViaTor")

On Linux, CFNetwork is unavailable so the helper is not compiled. Integrate your own SOCKS5 client or use the endpoint with a curl subprocess, [`swift-openssl`](https://github.com/21-DOT-DEV/swift-openssl)-based TLS client, or any third-party Swift HTTP client that accepts a proxy endpoint.

### Publish an onion service

Swift-tor exposes the full v3 onion-service lifecycle through ``TorControlClient/addOnion(key:ports:detach:)``. The snippet below creates a fresh single-session service that forwards port 80 on the `.onion` address to `127.0.0.1:8080`, discards the private key (no later re-adoption is possible), and returns as soon as the service is published.

@Snippet(path: "swift-tor/Snippets/EphemeralOnionService")

For long-lived services, supply an ``OnionKeySpec/providedV3(_:)`` with a persisted private key, or pass `detach: true` so the service survives this control connection. See <doc:OnionServices> for the full lifecycle and security guidance around key persistence.

### Observe state

Every ``TorClient`` instance exposes a fresh ``TorSession/events`` `AsyncStream` at the actor boundary. Subscribe in a background task to observe bootstrap progress, state changes, and any raw control-protocol events you've subscribed to via ``TorControlClient/subscribe(to:)``:

```swift
let task = Task {
    for await event in await client.events {
        switch event {
        case .bootstrap(let progress, _, let summary):
            print("bootstrap \(progress)%: \(summary)")
        case .stateChanged(let state):
            print("state \u2192 \(state)")
        default:
            break
        }
    }
}
```

The stream completes exactly once, when ``TorClient/stop()`` tears down the session. Cancel the task if you want to unsubscribe earlier.

### Drive the control protocol directly

For advanced workflows, go through ``TorClient/control()`` to reach the typed control client. Issue `GETINFO` queries, `SETCONF` mutations, or raw `SIGNAL` commands:

@Snippet(path: "swift-tor/Snippets/ControlProtocolQuery")

See <doc:ControlProtocol> for the full control-protocol vocabulary and error-model guidance.

### Shut down cleanly

``TorClient/stop()`` is best-effort and non-throwing. It sends `SIGNAL SHUTDOWN`, waits up to 10 seconds for the Tor thread to exit, then force-cancels if Tor is still hung. If `configuration.ownsDataDirectory` was `true`, the data directory is removed on the way out. After `stop()`, the same `TorClient` can be started again with a fresh data directory.

### Next steps

Read <doc:ControlProtocol> for deep dives on `GETINFO`, `SETEVENTS`, and raw async-event handling; <doc:OnionServices> for v3 key lifecycle, re-adoption, and private-key persistence; ``TorError`` for every failure mode swift-tor surfaces; and ``TorState`` for the legal lifecycle transition graph.

## See Also

- <doc:ControlProtocol>
- <doc:OnionServices>
- ``TorClient``
- ``TorConfiguration``
