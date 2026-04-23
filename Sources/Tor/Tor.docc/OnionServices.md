# Publishing Onion Services

v3 onion-service registration, key lifecycle, and security practices for swift-tor.

## Overview

Tor onion services (formerly "hidden services") let a program expose a TCP endpoint reachable only through the Tor network at a `.onion` address, with built-in authentication of the service's public key. Swift-tor supports **v3 only** \u2014 the older v2 protocol (RSA-1024) was deprecated in Tor 0.4.6 and removed in 0.4.7 \u2014 and gives you the full v3 lifecycle through ``TorControlClient/addOnion(key:ports:detach:)`` / ``TorControlClient/delOnion(_:)-(String)``.

The v3 key format is Ed25519 (rend-spec-v3 \u00a72.5); the service ID is a 56-character base32 encoding of the public key hash (rend-spec-v3 \u00a76). Swift-tor's ``OnionService`` carries both, plus a creation timestamp and the optional private-key blob.

### Three key strategies

#### 1. Ephemeral, discarded key

The simplest form: Tor generates a fresh key pair, publishes the service, and **never hands the private key back**. The service is reachable as long as the control connection stays open (or, with `detach: true`, as long as Tor stays running) and cannot be re-adopted after it disappears. Ideal for single-session use: file transfers, command-line demos, request/response handshakes.

```swift
let service = try await control.addOnion(
    key: .newV3(discardPrivateKey: true),
    ports: [.toLocalPort(80, localPort: 8080)]
)
print("reachable at \(service.onionAddress)")
// service.privateKey == nil \u2014 cannot be re-adopted
```

#### 2. Ephemeral, keep the key

Tor generates a fresh key pair and returns the private-key blob. Callers can persist it in Keychain (Apple) or an equivalent credential store (Linux) and later re-adopt the service through ``OnionKeySpec/providedV3(_:)``.

```swift
let service = try await control.addOnion(
    key: .newV3(discardPrivateKey: false),
    ports: [.toLocalPort(80, localPort: 8080)]
)

guard let key = service.privateKey else {
    throw MyError.expectedKeyblob   // should not happen when discardPrivateKey: false
}
// Persist `key` to Keychain under a stable identifier.
// The next run can re-adopt via OnionKeySpec.providedV3(storedKey).
```

#### 3. Re-adopt an existing key

Load the persisted key and re-publish the same service identity. Tor validates the key and re-derives the same ``OnionService/serviceID`` \u2014 the `.onion` address is stable across re-adoptions.

```swift
let storedKey: String = /* fetch from Keychain */ 
let service = try await control.addOnion(
    key: .providedV3(storedKey),
    ports: [.toLocalPort(80, localPort: 8080)]
)
// service.serviceID is the same as the original run
```

Tor refuses to publish two services with the same key on the same control connection: re-adopting a key that's already active throws ``TorError/serviceAlreadyExists(_:)``. Delete the existing service first (``TorControlClient/delOnion(_:)-(String)``) or discard the stored key and generate a new one.

### Detach semantics

`ADD_ONION` couples service lifetime to the control connection by default (control-spec.txt \u00a73.27):

- **`detach: false`** (default) \u2014 the service lives as long as **this** control connection. When ``TorClient/stop()`` runs, or the underlying socket closes, Tor removes the service automatically.
- **`detach: true`** \u2014 Tor adds the `Detach` flag to the `ADD_ONION` command. The service persists until an explicit ``TorControlClient/delOnion(_:)-(String)`` call or Tor process exit, even if this control connection closes.

Pick `detach: true` when building long-lived services outside your app's lifetime; pick the default for scoped services you want cleaned up automatically.

### Port mappings

An onion service can expose many virtual ports, each forwarding to a different backend. Build an array of ``OnionPortMapping`` values:

```swift
let service = try await control.addOnion(
    key: .newV3(discardPrivateKey: true),
    ports: [
        .toLocalPort(80, localPort: 8080),                          // HTTP
        .toLocalPort(443, localPort: 8443),                         // HTTPS
        OnionPortMapping(virtualPort: 22,
                         target: .unix(path: "/var/run/ssh.sock")), // SSH over Unix socket
    ]
)
```

Virtual ports live in the `.onion` namespace (what remote clients dial); targets live in the local kernel's address space. They are independent and do not need to match \u2014 exposing `443` on the `.onion` and forwarding to `127.0.0.1:8080` is perfectly normal.

Tor does **not** validate the target at registration time. Missing backends surface as connection refusals when a client dials the `.onion` address.

### Deleting services

Two convenience overloads remove a published service:

```swift
try await control.delOnion(service)              // by OnionService value
try await control.delOnion(service.serviceID)    // by raw service ID
```

Both are idempotent in the absence of the service \u2014 the second call returns reply code 552, which swift-tor surfaces as ``TorError/invalidServiceID(_:)``. Callers that want to ignore already-deleted services can `try?` the call.

### Security practices

Four rules cover most key-management incidents.

**Treat ``OnionService/privateKey`` as a credential.** Never log it. Never commit it to source control. Persist only via Keychain on Apple platforms or an equivalent secure credential store on Linux.

**Use `discardPrivateKey: true` when you don't need re-adoption.** The less key material leaves Tor, the smaller the attack surface.

**Rotate private keys on security incidents.** Generate a fresh key with ``OnionKeySpec/newV3(discardPrivateKey:)`` and discard the old stored blob. The old `.onion` address is gone but so is the compromised key.

**Keep the onion address secret if your threat model requires it.** The v3 protocol authenticates the service's public key but does not hide the `.onion` address from anyone who learns it. Share only through out-of-band channels with intended clients.

## See Also

- ``OnionService``
- ``OnionKeySpec``
- ``OnionPortMapping``
- ``OnionPortTarget``
- ``TorControlClient/addOnion(key:ports:detach:)``
- ``TorControlClient/delOnion(_:)-(String)``
- [Tor Onion Services specification (rend-spec-v3)](https://spec.torproject.org/rend-spec/)
