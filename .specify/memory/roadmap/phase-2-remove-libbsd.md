# Phase 2: Remove libbsd Dependency

**Status**: 🔜 Planned  
**Priority**: High  
**Last Updated**: 2025-01-26  
**Depends On**: Phase 1 (Linux Basic Support)

---

## Objective

Remove the `libbsd` dependency on Linux by using Tor's internal `strlcpy`/`strlcat` implementations from `Vendor/tor/src/ext/`.

---

## Motivation

The current Linux build uses these workarounds in `Package.swift`:

```swift
// Linux: Force-include BSD string functions header for strlcpy/strlcat
.unsafeFlags(["-include", "bsd/string.h"], .when(platforms: [.linux])),
```

```swift
.linkedLibrary("bsd", .when(platforms: [.linux])), // libbsd for strlcpy/strlcat
```

**Problems with current approach**:
1. `.unsafeFlags` prevents package from being used as a dependency (SPM restriction)
2. Requires `libbsd-dev` apt package in Docker/CI
3. Extra runtime dependency (`libbsd.so`)

**Benefits of using tor's internal implementations**:
1. No `.unsafeFlags` needed - package can be a normal dependency
2. No `libbsd-dev` required in Docker/CI
3. Self-contained build with zero extra runtime dependencies
4. Matches how tor upstream handles this (conditional include)

---

## Implementation Plan

### Step 1: Copy ext files from Vendor to Sources

Copy these files from `Vendor/tor/src/ext/` to `Sources/libtor/src/ext/`:

| File | Size | License |
|------|------|---------|
| `strlcpy.c` | 61 lines | BSD (OpenBSD, Todd C. Miller) |
| `strlcat.c` | 71 lines | BSD (OpenBSD, Todd C. Miller) |

### Step 2: Update orconfig.h

Add Linux conditionals to disable system strlcpy/strlcat:

```c
/* Define to 1 if you have the 'strlcpy' function. */
#if defined(__linux__)
/* Use tor's internal implementation from ext/strlcpy.c */
#undef HAVE_STRLCPY
#else
#define HAVE_STRLCPY 1
#endif

/* Define to 1 if you have the 'strlcat' function. */
#if defined(__linux__)
/* Use tor's internal implementation from ext/strlcat.c */
#undef HAVE_STRLCAT
#else
#define HAVE_STRLCAT 1
#endif
```

### Step 3: Update Package.swift

Remove these lines:

```swift
// REMOVE: .unsafeFlags(["-include", "bsd/string.h"], .when(platforms: [.linux])),
// REMOVE: .linkedLibrary("bsd", .when(platforms: [.linux])),
```

Keep:
```swift
.define("_GNU_SOURCE", .when(platforms: [.linux])),  // Still needed for memmem
```

### Step 4: Update Dockerfile

Remove `libbsd-dev` from apt packages:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        pkg-config \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
```

### Step 5: Verify

1. Run `docker build .` - should pass without libbsd
2. Run macOS build - should still pass (uses system strlcpy/strlcat)
3. Verify no `.unsafeFlags` remain in Package.swift

---

## How It Works

The mechanism is already built into tor's codebase:

```c
// Sources/libtor/src/lib/string/compat_string.c
#ifndef HAVE_STRLCPY
#include "ext/strlcpy.c"
#endif
#ifndef HAVE_STRLCAT
#include "ext/strlcat.c"
#endif
```

When `HAVE_STRLCPY` is undefined, `compat_string.c` directly includes the implementation. This is an inline include pattern - no separate compilation unit needed.

---

## Files to Modify

| File | Action |
|------|--------|
| `Sources/libtor/src/ext/strlcpy.c` | **Create** (copy from Vendor) |
| `Sources/libtor/src/ext/strlcat.c` | **Create** (copy from Vendor) |
| `Sources/libtor/include/orconfig.h` | **Modify** (add Linux conditionals) |
| `Package.swift` | **Modify** (remove unsafeFlags and libbsd) |
| `Dockerfile` | **Modify** (remove libbsd-dev) |

---

## Completion Criteria

- [ ] `strlcpy.c` and `strlcat.c` copied to `Sources/libtor/src/ext/`
- [ ] `orconfig.h` updated with Linux conditionals
- [ ] `Package.swift` has no `.unsafeFlags`
- [ ] `Package.swift` has no `libbsd` linker setting
- [ ] `Dockerfile` has no `libbsd-dev`
- [ ] `docker build .` passes
- [ ] macOS `swift test` passes
- [ ] Package can be used as a normal SPM dependency

---

## Risk Assessment

**Low Risk**: This is exactly how tor upstream handles platforms without strlcpy/strlcat. The implementation files are well-tested OpenBSD code (BSD licensed, compatible with MIT).
