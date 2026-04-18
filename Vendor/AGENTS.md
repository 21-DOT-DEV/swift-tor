# AGENTS.md (Vendor)

This directory contains vendored Tor sources managed by `subtree.yaml`.

## Boundaries (strict)

- Do not edit files under `Vendor/**` unless explicitly asked to patch vendored code.
- Prefer updating vendored code via the subtree CLI rather than manual edits.
- If you need to change behavior, prefer making the change upstream and then updating the subtree.

## If you must patch (explicit request only)

- Keep changes minimal and tightly scoped.
- Avoid reformatting, renaming, or sweeping refactors.
- Verify the subtree entry in `subtree.yaml` (remote / tag / commit) before editing.
- Ensure changes remain upstream-syncable against the `tor-0.4.8.x` line.

## Extractions (Vendor → Sources)

The subtree CLI uses `subtree.yaml` to extract filtered sources from Vendor into the Swift target:

- `Vendor/tor` → `Sources/libtor/` (glob: `src/{lib,core,feature,app,trunnel,ext}/**/*.{c,h,inc}` with excludes defined in `subtree.yaml`)

### Manually maintained (not extracted)

These files live under `Sources/libtor/` but are not produced by extraction. Do not expect them to appear in `Vendor/tor`.

- `Sources/libtor/include/orconfig.h` — cross-platform config for macOS / Linux / iOS
- `Sources/libtor/include/libtor.h` — Swift bindings header
- `Sources/libtor/include/tor_api.h` — public API header (copied from Vendor)
- `Sources/libtor/Shims/clear_cache_shim.c` — iOS `__clear_cache` shim
- `Sources/libtor/src/lib/version/micro-revision.i` — version stub
- `Sources/libtor/src/app/main/tor_main_loop.c` — `main.c` without `main()`
