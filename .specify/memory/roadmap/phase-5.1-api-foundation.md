# Phase 5.1: API Type-Safety — Foundation

**Status**: 🔜 Planned  
**Priority**: High  
**Last Updated**: 2026-04-17  
**Depends On**: — (self-contained; unblocks 5.2 and 5.3)

---

## Objective

Ship the safe, mostly-additive type-safety improvements to the swift-tor public API. Lay groundwork for 5.2 (identifier hygiene) and 5.3 (typestate + closure DI) by introducing typed enums, validation infrastructure, and extension-split source files — without taking large breaking changes yet.

---

## Constitutional Alignment

- **Principle IV** — API Design & Safe Defaults: typed enums and validation make safe the default; raw strings become escape hatches, not the primary interface.
- **Principle V** — Spec-First & TDD: each feature below gets its own `spec.md` + failing tests before implementation.

---

## Features

| Feature | Purpose & User Value | Success Metrics | Dependencies | Notes |
|---------|----------------------|-----------------|--------------|-------|
| **`TorControlClient` extension split** | Break the 360-line file into focused extension files (`+GetInfo`, `+SetConf`, `+Events`, `+OnionServices`, `+Signals`, `+Raw`). Smaller reviews, clearer structure. | Each split file ≤ ~150 LOC; no public API shape changes; tests unchanged. | — | Reference pattern: `swift-bitcoin`'s `Sources/Bitcoin/Config/BitcoinConfig+*.swift` split. |
| **`TorConfiguration` extension split** | Core struct + `+Presets.swift` + `+Validation.swift`. Mirrors the `BitcoinConfig` layout. | Core file shrinks; presets and validation have dedicated homes; no functional change. | — | — |
| **`TorConfiguration.validate()`** | Surface configuration conflicts before `TorClient.start()` wastes a bootstrap. Return typed warnings and throw typed errors. | `throws(TorConfigError) -> [TorConfigWarning]`; bridged in `TorClient.start()`; covers all known conflict cases (e.g., cookie-auth + password; `cookieAuthentication = true` without `controlPassword`). | — | Pattern source: `swift-bitcoin` `BitcoinConfig+Validation.swift:17-92`. |
| **`TorControlAuth` enum** | Replace `cookieAuthentication: Bool` + `controlPassword: String?` with a single enum (`.none / .cookie / .hashedPassword(String)`). Eliminates the ambiguous "both set" state. | Invalid combinations become unrepresentable at the type level; call sites migrated; `TorConfiguration.validate()` no longer needs the cross-field check. | — | Breaking change: public `TorConfiguration` initializer signature changes. |
| **`TorError: LocalizedError` + typed throws on control APIs** | Enable SwiftUI/`NSError` bridging; adopt Swift 6 typed throws (`throws(TorError)`) on at least three control methods. | Conformance added; 3+ methods migrated; no string-concat error paths. | Swift 6.1 | `TorError` already conforms to `CustomStringConvertible`; adding `LocalizedError` is one line + `errorDescription`. |
| **`TorSignal` enum** | Replace `signal(_ signal: String)` in `TorControlClient` with a closed enum (`.shutdown / .reload / .hup / .newnym / .cleardnscache / .heartbeat / .dump / .debug / .active / .dormant / .custom(String)`). | Invalid signal strings unrepresentable; `.custom` escape hatch preserved for forward compatibility with new Tor versions. | — | Closed set derived from Tor's `control-spec` §3.7. |
| **Typed `CircuitStatus` / `StreamStatus`** | Replace `status: String` in `TorEvent.circuit` / `.stream` with enums per `control-spec` §4.1.1 / §4.1.2. | All documented status values modeled; `.unknown(String)` escape hatch for unrecognized tokens; downstream consumers benefit from exhaustive switches. | — | Parser in `ControlProtocolParser.swift` needs matching conversion layer. |
| **`TorConfiguration` presets** | Static factories: `.clientOnly()`, `.torBrowser()`, `.onionServiceHost(...)`. | ≥ 3 user-facing presets; each with doc comments explaining the configuration trade-offs. | — | Pattern source: `swift-bitcoin` `BitcoinConfig+Presets.swift`. |

---

## Sequencing

Internal to this sub-phase (8 features, each with its own spec):

1. Extension splits first (`TorControlClient` + `TorConfiguration`) — prep structure without behavior change.
2. Typed enums (`TorSignal`, `CircuitStatus`, `StreamStatus`, `TorControlAuth`).
3. Validation infrastructure (`TorConfigError`, `TorConfigWarning`, `validate()`).
4. Error bridging (`LocalizedError` + typed throws).
5. Presets last (build on the reshaped `TorConfiguration`).

Each lands as an independent PR; phase is complete when all 8 ship.

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| Public API shape | typed enums replace ≥ 4 `String` parameters |
| Configuration errors | ≥ 100% of documented conflict cases caught by `validate()` |
| File sizes | No source file > 200 LOC in the split targets |
| Breaking changes | Minimized; only `TorControlAuth` and `signal(_:)` rename are material |
| Tests | 0 regressions; new coverage for every typed enum |

---

## References

- `swift-bitcoin` `Sources/Bitcoin/Config/` — `BitcoinConfig.swift`, `BitcoinConfig+Validation.swift`, `BitcoinConfig+Presets.swift`, `ValueTypes.swift`
- Tor control protocol spec: https://spec.torproject.org/control-spec/
- Swift Evolution: SE-0413 (typed throws)

---

## Risks / Open Questions

- **Extension-split merge conflicts**: mechanical but touches every extension consumer. Sequence early to reduce downstream rebase churn.
- **Breaking change visibility**: migration notes must ship with this sub-phase's release (the `TorControlAuth` rename is source-breaking).

---

## Next `/speckit.specify` Hints

```
/speckit.specify "Feature: TorControlClient Extension Split"
/speckit.specify "Feature: TorConfiguration Extension Split + Presets"
/speckit.specify "Feature: TorConfiguration.validate() + TorConfigError + TorConfigWarning"
/speckit.specify "Feature: TorControlAuth Enum Replaces cookieAuthentication+controlPassword"
/speckit.specify "Feature: TorError LocalizedError + Typed Throws on Control APIs"
/speckit.specify "Feature: TorSignal Enum Replaces signal(_ String)"
/speckit.specify "Feature: Typed CircuitStatus and StreamStatus Enums"
```
