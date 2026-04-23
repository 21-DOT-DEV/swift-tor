# Production Considerations

@Metadata {
    @TitleHeading("Explanation")
}

Pre-1.0 caveats, threat-model boundaries, key-handling discipline, log hygiene, bootstrap performance, concurrency model, and platform exclusions for swift-tor in production deployments.

## Overview

> Warning: Tor cannot "fix" unsafe application behaviour. Review the [Tor Project guidance](https://support.torproject.org/) on staying anonymous. Avoid logging sensitive information (credentials, onion private keys, control-port passwords). Consider your threat model — Tor integration is only one part of privacy and security.

This article is the single source of truth for swift-tor's production caveats. Inline `> Warning:` callouts on individual symbols point here for the full discussion.

### Pre-1.0 API stability

swift-tor is pre-1.0 — major-version zero per [SemVer 2.0 §4](https://semver.org/#spec-item-4): "Major version zero (`0.y.z`) is for initial development. Anything MAY change at any time. The public API SHOULD NOT be considered stable." Until the first 1.0 release, every minor and patch version is allowed to introduce breaking changes; pin a specific version with `exact:` in `Package.swift` to avoid surprise migrations:

```swift
.package(url: "https://github.com/21-DOT-DEV/swift-tor.git", exact: "0.1.0")
```

Until the first tagged release lands, track `branch: "main"` and audit the diff between commits before bumping.

### Anonymity vs integration

swift-tor exposes the embedded Tor process; it does not enforce application-level anonymity. Common pitfalls outside Tor's control include: leaking your application's IP via DNS resolved outside the SOCKS5 proxy, mixing identified and anonymous traffic on the same circuit, using long-lived persistent identifiers (logins, cookies) that correlate sessions, sending identifying metadata in HTTP headers (`User-Agent`, `Cookie`, `Referer`), and clock skew that fingerprints the host. The Tor Project documents these in detail at [support.torproject.org](https://support.torproject.org/); read the relevant sections before publishing a production deployment.

### Threat model

swift-tor inherits Tor's threat model: a global passive adversary can in principle correlate traffic timing across circuit endpoints (control-spec.txt does not claim resistance to global adversaries). Onion services additionally rely on the v3 Ed25519 keypair remaining secret (rend-spec-v3 §2.5); leakage of the private key permits an attacker to impersonate the service. Application-level threats — XSS, SSRF, deserialization vulnerabilities — are entirely outside swift-tor's scope and are not mitigated by routing traffic through Tor.

### Private key handling

Onion-service private keys returned via ``OnionService/privateKey`` are secret material. Treat them as credentials at every step:

**Persist via the platform credential store.** Use [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain_services) on Apple platforms with `kSecAttrAccessible` set to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` or stricter. On Linux, use `libsecret`, the GNOME Keyring, or KWallet; do not write keys to disk in plaintext.

**Never log, diff, or serialise keys to stdout.** Audit every `print`, `os_log`, structured-logging call, and crash-report dump path before shipping. Remember that onion-service private keys are written to the Tor data directory by Tor itself in some configurations — review ``TorConfiguration/dataDirectory`` placement and OS-level file permissions.

**Use ``OnionKeySpec/newV3(discardPrivateKey:)`` with `true` whenever re-adoption is unnecessary.** The less key material leaves Tor, the smaller the attack surface. Single-session services should always discard the key.

**Rotate keys after security incidents.** Generate a fresh key with ``OnionKeySpec/newV3(discardPrivateKey:)`` and discard the old stored blob. The old `.onion` address is gone — but so is the compromised key, and the new address can be rolled out via your existing distribution channel.

### Log discipline

swift-tor surfaces Tor's log stream through ``TorEvent/log(level:message:)`` events. Filter at the subscription level via ``TorControlClient/subscribe(to:)`` rather than at the UI layer to avoid pushing high-volume `DEBUG` / `INFO` events across the control socket unnecessarily. In production deployments:

Set ``TorConfiguration`` to log at ``TorLogLevel/notice`` or higher; `DEBUG` and `INFO` produce thousands of lines per minute. Never include onion-service private keys, control-port passwords, or SOCKS5 authentication metadata in any log sink. Treat the entire control protocol transcript as sensitive — `GETINFO` responses can reveal local listener addresses, circuit identifiers, and other operational metadata.

### Bootstrap performance

Cold bootstraps on a public guard typically complete in 30–60 seconds: Tor downloads the network consensus, fetches a microdescriptor sample, and authenticates a relay path. Warm bootstraps with a reused ``TorConfiguration/cacheDirectory`` cut that to roughly 5–10 seconds because the consensus and microdescriptor cache survive between runs. Choose ``TorClient/waitUntilBootstrapped(timeout:)`` timeouts with appropriate headroom — 120 seconds is the default for cold-boot scenarios.

`TorConfiguration/cacheDirectory` should be a stable per-application path inside the application's sandbox container. The data directory itself can remain ephemeral (UUID-suffixed temp); only the cache needs to persist.

### Concurrency model

``TorClient`` is an `actor` — every public method is `async` and serialised by Swift's actor executor. Internally, swift-tor runs Tor's `tor_run_main()` on a dedicated `Thread` rather than on a Swift Concurrency cooperative thread, because `tor_run_main()` is a long-running blocking C function and would otherwise stall the global executor. Cross-thread bootstrapping happens through a `CheckedContinuation` in ``TorClient/start()``.

Lower-level concurrency primitives — ``ControlSocket`` and ``TorControlClient`` — use `Mutex<State>` from the [`Synchronization` module (SE-0410)](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0410-atomics.md) for compiler-verified `Sendable` conformance without `@unchecked Sendable` escape hatches. The iOS 18 / macOS 15 platform floor is required by `Mutex<T>`'s availability.

### Platform exclusions

swift-tor supports macOS 15+, iOS 18+, and Linux (Ubuntu 22.04+). It does **not** support tvOS, watchOS, or visionOS. Tor's codebase relies on UNIX process primitives — `fork(2)`, `execve(2)`, `daemon(3)`, `setuid(2)` — that Apple prohibits on those platforms; the restrictions are enforced at App Store review and would cause runtime crashes if shipped. Do not add `.tvOS`, `.watchOS`, or `.visionOS` to `Package.swift` `platforms:`, and do not enable those slices in CI build matrices.

### Reporting vulnerabilities

Security vulnerabilities in swift-tor are coordinated through the [SECURITY.md](https://github.com/21-DOT-DEV/swift-tor/blob/main/SECURITY.md) policy in the repository root. For the broader 21-DOT-DEV organisation policy, see the [organization Security Policy](https://github.com/21-DOT-DEV/.github/blob/main/SECURITY.md). Do not report vulnerabilities through public GitHub issues.

For Tor-protocol vulnerabilities (specification flaws, cryptographic issues in tor-spec.txt or rend-spec-v3.txt), report to the upstream [Tor Project Security Team](https://support.torproject.org/misc/bug-or-feedback/) — they handle coordinated disclosure across the Tor ecosystem.

## See Also

- <doc:GettingStarted>
- <doc:ControlProtocolGuide>
- ``TorClient``
- ``TorConfiguration``
- ``OnionService``
- ``TorError``
- [Tor Project — Frequently Asked Questions](https://support.torproject.org/)
- [SECURITY.md](https://github.com/21-DOT-DEV/swift-tor/blob/main/SECURITY.md)
