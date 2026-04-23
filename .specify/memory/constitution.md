<!--
Sync Impact Report:
- Version: N/A → 1.0.0 (Initial constitution)
- Change Type: Initial creation
- Scope: swift-tor package (/Users/csjones/Developer/swift-tor)
- Structure: Seven core principles + implementation practices + governance, three-tier enforcement (MUST/SHOULD/MAY + explicit MUST NOT)
- Core Principles:
  I. Scope & Tor Standards Alignment
  II. Metadata Hygiene & Honest Anonymity Claims
  III. Key & Onion Secret Handling
  IV. API Design & Safe Defaults
  V. Spec-First & Test-Driven Development
  VI. Cross-Platform CI & Quality Gates
  VII. Open Source Excellence
- Governance: BDFL model, pre-1.0 stability posture, security-relevant change protocol
- Templates Status:
  ⚠ .specify/templates/spec-template.md - Requires alignment review (integration-test env-gating, Vendor extraction)
  ⚠ .specify/templates/plan-template.md - Requires alignment review (Constitution Check section)
  ⚠ .specify/templates/tasks-template.md - Requires alignment review (task categories for Vendor sync, determinism tier)
  ⚠ .specify/templates/checklist-template.md - Requires alignment review
- Follow-up TODOs:
  • Create CONTRIBUTING.md with Vendor/tor extraction workflow and PR discipline
  • Create SECURITY.md with vulnerability disclosure process (including coordinated disclosure with Tor Project for upstream-originating issues)
-->

# Constitution for swift-tor

## Preamble

This constitution governs the **swift-tor** package, a Swift package that embeds Tor
(`libtor`) and exposes a Swift-concurrency-first API (`Tor` / `TorClient`) for client
applications on macOS, iOS, and Linux.

**Scope**: This repository only. Covers the `libtor` C-bindings product and the `Tor`
Swift wrapper product, plus the vendored Tor source tree under `Vendor/tor/`.

**Threat-model framing (narrow)**: swift-tor promises *correct Tor integration* — honest
embedding of upstream Tor, metadata hygiene in the Swift/C boundary we own, safe
defaults, and accurate documentation of what Tor does and does not protect. swift-tor
does **not** promise end-to-end anonymity: anonymity ultimately depends on the
application's behavior, threat model, and operational posture, which are outside this
library's control. Principles are written to be enforceable at the layer swift-tor
actually owns.

**Philosophy**: Minimize what we promise; keep what we do promise enforceable in code
review and CI; stay close to upstream Tor; refuse to reinvent anonymity protocols.

---

## Core Principles

### I. Scope & Tor Standards Alignment

**Statement**: The package MUST focus on embedding Tor and exposing client-oriented
APIs that conform to Tor Project specifications. `libtor` MUST be the sole source of
Tor protocol behavior; runtime dependencies MUST be drawn from a small, explicit
allowlist.

**Rationale**: Keeping scope tight reduces attack surface and maintenance burden.
Aligning with upstream Tor specs avoids fragmentation, protocol drift, and subtle
incompatibilities that degrade user anonymity.

**Practices**:
- **MUST** limit scope to embedding Tor and exposing client, onion-service, and
  control-protocol APIs grounded in the Tor Project specifications (e.g.,
  `control-spec`, `rend-spec-v3`, `pt-spec`, `dir-spec`, `tor-spec`).
- **MUST** use the vendored `libtor` tree under `Vendor/tor/` as the sole source of
  Tor protocol behavior and cryptographic primitives sourced from its C stack.
- **MUST** limit runtime dependencies to the following allowlist:
  - `libtor` (this package's own C bindings target)
  - `swift-openssl` (`libcrypto`, `libssl`) — Tor's required TLS/crypto backend
  - `swift-event` (`libevent`) — Tor's required event loop
  - System `zlib` — Tor's required compression library
- **MUST NOT** add runtime dependencies outside the allowlist without a constitutional
  amendment (MINOR version bump) that records the justification.
- **MUST NOT** implement novel anonymity protocols, alternate onion-service schemes,
  or unreviewed cryptographic constructions inside this package.
- **SHOULD** align high-level Swift APIs with Tor Project terminology and spec-level
  concepts (bootstrap phases, circuits, streams, onion services, pluggable transports).
- **MAY** expose lower-level `libtor` bindings for advanced use cases, clearly marked
  as such.

**Compliance**: PRs adding new runtime dependencies or new protocol surface MUST cite
the governing Tor specification and MUST include constitutional review. CI blocks
unapproved dependency additions.

---

### II. Metadata Hygiene & Honest Anonymity Claims

**Statement**: swift-tor MUST avoid leaking user-identifying or circuit-identifying
metadata through the layers it owns, and MUST document accurately what Tor does and
does not protect. The library MUST NOT overstate the anonymity guarantees available
to consumers.

**Rationale**: The anonymity a user experiences is a property of their whole system;
no library can deliver anonymity on its own. What swift-tor *can* deliver is honest
framing plus a disciplined refusal to leak metadata in the Swift/C layer we wrote.
Overpromising erodes user trust and, worse, may cause users to relax operational
precautions they still need.

**Practices**:
- **MUST** ensure default log output contains no circuit IDs, onion addresses, SOCKS
  credentials, bridge lines, relay fingerprints, or guard identities at informational
  log levels.
- **MUST** avoid persistent on-disk identifiers unless the user explicitly opts in
  (e.g., persistent onion keys, reusable cache directories).
- **MUST** ensure public error types, debug descriptions, and crash surfaces do not
  embed secret material or routing-sensitive identifiers.
- **MUST** document in the README and API reference what Tor actually protects
  (network-layer identity for routed traffic) and what it does not (application-layer
  fingerprinting, user behavior, clock leaks, DNS leaks caused by the application,
  side channels outside Tor).
- **MUST NOT** claim or imply that using swift-tor, on its own, anonymizes a user.
- **SHOULD** prefer safe-by-default configurations (e.g., isolated SOCKS auth, DNS
  through Tor where the API supports it) and require explicit opt-out for weaker
  modes.
- **SHOULD** provide a documented, opt-in verbose logging tier for debugging that
  still redacts onion addresses and keys.
- **MAY** expose raw control-protocol responses for advanced users, clearly marked as
  carrying sensitive data.

**Compliance**: Code review MUST verify log and error redaction on any PR touching
logging, error types, or the control protocol. Documentation changes MUST preserve
the honest-framing language in the README and SECURITY.md.

---

### III. Key & Onion Secret Handling

**Statement**: Private keys (ED25519-V3 onion-service keys, client-auth keys), control
authentication material (cookies, passwords), and bridge credentials MUST be treated
as secrets: generated securely, scoped to the minimum lifetime, and never exposed
through public APIs except as opaque types.

**Rationale**: Onion-service private keys *are* the onion address. Leaking a key
silently transfers control of the service. Control authentication material gates
every sensitive runtime operation. Both demand the same discipline applied to any
cryptographic secret.

**Practices**:
- **MUST** generate keys, control cookies, and any random material using the CSPRNGs
  provided by `libtor` / `libcrypto`; MUST NOT introduce alternate RNG paths.
- **MUST** make ephemeral onion keys the default (private key discarded after
  teardown) for ephemeral onion-service APIs.
- **MUST** require explicit opt-in to retain a persistent onion private key, and
  document secure-storage guidance (e.g., Keychain on Apple platforms, appropriate
  file-permission guidance on Linux).
- **MUST NOT** log, print, or embed in descriptions any private key, control cookie,
  bridge credential, or client-auth secret.
- **MUST NOT** accept predictable, hardcoded, or test-vector onion keys in
  production-facing APIs; test fixtures MUST be clearly segregated.
- **MUST** zero sensitive Swift-owned buffers (e.g., intermediate representations of
  keys marshalled across the C boundary) when they go out of scope, where the Swift
  layer owns the allocation.
- **SHOULD** expose secrets only as opaque Swift types with restricted printable
  representations.
- **MAY** provide clearly-named unsafe escape hatches for expert users who need raw
  key material.

**Compliance**: Code review MUST verify secret handling on any PR touching onion
services, control authentication, or bridge configuration. CI MUST scan for obvious
regressions (e.g., `print`/`NSLog` statements on key-carrying types).

---

### IV. API Design & Safe Defaults

**Statement**: Public Swift APIs MUST follow a Swift-concurrency-first design with
safe defaults. Advanced or footgun-prone operations MUST live behind clearly named,
documented surfaces.

**Rationale**: swift-tor will be consumed by application developers who are experts
in their domain but not necessarily in Tor internals. Safe defaults protect typical
users; explicit "unsafe" or "advanced" naming ensures that the risk of a sharp-edged
API is impossible to miss.

**Practices**:
- **MUST** expose `TorClient` as an actor (or equivalent concurrency-isolated type)
  with an async/await surface; MUST NOT introduce Combine-based public API (Combine
  is unavailable on Linux).
- **MUST** prefer default configurations that minimize cross-circuit linkability
  (e.g., SOCKS isolation flags on by default where practical) and document any
  trade-off made in the default.
- **MUST** use strongly-typed errors; error descriptions MUST NOT embed secret
  material or routing-sensitive identifiers (see Principle II).
- **MUST** clearly separate the high-level `Tor` product from the lower-level
  `libtor` bindings product so consumers can choose their altitude.
- **MUST** document every public type and function with Swift doc comments.
- **SHOULD** gate advanced operations (manual control-protocol commands, raw cell
  access, bridge/relay-oriented surface if introduced) behind explicit `unsafe` or
  `advanced` naming and documentation.
- **SHOULD** provide compile-time or runtime guards that make platform-unsupported
  APIs (e.g., Apple-only helpers under `canImport(CFNetwork)`) unambiguous to the
  caller.
- **MAY** offer convenience helpers for common integrations (URLSession via Tor,
  onion-service creation) that compose the lower-level primitives.

**Compliance**: Code review enforces API naming, concurrency model, and
documentation requirements.

---

### V. Spec-First & Test-Driven Development

**Statement**: Every feature MUST begin with a specification. Implementation MUST
follow test-driven development: tests written first, verified to fail, then code
written to make them pass.

**Rationale**: Specifications force alignment with users and provide measurable
acceptance criteria. TDD prevents regressions, enables confident refactoring across
the Swift/C boundary, and documents intended behavior for future contributors.

**Practices - Specification Requirements**:
- **MUST** create `spec.md` for every feature before development begins.
- **MUST** scope each spec to a single feature or small, independently-testable
  sub-feature.
- **MUST** define user scenarios, acceptance criteria, and success metrics in
  user-facing terms.
- **MUST NOT** combine multiple unrelated features in one spec.
- **MUST NOT** describe implementation details in place of behavior.

**Practices - Test-Driven Development**:
- **MUST** write tests before implementation (red → green → refactor).
- **MUST** verify tests fail before the implementing change lands.
- **MUST** validate control-protocol parsers and config-validation logic against
  fixtures derived from the relevant Tor specifications.
- **MUST** maintain a clear separation between deterministic unit tests and
  env-gated live-network integration tests (see Principle VI).
- **SHOULD** develop outside-in, starting from the caller's perspective.
- **MAY** add property-based tests for parser and state-machine components where
  they add value beyond fixture-based coverage.

**Compliance**: PRs MUST include tests written first. PRs that ship code without
corresponding tests, or whose tests pass on the first commit before the
implementation exists, MUST be rejected in review. Specs that combine multiple
unrelated features MUST be rejected in review.

---

### VI. Cross-Platform CI & Quality Gates

**Statement**: The package MUST compile and (where applicable) test cleanly on all
supported platforms. Tests MUST be partitioned into a deterministic tier that gates
every PR and an env-gated integration tier that runs out-of-band. Platform scope is
normative.

**Rationale**: Cross-platform reliability is a core value proposition. Enforcing a
deterministic CI tier preserves signal; isolating live-network tests preserves
coverage without eroding trust in the merge gate. Locking platform scope normatively
prevents recurring discussion of Apple platforms on which Tor cannot run at all.

**Practices - Platform scope**:
- **MUST** support and exercise in CI:
  - macOS 15+ (build and deterministic tests)
  - iOS 18+ (build)
  - Linux (Ubuntu 22.04+, build and deterministic tests)
- **Platform floor rationale**: the macOS 15 / iOS 18 minimum is required by
  `Synchronization.Mutex` (SE-0410), which underpins the compiler-verified
  `Sendable` conformance of `ControlSocket` and `TorControlClient`. Lowering
  the floor would require reverting to `@unchecked Sendable` escape hatches.
- **MUST NOT** add support for **tvOS, watchOS, or visionOS**. Tor's source depends
  on UNIX process primitives (`fork`, `execve`, `daemon`, `setuid`) that Apple
  prohibits on those platforms, and the prohibition is enforced at App Store review.
  Reopening this scope requires a constitutional amendment with a concrete technical
  justification.

**Practices - Test determinism (two-tier)**:
- **MUST** ensure unit tests, control-protocol parser tests, and config-validation
  tests are fully deterministic and gate every PR in CI.
- **MUST** env-gate live-network integration tests (e.g., `TOR_INTEGRATION_TESTS=1`)
  so they do not run in default PR CI.
- **MUST** document timeouts and retry policies for any non-deterministic test.
- **SHOULD** run integration tests on a scheduled cadence and surface failures
  separately from blocking CI.
- **MUST NOT** mark a test "flaky" as a workaround for real non-determinism in
  production code.

**Practices - Upstream tracking & Vendor sync**:
- **MUST** monitor Tor Project security advisories and upstream stable releases on
  a best-effort cadence and MUST document merge/skip decisions (e.g., via commit
  trailers, `Vendor/tor/`-adjacent notes, or a SECURITY.md changelog).
- **MUST** perform Vendor tree updates via the declared subtree extraction workflow
  (`subtree.yaml` + `swift-plugin-subtree`); MUST NOT hand-edit files under
  `Vendor/tor/`.
- **SHOULD** merge upstream security fixes promptly.
- **SHOULD** exercise both the libbsd-present and libbsd-absent Linux build paths
  so long as both are supported configurations.

**Compliance**: CI pipeline enforces every MUST in this principle. Platform build or
deterministic-tier failures block merge.

---

### VII. Open Source Excellence

**Statement**: All development MUST follow open-source best practices: clear
documentation, welcoming contribution process, correct licensing and attribution,
and code that favors readability over cleverness.

**Rationale**: swift-tor sits in an ecosystem where users evaluate library trust
before adopting it. Good documentation, responsive maintenance, and clear licensing
lower adoption friction and increase the chance that security-relevant feedback
reaches the maintainer.

**Practices**:
- **MUST** include a LICENSE file (MIT) for swift-tor's own code.
- **MUST** preserve and attribute the upstream Tor license(s) shipped under
  `Vendor/tor/` (see `Vendor/tor/LICENSE`).
- **MUST** maintain a README with setup, supported platforms, a Quick Start, and
  honest security/privacy framing.
- **MUST** provide `CONTRIBUTING.md` describing branch, PR, commit, and Vendor-sync
  conventions.
- **MUST** provide `SECURITY.md` describing the vulnerability disclosure process,
  preferred contact, and expected response timeline.
- **MUST** document every public API with Swift doc comments.
- **MUST** ship at least one minimal runnable example (e.g., `TorDemo`) covering
  bootstrap, clearnet fetch via Tor, and onion-service creation.
- **MUST** apply KISS and DRY principles; favor readable code over clever code.
- **SHOULD** provide issue and PR templates.
- **SHOULD** respond to community contributions and security reports promptly and
  respectfully.

**Compliance**: PRs MUST include documentation updates for new features or API
changes. Code reviewers enforce readability.

---

## Implementation Guidance

### Security Disclosure Process

**Statement**: A clear process for reporting vulnerabilities MUST be documented.

**Requirements**:
- **MUST** provide `SECURITY.md` with reporting instructions. *(TODO: create file.)*
- **MUST** include a preferred contact method (email, encrypted if possible).
- **MUST** define an expected response timeline (e.g., acknowledgment within 48
  hours).
- **MUST** commit to a coordinated disclosure timeline.
- **SHOULD** provide a PGP key for encrypted reports.
- **SHOULD** acknowledge reporters in release notes (with permission).
- **SHOULD** coordinate with the Tor Project's disclosure process when the issue
  originates upstream in `Vendor/tor/`.

**Security-Relevant Changes**:
- Maintainer MUST document security implications in the PR description.
- 48–72 hour merge delay for community review opportunity.
- Explicit "security-reviewed" label required before merge.

---

### Vendor & Extraction Workflow

**Purpose**: `Vendor/tor/` contains an extracted copy of upstream Tor. Keeping this
tree clean and reproducible is a security property.

**Requirements**:
- **MUST** update `Vendor/tor/` only through the declared subtree extraction tooling
  (`subtree.yaml` + `swift-plugin-subtree`).
- **MUST NOT** hand-edit files under `Vendor/tor/`. Any required local patch MUST
  be applied via the extraction configuration or a documented patch file outside
  the vendored tree.
- **MUST** record the upstream revision / tag being extracted in the commit that
  performs the extraction.
- **SHOULD** re-extract on upstream security fixes per Principle VI.

---

## Technology Stack (Current Implementation)

**Note**: The constitution defines technology-agnostic principles. This section
documents current choices, which may change without constitutional amendments so
long as the principles above continue to hold.

### Supported Platforms

- **macOS** 13+ (arm64, x86_64)
- **iOS** 16+ (arm64)
- **Linux** (x86_64, arm64) — Ubuntu 22.04+ validated via Docker

Not supported (normative per Principle VI): tvOS, watchOS, visionOS.

### Current Stack (2026-04-17)

- **Language**: Swift 6.1, language mode `.v6`
- **Build**: Swift Package Manager (SPM)
- **Testing**: swift-testing / XCTest
- **CI**: GitHub Actions (Apple + Docker Linux)
- **Vendor tooling**: `swift-plugin-subtree`

### Products

| Product   | Type                | Description                                    |
|-----------|---------------------|------------------------------------------------|
| `Tor`     | Swift wrapper       | High-level, concurrency-first client API       |
| `libtor`  | C bindings target   | Raw bindings to the vendored Tor source tree   |
| `TorDemo` | Executable example  | Runnable demo of bootstrap + onion service     |

### Runtime Dependencies (allowlist per Principle I)

- `swift-openssl` — `libcrypto`, `libssl`
- `swift-event` — `libevent`
- System `zlib` (linked as `-lz`)

### Development-only Dependencies

- `swift-plugin-subtree` (Vendor extraction)
- Linting / formatting tooling if/when introduced (non-blocking for v1.0.0)

---

## Governance

### Authority

This constitution supersedes all other development practices for this repository.
Deviations MUST be explicitly justified and approved.

**Model**: Project owner (BDFL) can amend the constitution directly. Community
proposes changes via GitHub issues and pull requests.

### Security-Relevant Changes

Changes that affect anonymity properties, key handling, log output, or the
control-protocol surface require additional scrutiny:

| Requirement                                          | Purpose                     |
|------------------------------------------------------|-----------------------------|
| Document security implications in the PR description | Creates an audit trail      |
| 48–72 hour merge delay                               | Allows community review     |
| Explicit "security-reviewed" label                   | Signals deliberate review   |

**Security-relevant changes include**:
- Changes to logging, error descriptions, or debug output.
- Changes to onion-service key handling or control authentication.
- Changes to default configuration values affecting circuit isolation or DNS.
- Vendor tree updates that touch Tor's cryptographic or networking layers.

### Amendment Process

1. Project owner proposes an amendment with rationale and impact analysis.
2. Version updated (semantic versioning):
   - **MAJOR**: Backward-incompatible changes or principle removals.
   - **MINOR**: New principle, new dependency on the allowlist, or materially
     expanded guidance.
   - **PATCH**: Clarifications, wording fixes, non-semantic refinements.
3. Update dependent templates in `.specify/templates/` as needed.
4. Document the change in the Sync Impact Report at the top of this file.
5. Commit with a descriptive message.

### Compliance Review Triggers

| Trigger                                                | Action                                   |
|--------------------------------------------------------|------------------------------------------|
| Adding a runtime dependency outside the allowlist      | Full constitutional amendment required  |
| Tor upstream security advisory                         | Best-effort merge + documented decision |
| Change to onion-key / control-auth / logging surface   | Security review required                |
| Introduction of relay, bridge, or pluggable-transport surface | Spec-level governance required (per-feature spec.md) |
| Breaking API changes (post-1.0)                        | Stability-signalling review required    |

### Versioning & Stability

**Pre-1.0** (current):
- No stability guarantees.
- Immediate breaking changes acceptable.
- Users advised to pin exact versions (e.g., `.exact("0.x.y")`).

**Post-1.0** (future):
- Semantic versioning strictly enforced.
- Deprecation period (one minor version) before removal of public API.
- Breaking changes require a major version bump.

### Enforcement

- PR reviewers verify constitutional alignment.
- CI pipeline enforces MUST-level (blocking), SHOULD-level (warnings).
- Three-tier enforcement:
  - **MUST**: Blocks merge.
  - **SHOULD**: Warning; requires override justification in the PR description.
  - **MAY**: Informational only.

---

## Version History

**Version**: 1.1.0
**Ratified**: 2026-04-17
**Last Amended**: 2026-04-23

**Changelog**:
- **1.1.0** (2026-04-23): **MINOR amendment** — Principle VI platform floor
  raised from macOS 13+ / iOS 16+ to macOS 15+ / iOS 18+. Justification:
  `Synchronization.Mutex` (SE-0410) is required for compiler-verified
  `Sendable` conformance of `ControlSocket` and `TorControlClient`, replacing
  the prior `@unchecked Sendable` + `NSLock` pattern and a hand-rolled
  `ManagedAtomic<Bool>` helper. The minimum iOS 18 / macOS 15 deployment is
  the prerequisite. Linux (Ubuntu 22.04+) unaffected. tvOS/watchOS/visionOS
  MUST-NOT line preserved. Pre-1.0 package with no public release tags so no
  existing consumers are affected by the floor raise.
- **1.0.0** (2026-04-17): Initial constitution. Seven core principles, narrow
  threat-model framing, runtime-dependency allowlist, best-effort upstream
  tracking, two-tier test determinism, normative platform scope, pre-1.0 stability
  posture, BDFL governance with security-relevant change protocol.

---

## Appendix: Principle Mapping

This constitution organizes Tor-ecosystem concerns as follows:

- Tor-standards alignment, protocol scope, dependency hygiene → **Principle I**
- Metadata leakage, honest anonymity claims, default-posture hardening → **Principle II**
- Onion-service keys, control authentication, bridge credentials → **Principle III**
- Concurrency model, typed errors, safe-by-default API surface → **Principle IV**
- Spec-first workflow, parser/state-machine TDD, control-protocol fixtures → **Principle V**
- Platform matrix, deterministic vs env-gated tests, upstream sync, Vendor discipline → **Principle VI**
- README / CONTRIBUTING / SECURITY / LICENSE, docs, examples, contributor UX → **Principle VII**
- Vulnerability disclosure, Tor Project coordination → **Implementation Guidance**
- Stability posture, amendment process, enforcement tiers → **Governance**

**Version**: 1.1.0 | **Ratified**: 2026-04-17 | **Last Amended**: 2026-04-23
