# Phase 3.5: Binary Size Optimization

**Status**: 🔜 Planned  
**Priority**: Medium  
**Last Updated**: 2026-04-17  
**Depends On**: Phase 2 (Remove libbsd) — baseline clean build graph

---

## Objective

Reduce the compiled size of the `libtor` target by disabling Tor modules that are unused for client-only deployments and making GeoIP data loading optional.

---

## Background

Tor's source tree includes server-oriented modules (directory authority, directory cache, relay) and optional data files (GeoIP databases, ~2 MB) that most swift-tor consumers don't need. The current build includes them all.

`Package.swift:3-8` documents LTO and dead-strip options as "Future" (they require `unsafeFlags` which prevents use as a dependency — app-only).

---

## Features

| Feature | Purpose & User Value | Success Metrics | Dependencies | Notes |
|---------|----------------------|-----------------|--------------|-------|
| **GeoIP Optional** | Make GeoIP data loading opt-in. Saves ~2 MB in the shipped binary for consumers who don't need geo-based circuit selection. | `libtor` release binary ~2 MB smaller with GeoIP disabled; API flag in `TorConfiguration` to enable; docs explain trade-off (no country-based exit selection). | — | GeoIP files live in `Sources/libtor/src/config/`. |
| **Client-Only Modules** | Exclude `dirauth`, `dircache`, and `relay` source modules from the build. These are only needed by directory authorities, caches, or relay operators — not client-only consumers. | `libtor` release binary significantly smaller; `swift build` and `swift test` still pass on all platforms; client functionality unaffected. | Coordinated `subtree.yaml` exclusion + `orconfig.h` `#undef` of related `HAVE_MODULE_*` flags. | Requires excluding entire feature directories from extraction, not just stubbing functions. Landing this cleanly depends on how `subtree.yaml` handles directory-level excludes. |

---

## Sequencing

1. **GeoIP Optional first** (lower risk, self-contained) — proves the optional-feature pattern.
2. **Client-Only Modules second** (requires coordinated subtree + config changes) — apply lessons from GeoIP work.

LTO and dead-strip remain out of scope (already documented in `Package.swift` as app-only options due to `unsafeFlags` incompatibility with SPM dependency use).

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| `libtor` release binary size | ≥30% reduction with client-only + GeoIP-off |
| CI pass rate across platforms | 100% (macOS, iOS, Linux) |
| API flag coverage | `TorConfiguration.disableGeoIP: Bool` default `false` (backward compatible) |

---

## Risks / Open Questions

- **Module disabling complexity**: Tor's modules are intertwined. Some symbols may be referenced from always-on code paths and require stubbing rather than exclusion.
- **Subtree extraction coordination**: `swift-plugin-subtree` may need configuration changes to exclude directories during extraction. Verify tooling supports this.
- **Testing coverage**: removing server-oriented modules means we lose any tests that exercise them; audit before removal.
