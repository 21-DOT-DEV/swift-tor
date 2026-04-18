# Phase 3: iOS Target Refactor

**Status**: ❓ Unscoped  
**Priority**: TBD (depends on scope resolution)  
**Last Updated**: 2026-04-17  
**Depends On**: —

---

## Objective

_To be defined._ This phase carries forward from an earlier roadmap but does not have documented concrete goals.

---

## Current iOS Baseline (verified 2026-04-17)

iOS support **already ships today**:

- `Package.swift:16` declares `.iOS(.v16)`
- `.github/workflows/apple-builds.yml:18-29` has a passing iOS build job (`xcodebuild -destination generic/platform=iOS`)
- `Sources/Tor/Apple/URLSession+Tor.swift` is the iOS-compatible `URLSession` proxy helper (guarded by `#if canImport(CFNetwork)`)
- `README.md:17` advertises iOS 16+ as a supported platform

What "refactor" is pending is **not documented in any artifact**.

`[NEEDS CLARIFICATION: specific refactor goals — e.g., TorDemo iOS-compatibility, platform-specific target split, or drop the phase]`

---

## Candidate Scopes (to be confirmed)

Three plausible readings of the phase name:

### Candidate A: Make `TorDemo` iOS-compatible
- `TorDemo` is currently an `.executableTarget` (Package.swift:71-75). Executables don't build for iOS.
- Refactor options: convert to a SwiftUI/UIKit sample app, or move to a `Examples/` directory outside the SPM graph.
- Effort: S–M.

### Candidate B: Platform-specific target split
- Move Apple-only helpers (`URLSession+Tor.swift`) into a dedicated `TorApple` target.
- Cleaner dependency graph on Linux builds; no `#if canImport(CFNetwork)` guards in source.
- Effort: S.

### Candidate C: Drop the phase
- Baseline iOS support already meets the constitution's Principle VI Platform scope.
- If no concrete gap motivates the refactor, remove from roadmap and redirect effort elsewhere.
- Effort: — (delete only).

---

## Features

_None defined until scope is resolved._

---

## Sequencing

Orthogonal to the 5.x API Type-Safety theme. Can run before, during, or after.

---

## Phase-Level Metrics

_To be defined with scope._

---

## Risks / Open Questions

- **Scope drift**: the phase name implies work, but no work items exist. Risk: phantom scope lingering on the roadmap creates false signal.
- **Overlap with 5.3**: Phase 5.3 already migrates `Sources/Tor/Apple/URLSession+Tor.swift` onto `TorHandle<Running>`. If Candidate B is chosen, it may conflict with 5.3; if Candidate A, no overlap.

---

## Resolution Checklist

- [ ] Project owner confirms concrete scope (A / B / C or alternative)
- [ ] If retained: convert `[NEEDS CLARIFICATION]` marker to concrete Features table
- [ ] If dropped: remove from `roadmap.md` Phases Overview and record in Change Log
