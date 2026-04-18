# Phase 5.2: API Type-Safety — Identifier Hygiene

**Status**: 🔜 Planned  
**Priority**: High  
**Last Updated**: 2026-04-17  
**Depends On**: Phase 5.1 (extension splits + typed enums establish the pattern)

---

## Objective

Eliminate cross-identifier mix-ups and empty-collection bugs at compile time. Introduce tagged identifiers (no mixing `ServiceID`, `CircuitID`, `StreamID`), a proper OptionSet for onion-service flags, and non-empty collection types for APIs where empty is always a bug.

---

## Constitutional Alignment

- **Principle IV** — API Design & Safe Defaults: invalid input becomes unrepresentable.
- **Principle I** — Scope & Dependency Hygiene: if `swift-tagged` is adopted, that's a new runtime dependency requiring a constitutional amendment (MINOR bump) to the allowlist. The local-vendor alternative avoids this.

---

## Features

| Feature | Purpose & User Value | Success Metrics | Dependencies | Notes |
|---------|----------------------|-----------------|--------------|-------|
| **`OnionServiceFlags: OptionSet`** | Replace `detach: Bool` in `TorControlClient.addOnion(...)` with a composable flag set (`DiscardPK`, `Detach`, `MaxStreamsCloseCircuit`, `NonAnonymous`, `V3Auth`). Exposes the full ADD_ONION surface with compile-time correctness. | ADD_ONION flag surface 100% typed; `validate()` catches known invalid combinations (e.g., `NonAnonymous` without `HiddenServiceSingleHopMode`). | 5.1 (pattern established) | Reference: `swift-bitcoin` `BitcoinConfig.swift:21-42` `ConfigFlags: OptionSet`. |
| **Tagged Identifiers (`ServiceID`, `CircuitID`, `StreamID`)** | Make cross-ID mix-ups unrepresentable: passing a `StreamID` where a `CircuitID` is expected becomes a compile error. Inherits all `String` conformances via phantom-tagged wrapper. | 0 `String` id parameters in public API; `OnionService.serviceID`, `TorEvent.circuit(id:...)`, `TorEvent.stream(id:...)` all use tagged types. | Tagged-type decision (see below) | — |
| **`NonEmpty` for `ports` / `events`** | Empty collections in `TorControlClient.addOnion(ports:)` and `TorControlClient.subscribe(to: events:)` are always a runtime error (`ADD_ONION` rejects; `SETEVENTS` with an empty set disables all events, typically a bug). Make unrepresentable. | 0 runtime empty-collection checks on these paths; API signatures use `NonEmpty<[OnionPortMapping]>` and `NonEmpty<Set<TorControlEvent>>` or equivalent. | — | Consider [pointfreeco/swift-nonempty](https://github.com/pointfreeco/swift-nonempty) pattern; may vendor locally if we also vendor `Tagged`. |

---

## Open Decision (MUST resolve before implementation)

`[NEEDS CLARIFICATION: swift-tagged as a runtime dependency vs. vendored local Tagged]`

### Option A: Add `pointfreeco/swift-tagged` to the allowlist
- **Pros**: battle-tested; full `Codable`/`Hashable`/`Comparable`/`ExpressibleByStringLiteral` via conditional conformance.
- **Cons**: +1 runtime dependency; Constitution Principle I requires an amendment (MINOR bump) to add.
- **Process**: amend `.specify/memory/constitution.md` to add `pointfreeco/swift-tagged` to the allowlist; document justification.

### Option B: Vendor a ~20-line local `Tagged`
- **Pros**: no allowlist amendment; minimal dependency surface; sufficient for our use cases.
- **Cons**: have to maintain conditional conformance additions ourselves; ~20 lines grows over time.
- **Process**: implement as an internal helper in a new `Sources/Tor/Support/Tagged.swift`.

**Recommended default**: Option B (vendor local) unless the decision-maker prefers the upstream dep.

---

## Sequencing

1. Resolve the Tagged-dep decision.
2. Ship `OnionServiceFlags: OptionSet` (independent of Tagged decision).
3. Ship Tagged identifiers on `OnionService.serviceID` first (simplest migration).
4. Extend tagged IDs to `TorEvent.circuit` / `.stream` (requires coordination with 5.1's typed statuses).
5. `NonEmpty` for `ports` / `events` last.

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| `String`-typed id params on public API | 0 |
| ADD_ONION flag coverage | all 5 documented flags modeled |
| Runtime empty-collection checks eliminated | ≥ 2 (ports, events) |
| Call-site migration scope | known and documented before landing |

---

## References

- `pointfreeco/swift-tagged` — https://github.com/pointfreeco/swift-tagged
- `pointfreeco/swift-nonempty` — https://github.com/pointfreeco/swift-nonempty
- Swift by Sundell — [Type-safe identifiers in Swift](https://www.swiftbysundell.com/articles/type-safe-identifiers-in-swift/)

---

## Risks / Open Questions

- **Tagged decision** (see above) — blocks implementation start.
- **Migration scope** — tagged IDs touch every API surface that currently uses `String` for an id. Sequence after 5.1's extension splits so the diffs are small.

---

## Next `/speckit.specify` Hints

```
/speckit.specify "Feature: OnionServiceFlags OptionSet"
/speckit.specify "Feature: Tagged Identifiers — ServiceID, CircuitID, StreamID"
/speckit.specify "Feature: NonEmpty Collection Types for addOnion(ports:) and subscribe(to:)"
```
