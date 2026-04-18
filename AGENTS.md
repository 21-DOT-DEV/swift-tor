# AGENTS.md (swift-tor)

A Swift 6.1 wrapper around the Tor daemon (`libtor`) providing a Swift-concurrency-first API (`TorClient`) and Tor control protocol utilities. Supports macOS 13+, iOS 16+, and Linux (Ubuntu 22.04+). Does NOT support tvOS/watchOS/visionOS: Tor's codebase relies on UNIX process primitives (`fork`, `execve`, `daemon`, `setuid`) prohibited by Apple on those platforms.

## Commands

- Build: `swift build`
- Test: `swift test`
- Integration tests: `TOR_INTEGRATION_TESTS=1 swift test --filter IntegrationTests`
- Demo: `swift run TorDemo`
- Linux build: `docker build .`

## Non-obvious patterns

- **Conditional dev deps**: `Package.swift` uses `Context.gitInformation?.currentTag` to exclude `swift-plugin-subtree` at tagged releases. Consumers resolving a tagged version get zero transitive dev dependencies; runtime deps (swift-openssl, swift-event) stay inline and always resolve.
- **Extraction flow**: Tor upstream is extracted via `subtree.yaml` (remote `gitlab.torproject.org/tpo/core/tor`, tag `tor-0.4.8.21`). `Vendor/tor` → `Sources/libtor/`. Do NOT edit `Sources/libtor/src/**` directly; changes are overwritten on the next extraction. Manually maintained files are listed in `subtree.yaml` comments.
- **Forbidden platforms**: tvOS/watchOS/visionOS crash at runtime due to App Store-prohibited UNIX primitives. Never add them to `platforms:` in `Package.swift` or to CI build matrices.
- **Runtime Swift deps**: `libtor` links `libcrypto`, `libssl` (from swift-openssl), and `libevent` (from swift-event). These are runtime deps and must never move into `developmentDependencies`.
- **iOS __clear_cache shim**: `Sources/libtor/Shims/clear_cache_shim.c` is required on iOS. Do not remove.
- **Integration tests env-gated**: IntegrationTests require live Tor network access; they are skipped unless `TOR_INTEGRATION_TESTS=1`.

## Boundaries

- **Never**: edit files under `Vendor/**` directly; log onion-service private keys or control-port passwords; broaden CI permissions without justification; re-enable tvOS/watchOS/visionOS.
- **Ask first**: add new third-party dependencies; modify `subtree.yaml` extraction patterns.
- See the [21-DOT-DEV contributing guidelines](https://github.com/21-DOT-DEV/.github/blob/main/CONTRIBUTING.md) for branching and commit guidelines. See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## Scoped guidance

Directory-specific `AGENTS.md` files provide additional context:

- `.github/AGENTS.md` — CI workflows and Actions security policy
- `Vendor/AGENTS.md` — vendored Tor sources and subtree sync rules

## Maintenance

- Keep scoped `AGENTS.md` files limited to deltas; avoid duplicating root guidance.
- Update when build/test workflows, toolchain versions, or platform support changes.
