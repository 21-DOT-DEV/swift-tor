# Using the Tor Control Protocol

@Metadata {
    @TitleHeading("Explanation")
}

Learn to interact with an embedded Tor instance via ``TorControlClient`` — the typed `async` client that wraps Tor's control protocol (control-spec.txt) for state introspection, configuration mutation, event subscription, signal dispatch, and the v3 onion-service lifecycle.

## Overview

Every running swift-tor instance speaks Tor's control protocol on an embedded, pre-authenticated Unix socket — a byproduct of `tor_main_configuration_setup_control_socket()` being called during ``TorClient/start()``. The protocol is textual, line-based, and documented in the canonical [control-spec.txt](https://spec.torproject.org/control-spec/). swift-tor wraps it twice: ``ControlSocket`` handles POSIX I/O and line framing per control-spec.txt §2; ``TorControlClient`` adds typed commands, authentication, and parsed replies per control-spec.txt §3–§4. Most application code reaches the client via ``TorClient/control()`` and never sees the socket directly.

### What the control protocol is

Per [control-spec.txt §1](https://spec.torproject.org/control-spec/), the control protocol is "a way for other programs to communicate with Tor", asynchronous over a single byte-stream, with each command terminated by `CRLF` and each reply prefixed by a three-digit status code (§2.3). Every Tor verb swift-tor implements maps to a single control-protocol command; every event is a `650`-status async line emitted on the same socket after a `SETEVENTS` subscription.

### Authentication

The first command after socket open is `AUTHENTICATE` (control-spec.txt §3.5). swift-tor's ``TorControlClient/authenticate(password:)`` tries three methods in priority order: **cookie** (if `dataDirectory/control_auth_cookie` exists, the 32-byte cookie is hex-encoded), **password** (if a `password` argument is supplied; requires Tor's `HashedControlPassword`), and **null** (bare `AUTHENTICATE` for sockets configured with no auth). The embedded control socket — created via ``TorControlClient/init(fileDescriptor:preAuthenticated:dataDirectory:)`` with `preAuthenticated: true` — skips authentication entirely because `tor_main_configuration_setup_control_socket()` returns an already-authenticated FD.

### GETINFO

The `GETINFO` command (control-spec.txt §3.9) exposes a tree of read-only keys describing Tor's runtime state. swift-tor ships typed wrappers for the keys it consumes internally — see ``TorControlClient/getBootstrapStatus()`` (which queries `status/bootstrap-phase` and parses the result through ``ControlProtocolParser/parseBootstrapStatus(_:)``) — plus generic dictionary and single-key overloads via ``TorControlClient/getInfo(_:)-([String])`` and ``TorControlClient/getInfo(_:)-(String)`` for everything else. Common keys swift-tor uses internally: `version`, `net/listeners/socks`, `status/bootstrap-phase`. Non-success replies throw ``TorError/controlProtocolError(code:message:)`` carrying the three-digit reply code so callers can branch on Tor's reason.

### SETCONF

``TorControlClient/setConf(_:)`` mutates Tor's runtime configuration (control-spec.txt §3.1). Pass a dictionary mapping torrc option names to optional `String` values; pass `nil` to reset a key to its configured default. Not all torrc options are settable at runtime — Tor rejects immutable options with reply code 553 (`invalid config value`). Consult [`tor.1.txt`](https://man.archlinux.org/man/tor.1) for each option's mutability annotation before composing a mutation.

### SETEVENTS and async streams

The control protocol supports an asynchronous event channel (control-spec.txt §4): after `SETEVENTS`, Tor emits `650`-status lines out of band on the same socket whenever subscribed events occur. swift-tor turns that into a typed `AsyncStream` via ``TorControlClient/subscribe(to:)``. The subscription stays active for the life of the control connection; call ``TorControlClient/subscribe(to:)`` again with an empty set to unsubscribe. Only one subscribe loop should read from a given ``ControlSocket`` at a time — two concurrent readers will interleave and fragment events. The full vocabulary is enumerated in ``TorControlEvent`` (one case per control-spec.txt §4.1 keyword).

### Signals

`SIGNAL` commands (control-spec.txt §3.7) trigger Tor operations that don't fit elsewhere: `RELOAD` (re-read torrc), `SHUTDOWN` (graceful exit), `DUMP` (debug log dump), `DEBUG` (toggle debug logging), `HALT` (immediate exit), `NEWNYM` (rotate to new circuits for new streams), `CLEARDNSCACHE`, `HEARTBEAT`, `ACTIVE`/`DORMANT`. swift-tor exposes the two most common as typed methods (``TorControlClient/newIdentity()`` for `NEWNYM`, ``TorControlClient/shutdown()`` for `SHUTDOWN`) and the full set through the raw ``TorControlClient/signal(_:)`` escape hatch. `NEWNYM` is rate-limited by Tor (default 10 seconds between signals); rapid re-invocation is silently coalesced — watch ``TorLogLevel/notice`` log events for the coalesce notification.

### ADD_ONION and DEL_ONION

Onion services are managed through `ADD_ONION` (control-spec.txt §3.27) and `DEL_ONION` (control-spec.txt §3.38). swift-tor wraps both: ``TorControlClient/addOnion(key:ports:detach:)`` and ``TorControlClient/delOnion(_:)-(String)`` / ``TorControlClient/delOnion(_:)-(OnionService)``. swift-tor supports **v3 only** — the older v2 protocol (RSA-1024) was deprecated in Tor 0.4.6 and removed in 0.4.7.

The `key:` parameter selects between three lifecycles: ``OnionKeySpec/newV3(discardPrivateKey:)`` with `true` generates a fresh key whose private half is **never returned** to the caller (single-session use); ``OnionKeySpec/newV3(discardPrivateKey:)`` with `false` generates a fresh key and returns the private blob in ``OnionService/privateKey``; ``OnionKeySpec/providedV3(_:)`` re-adopts a persisted private key, deriving the same ``OnionService/serviceID`` so the `.onion` address is stable across runs.

The `detach:` parameter controls service lifetime. With the default `false`, the service lives only as long as the control connection — when ``TorClient/stop()`` runs (or the underlying socket closes), Tor removes the service automatically. With `true`, Tor adds the `Detach` flag to the `ADD_ONION` command and the service persists until an explicit `DEL_ONION` call or Tor process exit.

The `ports:` parameter is an array of ``OnionPortMapping``. Virtual ports (what `.onion` clients dial) and target backends (where Tor forwards traffic) are independent — exposing virtual port `443` and forwarding to `127.0.0.1:8080` is normal. Tor does **not** validate the target at registration time; missing backends surface as connection refusals when a remote client dials.

`DEL_ONION` is idempotent in the absence of the service: a second call returns reply code 552, which swift-tor surfaces as ``TorError/invalidServiceID(_:)``. Callers that want to swallow already-deleted services can `try?` the call.

### Error model

swift-tor collapses every control-protocol failure into a ``TorError`` case keyed by the three-digit reply code from control-spec.txt §4.3. Reply codes 250 and 251 indicate success and are not raised. Reply code 451 (resource exhausted) raises ``TorError/resourceExhausted(_:)``. Reply codes 510, 512, 513, 514, 550, 553, 554, and 555 raise ``TorError/controlProtocolError(code:message:)`` with the underlying code preserved. Reply code 515 (bad authentication) raises ``TorError/controlAuthFailed(_:)``. Reply code 552 raises ``TorError/invalidServiceID(_:)`` when emitted by `DEL_ONION` and ``TorError/controlProtocolError(code:message:)`` otherwise. Malformed wire responses (truncated lines, missing status codes) surface as ``TorError/invalidResponse(_:)``.

### Escape hatches

For commands swift-tor has not yet modelled (`HSFETCH`, `MAPADDRESS`, `DROPTIMEOUTS`, etc.), use ``TorControlClient/sendRaw(_:)``. The method does no success/failure classification — callers must inspect the returned string and react. Prefer the typed methods (``TorControlClient/getInfo(_:)-([String])``, ``TorControlClient/setConf(_:)``, ``TorControlClient/signal(_:)``) whenever one exists.

## See Also

- ``TorControlClient``
- ``ControlSocket``
- ``ControlReply``
- ``ControlProtocolParser``
- ``OnionService``
- ``OnionKeySpec``
- ``OnionPortMapping``
- [control-spec.txt](https://spec.torproject.org/control-spec/)
- [Tor Onion Services specification (rend-spec-v3)](https://spec.torproject.org/rend-spec/)
