# Phase 1: Linux Basic Support

**Status**: 🔄 In Progress  
**Priority**: High  
**Last Updated**: 2025-01-26

---

## Objective

Enable swift-tor to build and run on Linux using the swift:6.1-jammy Docker image.

---

## Current State

Linux build now passes with the following workarounds:

### Changes Made

| File | Change |
|------|--------|
| `Sources/libtor/include/orconfig.h` | Conditional `#undef` for `HAVE_MEMSET_S`, `HAVE_EVUTIL_SECURE_RNG_ADD_BYTES`, `HAVE_ISSETUGID` on Linux |
| `Sources/Tor/Control/ControlSocket.swift` | Platform-specific types: `tv_usec` (Int vs Int32), `SOCK_STREAM` (rawValue) |
| `Sources/TorDemo/Demo.swift` | `#if canImport(CFNetwork)` guard for URLSession code |
| `Package.swift` | Added `_GNU_SOURCE`, `-include bsd/string.h`, linked `libbsd` |
| `Dockerfile` | Removed explicit `clang` install, added `libbsd-dev` |

### Current Dependencies

- `libbsd-dev` (apt package) - provides `strlcpy`, `strlcat`
- `-include bsd/string.h` compiler flag - force-includes BSD string header
- `-lbsd` linker flag - links libbsd library

---

## Issues & Workarounds

### 1. strlcpy/strlcat Not Declared

**Problem**: Tor code calls `strlcpy`/`strlcat` which are BSD functions not in glibc.

**Current Workaround**: 
- Install `libbsd-dev`
- Use `.unsafeFlags(["-include", "bsd/string.h"])` in Package.swift
- Link with `-lbsd`

**Planned Fix** (Phase 2):
- Copy `ext/strlcpy.c` and `ext/strlcat.c` from `Vendor/tor/src/ext/` to `Sources/libtor/src/ext/`
- Undefine `HAVE_STRLCPY` and `HAVE_STRLCAT` on Linux in `orconfig.h`
- Tor's `compat_string.c` will then `#include "ext/strlcpy.c"` automatically

### 2. memmem Not Declared

**Problem**: `memmem` is a GNU extension requiring `_GNU_SOURCE`.

**Fix**: Added `.define("_GNU_SOURCE", .when(platforms: [.linux]))` to Package.swift.

### 3. memset_s Not Available

**Problem**: `memset_s` is C11 Annex K, not available on Linux glibc.

**Fix**: Conditional `#undef HAVE_MEMSET_S` for Linux in `orconfig.h`.

### 4. evutil_secure_rng_add_bytes Not Available

**Problem**: swift-event's libevent build doesn't expose this function.

**Fix**: Conditional `#undef HAVE_EVUTIL_SECURE_RNG_ADD_BYTES` for Linux in `orconfig.h`.

### 5. issetugid Not Available

**Problem**: BSD function not in standard Linux libc.

**Fix**: Conditional `#undef HAVE_ISSETUGID` for Linux in `orconfig.h`.

### 6. Swift Type Differences

**Problem**: `timeval.tv_usec` is `Int` on Linux, `Int32` on macOS. `SOCK_STREAM` is enum on Linux.

**Fix**: Conditional compilation in `ControlSocket.swift`.

### 7. URLSession SOCKS Proxy

**Problem**: `URLSession` SOCKS proxy configuration requires `CFNetwork` (Apple only).

**Fix**: Wrapped demo code in `#if canImport(CFNetwork)`.

---

## Completion Criteria

- [x] `docker build .` passes
- [x] `swift build` passes in container
- [x] `swift test` passes in container
- [ ] Remove `libbsd` dependency (Phase 2)
- [ ] CI workflow added (Phase 3)

---

## Next Steps

→ **Phase 2**: Remove libbsd dependency by using tor's internal strlcpy/strlcat
