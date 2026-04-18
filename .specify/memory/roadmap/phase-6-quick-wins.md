# Phase 6: Quick Wins

**Status**: 🟡 Partial (1 of 4 — Bootstrap Events ~80% done)  
**Priority**: Medium  
**Last Updated**: 2026-04-17  
**Depends On**: Phase 5.1 (typed `CircuitStatus` / `StreamStatus` enums; reshaped `TorConfiguration`)

---

## Objective

Deliver a cluster of small, high-leverage features that materially improve daily use of swift-tor without introducing new protocol surface: DNS resolution through Tor, richer bootstrap observability, bandwidth metrics, and SOCKS circuit isolation.

---

## Features

| Feature | Purpose & User Value | Success Metrics | Dependencies | Status |
|---------|----------------------|-----------------|--------------|--------|
| **Bootstrap Events** (🟡 residual) | **Core path already ships**: `TorEvent.bootstrap(progress, tag, summary)` at `Sources/Tor/TorEvent.swift:43`, `BootstrapStatus` struct + parser at `Sources/Tor/Control/ControlProtocolParser.swift:150-208`, `getBootstrapStatus()` at `Sources/Tor/Control/TorControlClient.swift:161`, broadcast in `Sources/Tor/TorClient.swift:251-256`. **Residual scope**: surface the `warning` and `reason` fields (parsed at `ControlProtocolParser.swift:202-203` but dropped when converting to `TorEvent.bootstrap`). | `TorEvent.bootstrap` gains `warning: String?` and `reason: String?` (additive — existing consumers unaffected). | 5.1 | 🟡 ~80% done |
| **DNS over Tor** | Resolve hostnames through Tor, preventing DNS leaks at the application layer. Exposes Tor's `DNSPort` / `ResolveAddress` control-protocol surface. | `TorConfiguration.dnsPort: PortPolicy` added; `TorControlClient.resolve(_:)` returns resolved IP; documentation explains the difference between SOCKS-over-Tor (circuit-level) and DNS-over-Tor (application-level). | 5.1 (reshaped `TorConfiguration`) | 🔜 Planned |
| **Bandwidth Metrics** | Expose bytes read / written and circuit count via control-protocol `GETINFO`. Lets application developers surface Tor throughput in UI (e.g., menu bar indicator). | `TorControlClient.bandwidth()` → `(read: Int, written: Int)`; `TorControlClient.circuitCount()` → `Int`; typed results (not strings). | 5.1 | 🔜 Planned |
| **Circuit Isolation** | SOCKS port isolation flags (`IsolateDestAddr`, `IsolateDestPort`, `IsolateSOCKSAuth`, `IsolateClientProtocol`, `IsolateClientAddr`, `KeepAliveIsolateSOCKSAuth`). Prevents two application sessions from sharing a circuit when the user wants them isolated. | `TorConfiguration.socksPort` accepts isolation flags; typed enum/OptionSet per `control-spec` §5.3; safe-by-default (some isolation enabled). | 5.1 (reshaped `TorConfiguration`) | 🔜 Planned |

Reference draft APIs: `specs/feature-comparison.md`.

---

## Sequencing

1. **Bootstrap Events residual** (smallest diff; additive to an already-shipping enum case).
2. **Circuit Isolation** (pure `TorConfiguration` extension; no new protocol surface).
3. **Bandwidth Metrics** (simple `GETINFO` wrapping).
4. **DNS over Tor** (largest surface; adds a new config dimension plus a control API).

---

## Phase-Level Metrics

| Metric | Target | Status |
|--------|--------|--------|
| Structured bootstrap events expose WARNING/REASON | Events carry all parsed fields | 🟡 partial |
| DNS resolution via Tor | Resolves hostnames without DNS leak | 🔜 |
| Bandwidth metrics | `read` / `written` / `circuitCount` exposed as typed values | 🔜 |
| Circuit isolation | All 6 documented flags settable in `TorConfiguration` | 🔜 |

---

## References

- Tor control protocol spec: https://spec.torproject.org/control-spec/
- `specs/feature-comparison.md` — draft APIs for each feature.

---

## Risks / Open Questions

- **Ordering vs. 5.1**: circuit isolation and DNS over Tor both depend on a reshaped `TorConfiguration`. If 5.1 slips, this phase slips.
- **Safe defaults for isolation**: constitution Principle II favors safe-by-default; consider enabling `IsolateSOCKSAuth` by default and documenting the trade-off.
- **Bootstrap Events residual is polish, not a greenfield feature** — sequence it small and separate from the larger Quick Wins.

---

## Next `/speckit.specify` Hints

```
/speckit.specify "Feature: Bootstrap Events Residual — WARNING/REASON fields on TorEvent.bootstrap"
/speckit.specify "Feature: Circuit Isolation Flags in TorConfiguration"
/speckit.specify "Feature: Bandwidth Metrics via GETINFO"
/speckit.specify "Feature: DNS over Tor"
```
