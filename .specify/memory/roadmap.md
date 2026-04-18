# swift-tor Product Roadmap

**Version**: v1.6.0  
**Last Updated**: 2026-04-17

---

## Vision & Goals

Provide a Swift package that embeds Tor (`libtor`) with a Swift-concurrency-first API, enabling privacy-preserving network applications on Apple platforms and Linux.

**Target Audience**:
- Privacy-focused application developers
- Bitcoin/Lightning wallet developers (Tor integration)
- Developers building .onion service clients
- Swift developers needing anonymous networking
- Users in censored regions (Snowflake client)
- Relay/bridge operators (macOS/Linux)

**Core Value Proposition**:
- Embedded Tor (in-process, no external daemon)
- Swift concurrency integration (async/await)
- Cross-platform support (macOS, iOS, Linux)
- Minimal external dependencies
- Censorship circumvention (Snowflake client)
- Network contribution (relay/bridge on macOS/Linux)

---

## Phases Overview

**Status legend**: ✅ Complete · 🟡 Partial · 🔜 Planned · ❓ Unscoped · ⚪ Deferred

Canonical detail for each phase lives in `.specify/memory/roadmap/phase-*.md`. This index intentionally stays slim.

| Phase | Name | Status | Detail File |
|-------|------|--------|-------------|
| **0** | Foundation | ✅ Complete | _historical_ |
| **1** | Linux Basic Support | ✅ Complete | [`phase-1-linux-basic.md`](./roadmap/phase-1-linux-basic.md) |
| **2** | Remove libbsd Dependency | ✅ Complete | [`phase-2-remove-libbsd.md`](./roadmap/phase-2-remove-libbsd.md) |
| **3** | iOS Target Refactor | ❓ Unscoped | [`phase-3-ios-target-refactor.md`](./roadmap/phase-3-ios-target-refactor.md) |
| **3.5** | Binary Size Optimization | 🔜 Planned | [`phase-3.5-binary-size.md`](./roadmap/phase-3.5-binary-size.md) |
| **4** | CI & Quality Gates | ✅ Complete | [`phase-4-ci-quality-gates.md`](./roadmap/phase-4-ci-quality-gates.md) |
| **5.1** | API Type-Safety — Foundation | 🔜 Planned | [`phase-5.1-api-foundation.md`](./roadmap/phase-5.1-api-foundation.md) |
| **5.2** | API Type-Safety — Identifier Hygiene | 🔜 Planned | [`phase-5.2-api-identifier-hygiene.md`](./roadmap/phase-5.2-api-identifier-hygiene.md) |
| **5.3** | API Type-Safety — Typestate + DI | 🔜 Planned | [`phase-5.3-api-typestate-di.md`](./roadmap/phase-5.3-api-typestate-di.md) |
| **6** | Quick Wins | 🟡 Partial (1 of 4 — Bootstrap Events ~80%) | [`phase-6-quick-wins.md`](./roadmap/phase-6-quick-wins.md) |
| **7** | Core Censorship | 🔜 Planned | [`phase-7-core-censorship.md`](./roadmap/phase-7-core-censorship.md) |
| **8** | Snowflake Client | 🔜 Planned | [`phase-8-snowflake-client.md`](./roadmap/phase-8-snowflake-client.md) |
| **9** | Advanced Features | 🔜 Planned | [`phase-9-advanced-features.md`](./roadmap/phase-9-advanced-features.md) |

**High-level dependency view**:

- Phases 1 → 2 → 4 form the completed platform/CI baseline.
- Phase 5.1 unlocks 5.2 and 5.3 (typed foundations before typestate).
- Phases 6 / 7 / 8 / 9 ride on 5.1's reshaped `TorConfiguration` and typed enums; doing them before 5.1 would incur rework.
- Phase 3 (iOS Target Refactor) is orthogonal but unscoped; resolve before scheduling.

---

## Completion Audit (verified 2026-04-17)

Index-level ✅ markers were re-verified against the actual codebase. Evidence trail:

| Phase | Evidence |
|-------|----------|
| **1** ✅ | `Dockerfile:1-19` (swift:6.1-jammy build+test); `Sources/Tor/Control/ControlSocket.swift:13-19` (platform guards); `Package.swift:57` (`_GNU_SOURCE` Linux-only) |
| **2** ✅ | `Sources/libtor/src/ext/strlcpy.c` + `strlcat.c` present; `Package.swift:37-38` excludes them (inline-included); `orconfig.h:546-560` Linux conditionals; no `libbsd` linker or unsafeFlags; `Dockerfile` has no `libbsd-dev` |
| **4** ✅ | `.github/workflows/apple-builds.yml:10-29` (macOS + iOS); `.github/workflows/docker-builds.yml:9-16` (Linux Docker) |
| **3** ❓ | Baseline iOS support ships (`Package.swift:16` `.iOS(.v16)`; `apple-builds.yml:18-29` passing iOS job; `Sources/Tor/Apple/URLSession+Tor.swift`; `README.md:17`). What "refactor" is pending is undocumented. |
| **6** 🟡 | Bootstrap Events core already ships: `TorEvent.swift:43`, `ControlProtocolParser.swift:150,188` (`BootstrapStatus` + parser), `TorControlClient.swift:161` (`getBootstrapStatus()`), `TorClient.swift:251-256` (broadcast). Residual: surface `warning`/`reason` on the event boundary. Other three Quick Wins (DNS, Bandwidth, Circuit Isolation) correctly 🔜. |

---

## ⚪ Deferred / Out of Scope

| Item | Description | Rationale |
|------|-------------|-----------|
| **Exit Relay** | Full exit relay configuration | Requires operator expertise; out of scope for initial implementation |
| **Server Transport Plugins** | Bridge-side PT support (obfs4, etc.) | macOS/Linux only; low priority |
| **Snowflake Proxy** | Volunteer proxy node | Background limits on iOS; use official tools |

---

## Platform Feature Matrix

| Feature | macOS | Linux | iOS |
|---------|:-----:|:-----:|:---:|
| Tor Client | ✅ | ✅ | ✅ |
| Onion Services | ✅ | ✅ | ✅ |
| Bootstrap Events (core) | ✅ | ✅ | ✅ |
| Bootstrap Events (warnings/reasons) | 🟡 | 🟡 | 🟡 |
| DNS over Tor | 🔜 | 🔜 | 🔜 |
| Bandwidth Metrics | 🔜 | 🔜 | 🔜 |
| Circuit Isolation | 🔜 | 🔜 | 🔜 |
| obfs4 Client | 🔜 | 🔜 | 🔜 |
| Snowflake Client | 🔜 | 🔜 | 🔜 |
| HSv3 Client Auth | 🔜 | 🔜 | 🔜 |
| Non-Exit Relay | 🔜 | 🔜 | ❌ |
| Bridge | 🔜 | 🔜 | ❌ |
| Exit Relay | ⚪ | ⚪ | ❌ |

---

## Product-Level Metrics & Success Criteria

| Metric | Target | Status |
|--------|--------|--------|
| macOS build & test | Pass in CI | ✅ |
| iOS build | Pass in CI | ✅ |
| Linux build & test (without libbsd) | Pass in CI | ✅ |
| Platform CI pass rate | 100% across macOS + iOS + Linux | ✅ |
| Public API eliminates runtime lifecycle guards | ≥90% eliminated after 5.3 | 🔜 |
| DNS resolution via Tor | Resolves hostnames without DNS leak | 🔜 |
| Structured bootstrap events expose WARNING/REASON | Events carry all parsed fields | � |
| obfs4 bootstrap | Connect via obfs4 bridge | 🔜 |
| Snowflake client bootstrap | Connect via Snowflake on all platforms | 🔜 |
| Relay self-test | ORPort reachable on macOS/Linux | 🔜 |

---

## Global Risks & Assumptions

- **Pre-1.0 breaking changes**: Constitution (`§ Versioning`) allows breaking changes without deprecation. Phase 5.x intentionally takes them while they're cheap.
- **Typestate + actor coexistence**: `~Copyable` types cannot conform to protocols or be members of actors in Swift 6.1. Phase 5.3 resolves this with a `TorHandle` value façade over an internal `TorRuntime` actor.
- **`@_spi(Testing)` stability**: underscore attribute is not part of the formal language, but stable since Swift 5.3 and used in Apple's own libraries. Re-evaluate splitting into a `TorTestKit` module at 1.0.
- **Upstream Tor cadence**: Best-effort tracking per Constitution Principle VI; security advisories may force interleaved Vendor syncs.
- **Platform scope is normative**: tvOS/watchOS/visionOS excluded per Constitution Principle VI; reopening requires amendment.

---

## Change Log

| Version | Date | Change Type | Description |
|---------|------|-------------|-------------|
| v1.0.0 | 2025-01-26 | Initial | Initial roadmap with Linux support phases |
| v1.1.0 | 2025-01-26 | Updated | Phase 1 & CI complete; added iOS target refactor phase |
| v1.2.0 | 2026-01-27 | Updated | Added Snowflake client and Relay/Bridge mode based on investigation |
| v1.3.0 | 2026-01-27 | Restructured | Reorganized into 8 phases with feature comparison; Circuit Isolation moved to Quick Wins |
| v1.4.0 | 2026-01-30 | Updated | Phase 2 complete; added Phase 3.5 Binary Size Optimization (GeoIP Optional, Client-Only Modules) |
| v1.5.0 | 2026-02-02 | Updated | Added ZSTD/LZMA compression and KIST support to Phase 8 |
| v1.6.0 | 2026-04-17 | Restructured | Inserted API Type-Safety theme as three sub-phases — 5.1 Foundation, 5.2 Identifier Hygiene, 5.3 Typestate + DI (TorHandle<State>, TorEngine closure DI, TorSession protocol removal); renumbered downstream phases (Quick Wins 5→6, Censorship 6→7, Snowflake 7→8, Advanced 8→9); brought every phase into forge.roadmap spec compliance with dedicated detail files; marked Phases 1/2/4 ✅ Complete (verified against codebase Round 3); expanded status palette to include 🟡 Partial and ❓ Unscoped; reclassified Phase 3 ❓ Unscoped and Phase 6 🟡 Partial (Bootstrap Events ~80% done). |
