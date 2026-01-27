# swift-tor Product Roadmap

**Version**: v1.0.0  
**Last Updated**: 2025-01-26  

---

## Vision & Goals

Provide a Swift package that embeds Tor (`libtor`) with a Swift-concurrency-first API, enabling privacy-preserving network applications on Apple platforms and Linux.

**Target Audience**:
- Privacy-focused application developers
- Bitcoin/Lightning wallet developers (Tor integration)
- Developers building .onion service clients
- Swift developers needing anonymous networking

**Core Value Proposition**:
- Embedded Tor (in-process, no external daemon)
- Swift concurrency integration (async/await)
- Cross-platform support (macOS, iOS, Linux)
- Minimal external dependencies

---

## 🔴 High Priority Items

| Item | Description | Status |
|------|-------------|--------|
| **Linux Basic Support** | Build and test on Linux. Handle platform differences (types, missing functions). | ✅ Complete |
| **Remove libbsd Dependency** | Use `ext/strlcpy.c` and `ext/strlcat.c` from Vendor/tor instead of `-include bsd/string.h`. Cleaner build, fewer dependencies. | 🔜 Planned |
| **iOS Target Refactor** | Create separate `libtor-ios` target excluding hashx JIT (`compiler_a64.c`). Removes need for `__clear_cache` shim. JIT is non-functional on iOS anyway due to code signing. | 🔜 Planned |
| **CI Workflows** | Add GitHub Actions for macOS, iOS, and Linux Docker builds. | ✅ Complete |

---

## Phases Overview

| Phase | Name | Status | File |
|-------|------|--------|------|
| **0** | Foundation | ✅ Complete | — |
| **1** | Linux Basic Support | ✅ Complete | [phase-1-linux-basic.md](roadmap/phase-1-linux-basic.md) |
| **2** | Remove libbsd Dependency | 🔜 Planned | [phase-2-remove-libbsd.md](roadmap/phase-2-remove-libbsd.md) |
| **3** | iOS Target Refactor | 🔜 Planned | — |
| **4** | CI & Quality Gates | ✅ Complete | — |

---

## Product-Level Metrics & Success Criteria

| Metric | Target | Status |
|--------|--------|--------|
| macOS build & test | Pass | ✅ |
| iOS build | Pass | ✅ |
| Linux build & test (with libbsd) | Pass | ✅ |
| Linux build & test (without libbsd) | Pass | 🔜 |
| Platform CI pass rate | 100% across macOS + Linux | 🔜 |

---

## Change Log

| Version | Date | Change Type | Description |
|---------|------|-------------|-------------|
| v1.0.0 | 2025-01-26 | Initial | Initial roadmap with Linux support phases |
| v1.1.0 | 2025-01-26 | Updated | Phase 1 & CI complete; added iOS target refactor phase |
