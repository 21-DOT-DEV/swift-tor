# swift-tor Product Roadmap

**Version**: v1.3.0  
**Last Updated**: 2026-01-27  

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

| Phase | Name | Status | Est. Duration |
|-------|------|--------|---------------|
| **0** | Foundation | ✅ Complete | — |
| **1** | Linux Basic Support | ✅ Complete | — |
| **2** | Remove libbsd Dependency | ✅ Complete | — |
| **3** | iOS Target Refactor | 🔜 Planned | 1 week |
| **3.5** | Binary Size Optimization | 🔜 Planned | 1 week |
| **4** | CI & Quality Gates | ✅ Complete | — |
| **5** | Quick Wins | 🔜 Planned | 1-2 weeks |
| **6** | Core Censorship | 🔜 Planned | 3-4 weeks |
| **7** | Snowflake Client | 🔜 Planned | 4-6 weeks |
| **8** | Advanced Features | 🔜 Planned | 2-4 weeks |

---

## Phase 3.5: Binary Size Optimization (1 week)

| Feature | Description | Effort |
|---------|-------------|--------|
| **GeoIP Optional** | Make GeoIP data loading optional (~2MB savings when disabled). Add config flag. | S |
| **Client-Only Modules** | Properly disable dirauth/dircache/relay modules by excluding source files in subtree.yaml. Requires coordinated orconfig.h + extraction changes. | M |

**Notes**:
- LTO and strip options documented in Package.swift (require unsafeFlags, app-only)
- Module disabling requires excluding entire feature directories, not just stubs

---

## Phase 5: Quick Wins (1-2 weeks)

| Feature | Description | Effort |
|---------|-------------|--------|
| **DNS over Tor** | Resolve hostnames through Tor via control protocol. Prevents DNS leaks. | S |
| **Bootstrap Events** | Structured bootstrap progress with phase tags, summaries, warnings. | S |
| **Bandwidth Metrics** | Expose bytes read/written, circuit count via control protocol. | S |
| **Circuit Isolation** | SOCKS port isolation flags (`IsolateDestAddr`, `IsolateSOCKSAuth`, etc.). | S |

**Reference**: [feature-comparison.md](../../specs/feature-comparison.md) for draft APIs

---

## Phase 6: Core Censorship (3-4 weeks)

| Feature | Description | Effort |
|---------|-------------|--------|
| **PT Configuration API** | First-class `TorConfiguration` support for pluggable transports and bridges. | S |
| **obfs4 Client** | obfs4 transport via managed PT (macOS/Linux) or unmanaged PT (iOS). | M |

**Reference**: [feature-comparison.md](../../specs/feature-comparison.md) for draft APIs

---

## Phase 7: Snowflake Client (4-6 weeks)

| Feature | Description | Effort |
|---------|-------------|--------|
| **Snowflake Client** | Native WebRTC Snowflake transport. iOS-compatible via unmanaged PT. | L |

**Reference**: [relay-snowflake-investigation.md](../../specs/relay-snowflake-investigation.md) for full implementation plan

---

## Phase 8: Advanced Features (2-4 weeks)

| Feature | Description | Effort |
|---------|-------------|--------|
| **HSv3 Client Auth** | Client-side authorization for private onion services. | M |
| **Relay Mode** | Run as non-exit relay (macOS/Linux). Requires public IP, port forwarding. | S |
| **Bridge Mode** | Run as bridge relay (macOS/Linux). Helps censored users connect. | S |

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
| DNS over Tor | 🔜 | 🔜 | 🔜 |
| Bootstrap Events | 🔜 | 🔜 | 🔜 |
| Bandwidth Metrics | 🔜 | 🔜 | 🔜 |
| Circuit Isolation | 🔜 | 🔜 | 🔜 |
| obfs4 Client | 🔜 | 🔜 | 🔜 |
| Snowflake Client | 🔜 | 🔜 | 🔜 |
| HSv3 Client Auth | 🔜 | 🔜 | 🔜 |
| Non-Exit Relay | 🔜 | 🔜 | ❌ |
| Bridge | 🔜 | 🔜 | ❌ |
| Exit Relay | ⏸️ | ⏸️ | ❌ |

---

## Product-Level Metrics & Success Criteria

| Metric | Target | Status |
|--------|--------|--------|
| macOS build & test | Pass | ✅ |
| iOS build | Pass | ✅ |
| Linux build & test (with libbsd) | Pass | ✅ |
| Linux build & test (without libbsd) | Pass | ✅ |
| Platform CI pass rate | 100% across macOS + Linux | 🔜 |
| DNS resolution via Tor | Resolves hostnames without DNS leak | 🔜 |
| Bootstrap events streaming | Structured events emitted | 🔜 |
| obfs4 bootstrap | Connect via obfs4 bridge | 🔜 |
| Snowflake client bootstrap | Connect via Snowflake on all platforms | 🔜 |
| Relay self-test | ORPort reachable on macOS/Linux | 🔜 |

---

## Change Log

| Version | Date | Change Type | Description |
|---------|------|-------------|-------------|
| v1.0.0 | 2025-01-26 | Initial | Initial roadmap with Linux support phases |
| v1.1.0 | 2025-01-26 | Updated | Phase 1 & CI complete; added iOS target refactor phase |
| v1.2.0 | 2026-01-27 | Updated | Added Snowflake client and Relay/Bridge mode based on investigation |
| v1.3.0 | 2026-01-27 | Restructured | Reorganized into 8 phases with feature comparison; Circuit Isolation moved to Quick Wins |
| v1.4.0 | 2026-01-30 | Updated | Phase 2 complete; added Phase 3.5 Binary Size Optimization (GeoIP Optional, Client-Only Modules) |
