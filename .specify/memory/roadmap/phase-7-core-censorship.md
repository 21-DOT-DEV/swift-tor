# Phase 7: Core Censorship

**Status**: 🔜 Planned  
**Priority**: High  
**Last Updated**: 2026-04-17  
**Depends On**: Phase 5.1 (reshaped `TorConfiguration`); recommended after Phase 6

---

## Objective

Provide first-class APIs for connecting through pluggable transports (PT) and bridges, with obfs4 as the reference implementation. This is the minimum-viable censorship-circumvention surface before the larger Snowflake effort (Phase 8).

---

## Features

| Feature | Purpose & User Value | Success Metrics | Dependencies | Notes |
|---------|----------------------|-----------------|--------------|-------|
| **PT Configuration API** | First-class `TorConfiguration` support for pluggable transports and bridges. Typed `BridgeLine`, `ManagedPluggableTransport`, `UnmanagedPluggableTransport` replace stringly-typed `ClientTransportPlugin` config. | `TorConfiguration.bridges: [BridgeLine]`; `TorConfiguration.transport: PluggableTransport?`; docs explain managed vs. unmanaged PT. | 5.1 (reshaped `TorConfiguration`) | Reference draft APIs: `specs/feature-comparison.md`. |
| **obfs4 Client** | obfs4 transport via managed PT on macOS/Linux (spawn `obfs4proxy`) or unmanaged PT on iOS (SOCKS-to-local). The baseline censorship transport; battle-tested. | Successfully bootstrap via obfs4 bridge on all three supported platforms; integration test env-gated per Constitution VI. | PT Configuration API | Platform note: managed PT requires `fork`/`execve`, disabled on iOS per Constitution VI (Apple platform prohibition). iOS uses unmanaged PT pattern. |

---

## Sequencing

1. **PT Configuration API** first (enables obfs4 and future PTs).
2. **obfs4 Client** second (consumes the config API).

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| obfs4 bootstrap | Connect via obfs4 bridge on macOS, Linux, iOS |
| BridgeLine parsing | Matches upstream Tor's bridge-line format |
| PT config API coverage | Supports both managed and unmanaged PT modes |
| Platform compatibility | macOS/Linux: managed + unmanaged; iOS: unmanaged only |

---

## References

- Tor specification: `pt-spec` (https://spec.torproject.org/pt-spec/)
- `specs/feature-comparison.md` — draft APIs for PT Configuration and obfs4 Client
- obfs4 upstream: https://gitlab.com/yawning/obfs4

---

## Risks / Open Questions

- **iOS managed-PT impossibility**: Apple prohibits `fork`/`execve` for App Store apps. Document unambiguously that iOS requires unmanaged PT and provide a clear integration example (caller runs the transport in-process; Tor connects via local SOCKS).
- **obfs4proxy binary distribution**: managed PT requires shipping the binary somehow. Options: system-provided (brew/apt), bundled in app, or caller-provided. Decide before implementation.
- **Spec-level governance** (Constitution §Compliance Review Triggers): introduction of pluggable-transport surface requires per-feature `spec.md` — not just one phase-level spec.

---

## Next `/speckit.specify` Hints

```
/speckit.specify "Feature: PT Configuration API (BridgeLine, PluggableTransport)"
/speckit.specify "Feature: obfs4 Client — Managed PT (macOS/Linux)"
/speckit.specify "Feature: obfs4 Client — Unmanaged PT (iOS)"
```
