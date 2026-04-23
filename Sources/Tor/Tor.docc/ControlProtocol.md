# Using the Tor Control Protocol

Typed `async` access to Tor's control protocol (control-spec.txt) for state introspection, configuration mutation, event subscription, and signal dispatch.

## Overview

Every running swift-tor instance speaks Tor's control protocol on an embedded, pre-authenticated Unix socket \u2014 a byproduct of `tor_main_configuration_setup_control_socket()` being called during ``TorClient/start()``. The protocol is textual, line-based, and documented in the canonical [control-spec.txt](https://spec.torproject.org/control-spec/). Swift-tor wraps it twice:

1. **Low-level**: ``ControlSocket`` handles POSIX I/O and line framing (control-spec.txt \u00a72).
2. **High-level**: ``TorControlClient`` adds typed commands, authentication, and parsed replies (control-spec.txt \u00a73\u2013\u00a74).

Most application code reaches the client via ``TorClient/control()`` and never sees the socket directly.

### GETINFO

The `GETINFO` command (control-spec.txt \u00a73.9) exposes a tree of read-only keys describing Tor's runtime state. Swift-tor ships typed wrappers for the keys it consumes internally, plus a generic dictionary overload for everything else.

```swift
let control = try await client.control()

// Typed path for bootstrap progress
if let status = try await control.getBootstrapStatus() {
    print("bootstrap: \(status.progress)% \(status.tag)")
}

// Generic path for any GETINFO key
let version = try await control.getInfo("version")
print("tor version: \(version ?? "unknown")")

let listeners = try await control.getInfo(["net/listeners/socks", "net/listeners/control"])
for (key, value) in listeners {
    print("\(key) = \(value)")
}
```

Common keys swift-tor uses: `version`, `net/listeners/socks`, `status/bootstrap-phase`. Non-success replies throw ``TorError/controlProtocolError(code:message:)`` carrying the three-digit reply code so callers can branch on Tor's reason.

### SETCONF

``TorControlClient/setConf(_:)`` mutates Tor's runtime configuration (control-spec.txt \u00a73.1). Pass a dictionary of torrc option names to optional values \u2014 pass `nil` to reset a key to its configured default.

```swift
try await control.setConf([
    "CircuitBuildTimeout": "60",
    "NumEntryGuards": "3",
    "Log": nil,   // reset to default
])
```

Not all torrc options are settable at runtime; Tor rejects immutable options with reply code 553 (`invalid config value`). Consult [`tor.1.txt`](https://man.archlinux.org/man/tor.1) for each option's mutability annotation before composing a mutation.

### SETEVENTS and async streams

The control protocol supports an asynchronous event channel (control-spec.txt \u00a74): after `SETEVENTS`, Tor emits `650`-status lines out of band on the same socket whenever subscribed events occur. Swift-tor turns that into a typed `AsyncStream` via ``TorControlClient/subscribe(to:)``.

```swift
let stream = try await control.subscribe(to: [.circuitStatus, .bandwidthUsed])
for await event in stream {
    switch event.event {
    case .circuitStatus:
        print("circuit event: \(event.data)")
    case .bandwidthUsed:
        print("bw: \(event.attributes)")
    default:
        break
    }
}
```

The subscription stays active for the life of the control connection. Call ``TorControlClient/subscribe(to:)`` again with an empty set to unsubscribe. Only one subscribe loop should read from a given ``ControlSocket`` at a time \u2014 two concurrent readers will interleave and fragment events.

### Signals

`SIGNAL` commands (control-spec.txt \u00a73.7) trigger Tor operations that don't fit elsewhere. Swift-tor exposes two common signals as typed methods and the rest through the raw ``TorControlClient/signal(_:)`` escape hatch:

```swift
// Rotate circuits for new streams
try await control.newIdentity()   // sends SIGNAL NEWNYM

// Graceful exit (usually wrapped by TorClient.stop())
try await control.shutdown()      // sends SIGNAL SHUTDOWN

// Everything else
try await control.signal("RELOAD")
try await control.signal("HEARTBEAT")
```

`NEWNYM` is rate-limited by Tor (default 10 seconds between signals). Rapid re-invocation is silently coalesced; watch ``TorLogLevel/notice`` log events for the coalesce notification.

### Error model

Swift-tor collapses every control-protocol failure into a ``TorError`` case:

| Reply code | Meaning | ``TorError`` case |
|---|---|---|
| 250/251 | Success | (not raised) |
| 451 | Resource exhausted | ``TorError/resourceExhausted(_:)`` |
| 510 | Unrecognized command | ``TorError/controlProtocolError(code:message:)`` |
| 512 | Syntax error in argument | ``TorError/controlProtocolError(code:message:)`` |
| 513 | Unrecognized argument | ``TorError/controlProtocolError(code:message:)`` |
| 514 | Authentication required | ``TorError/controlProtocolError(code:message:)`` |
| 515 | Bad authentication | ``TorError/controlAuthFailed(_:)`` |
| 550 | Unspecified Tor error | ``TorError/controlProtocolError(code:message:)`` |
| 552 | Unrecognized entity | ``TorError/invalidServiceID(_:)`` (for `DEL_ONION`) / ``TorError/controlProtocolError(code:message:)`` |
| 553 | Invalid config value | ``TorError/controlProtocolError(code:message:)`` |
| 554 | Invalid descriptor | ``TorError/controlProtocolError(code:message:)`` |
| 555 | Unmanaged entity | ``TorError/controlProtocolError(code:message:)`` |

Malformed wire responses (e.g. a truncated line, missing status code) surface as ``TorError/invalidResponse(_:)``.

### Escape hatches

For commands swift-tor has not yet modelled (`HSFETCH`, `MAPADDRESS`, `DROPTIMEOUTS`), use ``TorControlClient/sendRaw(_:)``. The method does no success/failure classification \u2014 callers must inspect the returned string and react.

```swift
let raw = try await control.sendRaw("GETCONF MaxClientCircuitsPending")
print(raw)   // "MaxClientCircuitsPending=32"
```

Prefer the typed methods (``TorControlClient/getInfo(_:)-([String])``, ``TorControlClient/setConf(_:)``, ``TorControlClient/signal(_:)``) whenever one exists.

## See Also

- ``TorControlClient``
- ``ControlSocket``
- ``ControlReply``
- ``ControlProtocolParser``
- [control-spec.txt](https://spec.torproject.org/control-spec/)
