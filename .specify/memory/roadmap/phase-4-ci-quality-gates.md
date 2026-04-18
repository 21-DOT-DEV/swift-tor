# Phase 4: CI & Quality Gates

**Status**: ✅ Complete  
**Priority**: High  
**Last Updated**: 2026-04-17  
**Depends On**: Phase 1 (Linux Basic Support), Phase 2 (Remove libbsd)

---

## Objective

Establish continuous integration coverage for every supported platform per constitution Principle VI (Cross-Platform CI & Quality Gates), with deterministic tests gating every PR.

---

## Features

| Feature | Purpose & User Value | Success Metrics | Dependencies | Notes |
|---------|----------------------|-----------------|--------------|-------|
| **Apple Platforms CI** | macOS build+test + iOS build on every push/PR to `main`. Catches platform regressions before merge. | `apple-builds.yml` passes on macos-15 runner; iOS builds via `xcodebuild -destination generic/platform=iOS`. | — | File: `.github/workflows/apple-builds.yml:10-29`. |
| **Linux Docker CI** | Linux build+test via `docker build .` on ubuntu-latest runner. Validates `swift:6.1-jammy` + `Dockerfile` pipeline. | `docker-builds.yml` passes without `libbsd-dev` present. | Phase 2 (libbsd removed) | File: `.github/workflows/docker-builds.yml:9-16`. |
| **Deterministic-Tier Gate** | Per Constitution Principle VI, deterministic unit + parser + config-validation tests gate every PR; live-network integration tests are env-gated. | Default CI runs no Tor bootstrap; all gating tests complete in seconds. | — | Current implementation: tests in `Tests/TorTests/` are deterministic. No env-gated integration tier yet defined, but the discipline is established. |

---

## Sequencing

All features shipped in parallel as a single CI workflow pair. Platform matrix was green by the time Phase 2 merged.

---

## Phase-Level Metrics

| Metric | Target | Status |
|--------|--------|--------|
| macOS build & test | Pass in CI | ✅ |
| iOS build | Pass in CI | ✅ |
| Linux build & test | Pass in CI | ✅ |
| CI latency (PR → merge gate) | < 15 minutes | ✅ (approximate) |

---

## Completion Evidence (verified 2026-04-17)

- `.github/workflows/apple-builds.yml:10-17` — `macos` job runs `swift test` on `macos-15`.
- `.github/workflows/apple-builds.yml:18-29` — `ios` job runs `xcrun xcodebuild build -scheme swift-tor-Package -destination generic/platform=iOS`.
- `.github/workflows/docker-builds.yml:9-16` — `linux` job runs `docker build .` on `ubuntu-latest`, which executes `swift build && swift test` inside the container per `Dockerfile:18-19`.

All three workflows trigger on `push` to `main` and `pull_request` targeting `main`.

---

## Risks / Open Questions

- **No scheduled integration-test cadence yet**: Constitution Principle VI says env-gated live-network tests SHOULD run on a schedule and surface failures separately. Not yet implemented; leave as a future enhancement.
- **No deterministic-tier formalization**: there's no explicit separation in the test target between deterministic and env-gated tests. Formalize when an env-gated test is first added.

---

## Completion Note (2026-04-17)

Ongoing maintenance only. Any future workflow changes are scoped per the relevant phase (e.g., Phase 3.5 Binary Size may need a release-configuration job; Phase 7/8 may need a bootstrap integration job).
