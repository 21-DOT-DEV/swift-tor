# Phase 5.3: API Type-Safety — Typestate + Dependency Injection

**Status**: 🔜 Planned  
**Priority**: High (tallest pole of the 5.x theme)  
**Last Updated**: 2026-04-17  
**Depends On**: Phase 5.1 (Foundation), Phase 5.2 (Identifier Hygiene)

---

## Objective

Encode Tor's lifecycle in the type system via `TorHandle<State>: ~Copyable` (typestate pattern), remove the `TorSession` protocol, and replace it with a closure-based `TorEngine` dependency-injection seam gated by `@_spi(Testing)`. Eliminate runtime lifecycle guards (`.alreadyStarted`, `.notStarted`, `.controlUnavailable`) by making illegal calls unrepresentable.

---

## Constitutional Alignment

- **Principle IV** — API Design & Safe Defaults: correctness is a compile-time property, not a runtime assertion.
- **Principle V** — Spec-First & TDD: typestate transitions are specified as type signatures; tests verify behavior, not protocol conformance.
- **Principle VI** — Cross-Platform CI & Quality Gates: the `TorEngine.fake(...)` factory is what makes the deterministic-tier requirement achievable. Without it, tests would require real Tor bootstrap (30–60 s) which cannot gate every PR.

---

## Design Sketch

```swift
// Public typestate façade (value type, noncopyable)
public struct TorHandle<State>: ~Copyable {
    internal let runtime: TorRuntime       // ref to actor
    internal let engine: TorEngine         // DI seam
    internal init(/* ... */)
}

public enum Idle {}; public enum Running {}; public enum Stopped {}

extension TorHandle where State == Idle {
    public init(configuration: TorConfiguration,
                @_spi(Testing) engine: TorEngine = .live)
    public consuming func start() async throws -> TorHandle<Running>
}

extension TorHandle where State == Running {
    public func control() -> TorControlClient                    // no throw
    public func waitUntilBootstrapped(timeout: Duration = .seconds(120)) async throws
    public var socksEndpoint: HostPort? { get async }
    public consuming func stop() async -> TorHandle<Stopped>
}

// Internal concurrency primitive — replaces the public TorClient actor
internal actor TorRuntime {
    // Wraps libtor FFI, event broadcasting, control socket setup.
}

// Closure-based dependency seam — replaces the TorSession protocol
public struct TorEngine: Sendable {
    var start:     @Sendable () async throws -> Void
    var bootstrap: @Sendable (Duration) async throws -> Void
    var stop:      @Sendable () async -> Void
    var events:    @Sendable () -> AsyncStream<TorEvent>

    public static let live: TorEngine = .init(/* real libtor call-chain */)

    @_spi(Testing)
    public static func fake(bootstrapDelay: Duration = .zero,
                            simulateFailure: Bool = false,
                            events: [TorEvent] = []) -> TorEngine
}
```

**Test call-site**:
```swift
@_spi(Testing) import Tor

@Test func bootstrapHandles() async throws {
    let handle = TorHandle<Idle>(configuration: .ephemeral(),
                                 engine: .fake(bootstrapDelay: .zero))
    let running = try await handle.start()
    // handle.start() here would be a compile error: `handle` was consumed
    _ = await running.stop()
}
```

---

## Features

| Feature | Purpose & User Value | Success Metrics | Dependencies | Notes |
|---------|----------------------|-----------------|--------------|-------|
| **`TorHandle<State>: ~Copyable` façade** | Lifecycle encoded in the type. `control()`, `waitUntilBootstrapped()`, `stop()` only reachable on `TorHandle<Running>`. Using a handle after `stop()` becomes a compile error (noncopyable consumption). | `.alreadyStarted`, `.notStarted`, `.controlUnavailable` error cases unreachable; runtime `guard state == .running else throw` patterns deleted. | 5.1 (typed errors), 5.2 (tagged IDs); Swift 6.1 `~Copyable` | Swiftology's Turnstile pattern applied to Tor's Idle→Running→Stopped state machine. |
| **`TorRuntime` actor (internal)** | Concurrency primitive. Actors are reference types and cannot be `~Copyable`, but a noncopyable handle can hold a reference to an actor. Keeps the existing Foundation-free concurrency model. | `TorHandle` is pure value-type façade; actor isolation preserved; no `@unchecked Sendable` workarounds in public API. | Above | — |
| **`TorEngine` closure DI + `@_spi(Testing) fake(...)`** | Replace the `TorSession` protocol with struct-of-closures DI. Modern Swift idiom (swift-dependencies / swift-nio / swift-crypto pattern). Deterministic-tier tests run without real Tor bootstrap. | `.live` constructor for production; `@_spi(Testing) .fake(...)` for tests; all existing `TorSessionTests` migrated. | Above | Fakes live in the main `Tor` module behind `@_spi(Testing)` per Round 3 decision. |
| **Delete `TorSession` protocol + tests** | Remove `Sources/Tor/TorSession.swift` and `Tests/TorTests/TorSessionTests.swift`. Protocol is incompatible with `~Copyable` and its functionality is absorbed by `TorEngine`. | Files removed; no remaining references in `Sources/` or `Tests/`; test suite green. | Above | Breaking change; migration guide required. |
| **Migrate `URLSession+Tor.swift`** | `makeURLSession()` moves from `extension TorClient` onto `TorHandle<Running>`. `guard state.isOperational else throw` becomes unnecessary — the extension only exists on `Running`. | `Sources/Tor/Apple/URLSession+Tor.swift:64-86` rewritten onto `TorHandle<Running>`; no runtime state check. | Above | — |
| **Typestate-aware `OnionService`** | Model ephemeral onion services as linear resources: they can't outlive the control connection that created them. Optional: noncopyable `OnionService` consumed by `delOnion()`. | Service lifetime tied to handle scope at the type level; accidental post-teardown use becomes a compile error. | Above | Gated on whether the design sketch holds up — may spin to a follow-on spec if complex. |
| **Migration guide** | Document the `TorClient` actor → `TorHandle<State>` value-type migration and the `TorSession` → `TorEngine` seam change. | Guide merged into `docs/migration/` or `README.md`; release notes draft present. | All above | Include before/after code snippets; cover the most common patterns (start+wait+stop, onion-service creation, URLSession proxy). |

---

## Sequencing

1. **Prototype `TorHandle` + `TorRuntime`** — smallest end-to-end slice: Idle → Running → Stopped, no control client yet. Validates the actor-behind-handle boundary.
2. **Integrate `TorEngine`** with `.live` and `.fake(...)` — the DI seam. Rewrite one existing test as a proof-of-concept.
3. **Migrate `waitUntilBootstrapped` and `control()`** onto `TorHandle<Running>`.
4. **Delete `TorSession` + rewrite `TorSessionTests`** — after all call sites are migrated.
5. **Migrate `URLSession+Tor.swift`** — the last public extension against `TorClient`.
6. **Typestate-aware `OnionService`** — if feasible per design; otherwise spin to a follow-on spec.
7. **Migration guide** merges with the final PR.

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| Runtime lifecycle guards in public API | 0 (all replaced by compile-time typestate) |
| Unreachable-in-practice error cases | `.alreadyStarted`, `.notStarted`, `.controlUnavailable` removed or deprecated |
| Test determinism (Constitution VI) | 100% of PR-gating tests run with `TorEngine.fake`; no real bootstrap required |
| Breaking changes documented | migration guide + release notes |
| Library version | pre-1.0 minor bump (`0.x → 0.(x+1)`) |

---

## References

- Swiftology — [Typestate in Swift 5.9](https://swiftology.io/articles/typestate/)
- WWDC24 — [Consume noncopyable types in Swift](https://developer.apple.com/videos/play/wwdc2024/10170/)
- SE-0390 — Noncopyable structs and enums
- SE-0427 — Noncopyable generics
- swift-dependencies — closure-based DI pattern
- `@_spi(Testing)` precedent: `swift-nio`, `swift-syntax`, `swift-crypto`

---

## Risks / Open Questions

- **Typestate + actor interaction**: resolved by value-type `TorHandle` + internal `TorRuntime` actor. Still to validate: whether `~Copyable` playing nicely with `async` functions holds in all transition scenarios (Swift 6.1 noncopyable+async has known edge cases in early adoption).
- **Swift 6.1 noncopyable limitations**: cannot conform to protocols, cannot be used with `Optional` or `Result`. Design avoids these; any fallible transition returns an explicit noncopyable enum (Swiftology's `TransitionResult` pattern).
- **`@_spi(Testing)` long-term stability**: underscore attribute, not formally part of the language. Stable since Swift 5.3 and used by Apple's own libraries, but re-evaluate `TorTestKit` module split at 1.0.
- **Downstream migration cost**: this is the largest breaking change in the 5.x theme. Migration guide is mandatory, not optional.
- **`OnionService` typestate**: if it turns out too constraining, keep `OnionService` as a plain value and rely on control-connection scope for lifetime.

---

## Next `/speckit.specify` Hints

```
/speckit.specify "Feature: TorHandle Typestate Prototype (Idle → Running → Stopped)"
/speckit.specify "Feature: TorEngine Closure DI + @_spi(Testing) Fake"
/speckit.specify "Feature: TorSession Protocol Removal + Test Migration"
/speckit.specify "Feature: URLSession+Tor Migration onto TorHandle<Running>"
/speckit.specify "Feature: Typestate-aware OnionService (if feasible)"
/speckit.specify "Feature: 5.x Migration Guide"
```
