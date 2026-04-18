# Phase 9: Advanced Features

**Status**: 🔜 Planned  
**Priority**: Mixed (per-feature)  
**Last Updated**: 2026-04-17  
**Depends On**: Phase 5.1 (reshaped `TorConfiguration`), optionally Phase 7 (PT Configuration API for bridge mode)

---

## Objective

Deliver a grab bag of advanced-operator and optional-enhancement features: hidden-service client authorization, non-exit relay and bridge modes (macOS/Linux), optional compression (ZSTD, LZMA), and relay-throughput optimization (KIST) on Linux.

These are independent features; this phase is a bucket rather than a cohesive deliverable.

---

## Features

| Feature | Purpose & User Value | Success Metrics | Dependencies | Platform | Notes |
|---------|----------------------|-----------------|--------------|----------|-------|
| **HSv3 Client Auth** | Client-side authorization for private onion services (`rend-spec-v3` §G). Callers can connect to private HS operators that require pre-shared client keys. | `TorConfiguration.clientAuth: [OnionClientAuth]`; typed `OnionClientAuth(serviceID: ServiceID, privateKey: Data)`; Keychain storage recommended on Apple platforms. | 5.1 (reshaped config), 5.2 (tagged `ServiceID`) | macOS, Linux, iOS | — |
| **Relay Mode** | Run as a non-exit relay on macOS or Linux. Contributes bandwidth to the Tor network. Requires public IP + reachable ORPort. | `TorConfiguration.relay(orPort: Int, nickname: String, contactInfo: String)` factory; reachable-port self-test via control protocol. | 5.1 | macOS, Linux (iOS ❌ per Constitution VI) | Spec-level governance triggered per Constitution §Compliance Review Triggers. |
| **Bridge Mode** | Run as a bridge relay on macOS or Linux. Helps censored users connect. | `TorConfiguration.bridge(orPort: Int, obfs4Port: Int?)` factory; bridge-line emission helper. | Phase 7 (PT config for obfs4 bridge support) | macOS, Linux (iOS ❌) | — |
| **ZSTD Compression** | Optional zstd compression for directory data. Reduces bandwidth during consensus download. | `libzstd` linked; Tor's `HAVE_ZSTD` flag enabled; measurable reduction in bootstrap bytes transferred. | — | macOS, Linux, iOS | New runtime dependency: requires Constitution Principle I allowlist amendment (MINOR bump). |
| **LZMA Compression** | Optional lzma compression for directory data. | `liblzma` linked; Tor's `HAVE_LZMA` flag enabled. | — | macOS, Linux, iOS | New runtime dependency: requires Constitution Principle I allowlist amendment (MINOR bump). |
| **KIST Support** | Kernel-Informed Socket Transport — Linux relay throughput optimization. | KIST scheduler enabled on Linux relay builds; measurable throughput improvement in relay-mode self-test. | Phase 9 Relay Mode | Linux only | — |

---

## Sequencing

Per-feature; can land in any order independent of each other. Suggested ordering by value/cost:

1. **HSv3 Client Auth** (high value, low complexity).
2. **Relay Mode** (high value for network; requires operator discipline).
3. **Bridge Mode** (depends on Phase 7 obfs4).
4. **ZSTD / LZMA** (both require allowlist amendments — may batch).
5. **KIST** (depends on Relay Mode).

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| HSv3 client-auth connection | Successfully connect to a private onion service with pre-shared auth |
| Relay self-test (macOS/Linux) | ORPort reachable; bandwidth published |
| Bridge self-test | Operator can generate a bridge line consumable by a client |
| Compression flags | ZSTD + LZMA both togglable; negotiation succeeds with network |
| KIST | Linux-only; throughput delta measurable on relay |

---

## Runtime-Dependency Amendments Required

- **ZSTD Compression** → add `libzstd` (or a Swift package wrapping it) to Constitution Principle I allowlist.
- **LZMA Compression** → add `liblzma` (or a Swift package wrapping it) to Constitution Principle I allowlist.

Both require a formal constitution amendment (MINOR bump) documented in the Sync Impact Report header of `constitution.md`.

---

## References

- `rend-spec-v3` §G — HSv3 client authorization
- `dir-spec` — directory compression
- KIST: https://freehaven.net/anonbib/cache/kist:sec14.pdf

---

## Risks / Open Questions

- **Relay operator expertise**: running a relay is a commitment. Documentation must clearly explain reachability requirements, port-forwarding, contact-info publication, and abuse-handling expectations.
- **Exit relay explicitly out of scope**: see `roadmap.md` Deferred table. Do not confuse non-exit relay with exit relay.
- **Compression allowlist decisions** (above): adopt now or later? If later, this phase slips until amendments land.
- **iOS platform exclusions**: Relay/Bridge/KIST are macOS+Linux only per Constitution VI; document clearly in the phase and in the API docs.
- **Spec-level governance**: Relay/Bridge introduction triggers per-feature spec.md per Constitution §Compliance Review Triggers.

---

## Next `/speckit.specify` Hints

```
/speckit.specify "Feature: HSv3 Client Authorization for Private Onion Services"
/speckit.specify "Feature: Non-Exit Relay Mode (macOS/Linux)"
/speckit.specify "Feature: Bridge Mode with obfs4 (macOS/Linux)"
/speckit.specify "Feature: ZSTD Compression (+ Constitution Allowlist Amendment)"
/speckit.specify "Feature: LZMA Compression (+ Constitution Allowlist Amendment)"
/speckit.specify "Feature: KIST Relay Throughput Optimization (Linux)"
```
