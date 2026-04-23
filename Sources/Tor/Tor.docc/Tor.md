# ``Tor``

@Metadata {
    @TitleHeading("Framework")
}

Swift-native, `Sendable`-first API for embedding the Tor anonymity network in macOS, iOS, and Linux applications.

## Overview

`Tor` is the idiomatic Swift face of this package. It wraps a vendored build of [Tor 0.4.8.21](https://gitlab.torproject.org/tpo/core/tor) behind Swift 6.1 structured concurrency so you can write `async`/`await` code against an embedded Tor instance on macOS 15+, iOS 18+, and Linux (Ubuntu 22.04+). The package depends on [`swift-event`](https://github.com/21-DOT-DEV/swift-event) (libevent) and [`swift-openssl`](https://github.com/21-DOT-DEV/swift-openssl) (libcrypto/libssl) for its native stack, and surfaces a small, typed API with no raw `OpaquePointer` leakage.

Direct-use capabilities shipping today span five areas.

**Actor-isolated Tor driver** — construct, start, wait for bootstrap, inspect, stop. See ``TorClient``.

**Typed control protocol** — `GETINFO`, `SETCONF`, `SETEVENTS`, `ADD_ONION`, `SIGNAL` through an `async` client. See ``TorControlClient``.

**v3 onion-service lifecycle** — register, re-adopt, and delete ephemeral `.onion` services. See ``OnionService``, ``OnionKeySpec``, ``OnionPortMapping``.

**Event stream** — back-pressure-aware `AsyncStream` of bootstrap progress, circuit/stream status, and log messages. See ``TorEvent``, ``TorSession``.

**Apple-only URLSession wiring** — one-step `URLSession` over SOCKS5 proxy. See `URLSessionConfiguration.configuredForTor(socksEndpoint:)` and ``TorClient/makeURLSession(ephemeral:)``.

```swift
import Tor

let client = TorClient(configuration: .ephemeral())
try await client.start()
try await client.waitUntilBootstrapped()
print("SOCKS5 reachable at \(await client.socksEndpoint!)")
await client.stop()
```

### Concurrency and security

Every type in the public surface is `Sendable` — ``TorClient`` is an `actor`, ``TorControlClient`` and ``ControlSocket`` use `Mutex<State>` from the [`Synchronization` module (SE-0410)](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0410-atomics.md), and value types carry all their state structurally. No `@unchecked Sendable` escape hatches remain in the call graph, which is why the platform floor is iOS 18 / macOS 15.

Onion-service private keys are surfaced through ``OnionService/privateKey`` as plain `String?` blobs. Treat them as credentials: persist only via Keychain on Apple platforms (or an equivalent credential store on Linux), and never log them.

### API positioning

`Tor` is a thin, `tor_api`-direct `async`/`await` wrapper. It is not a replacement for [Arti](https://gitlab.torproject.org/tpo/core/arti) — if you need Rust's memory-safety guarantees end-to-end, or anonymity features Arti has already shipped and the C Tor has not, reach for Arti. Reach for `Tor` when you want the stability of the reference C implementation, direct access to the full control-protocol vocabulary, or tight integration with Swift's structured concurrency.

## Topics

### Essentials

- <doc:GettingStarted>
- ``TorClient``
- ``TorSession``
- ``TorConfiguration``

### Control protocol

- <doc:ControlProtocol>
- ``TorControlClient``
- ``ControlSocket``
- ``ControlReply``
- ``ControlProtocolParser``

### Onion services

- <doc:OnionServices>
- ``OnionService``
- ``OnionKeySpec``
- ``OnionPortMapping``
- ``OnionPortTarget``

### Events and state

- ``TorEvent``
- ``TorState``
- ``TorLogLevel``
- ``TorControlEvent``
- ``TorControlEventMessage``
- ``BootstrapStatus``

### Values

- ``HostPort``
- ``PortPolicy``
- ``AddOnionResponse``

### Errors

- ``TorError``

### Apple-only

- ``TorClient/makeURLSession(ephemeral:)``
