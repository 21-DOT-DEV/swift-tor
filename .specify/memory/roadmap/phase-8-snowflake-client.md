# Phase 8: Snowflake Client

**Status**: 🔜 Planned  
**Priority**: High (censorship-circumvention core value prop)  
**Last Updated**: 2026-04-17  
**Depends On**: Phase 5.1 (typed `TorConfiguration`), Phase 7 (PT Configuration API — unmanaged PT pattern)

---

## Objective

Native Swift WebRTC Snowflake transport for users in heavily censored regions. iOS-compatible via the unmanaged PT pattern established in Phase 7.

See `specs/relay-snowflake-investigation.md` for the full implementation plan, rendezvous-broker strategy, and WebRTC library selection.

---

## Features

| Feature | Purpose & User Value | Success Metrics | Dependencies | Notes |
|---------|----------------------|-----------------|--------------|-------|
| **Snowflake Client** | Connect to Tor via WebRTC data channels through volunteer proxies, bypassing deep packet inspection and IP-level blocks. iOS-compatible (the headline platform where obfs4's managed PT is impossible). | Successful bootstrap on macOS, Linux, iOS via Snowflake; `SnowflakeClient` actor API per `specs/feature-comparison.md:77-99`; integration tests env-gated. | 5.1, 7 | Large feature (L, 4–6 weeks). Implementation plan documented in `specs/relay-snowflake-investigation.md`. |

---

## Design Note

The existing draft `SnowflakeClient` API in `specs/feature-comparison.md:77-99` uses an inner `State: Sendable` enum (`idle / connecting / connected(peerCount:) / failed`). Once Phase 5.3 (typestate) lands, **this design should be revisited**: `SnowflakeClient` is another linear-lifecycle resource that would benefit from typestate + noncopyable handle, matching the `TorHandle` pattern. Decide whether to reshape at spec time or ship as-drafted first and refactor later.

---

## Sequencing

See `specs/relay-snowflake-investigation.md` §Implementation Plan. The phase breaks naturally into:

1. WebRTC library integration (select + vendor or SPM dep).
2. Snowflake broker HTTP client (rendezvous protocol).
3. Local SOCKS5 server that tunnels through the WebRTC data channel.
4. `TorConfiguration.withSnowflake(...)` integration.
5. `TorClient.startWithSnowflake(...)` convenience (or `TorHandle.startWithSnowflake(...)` if 5.3 has landed).
6. Integration tests against public Snowflake broker (env-gated).

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| Snowflake bootstrap on macOS / Linux / iOS | Pass |
| Domain fronting support | Optional `frontDomain` honored |
| STUN server configurability | Multiple servers supported; sensible default |
| Integration test pass rate | Env-gated; scheduled cadence per Constitution VI |

---

## References

- `specs/relay-snowflake-investigation.md` — full plan
- `specs/feature-comparison.md:36-119` — draft `SnowflakeConfiguration` and `SnowflakeClient` API
- Snowflake upstream: https://snowflake.torproject.org/

---

## Risks / Open Questions

- **WebRTC library choice**: swift-webrtc is Apple-biased; non-Apple-platform WebRTC has historically required Google's reference library (C++). Selection needs explicit decision before implementation.
- **Broker availability**: production depends on `snowflake-broker.torproject.net` (or operator-supplied domain-fronted alternative).
- **Binary size impact**: WebRTC adds meaningful megabytes to the shipped library. May interact with Phase 3.5 Binary Size Optimization goals.
- **iOS background limits**: Snowflake connections are long-lived; iOS's background-execution constraints may affect stability. Document expected use-case patterns (foreground bootstrap only, or with background-mode entitlement).
- **Revisit typestate** (above) once 5.3 ships.
- **Spec-level governance**: pluggable-transport surface per Constitution §Compliance Review Triggers — each Snowflake sub-feature needs its own `spec.md`.

---

## Next `/speckit.specify` Hints

```
/speckit.specify "Feature: WebRTC Library Selection + Integration"
/speckit.specify "Feature: Snowflake Broker HTTP Client"
/speckit.specify "Feature: Snowflake Local SOCKS5 Tunnel"
/speckit.specify "Feature: TorConfiguration.withSnowflake(...) Integration"
```
