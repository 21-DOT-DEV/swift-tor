/* Shim for __clear_cache on iOS where Clang emits a library call
 * rather than inlining the built-in. This is needed for the hashx
 * JIT compiler used by Tor's proof-of-work system.
 *
 * On iOS, JIT is heavily restricted anyway, but this allows the code
 * to link successfully. The actual JIT code path will fail at runtime
 * due to iOS memory protection (W^X), falling back to interpreter mode.
 */

#if defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IOS

#include <libkern/OSCacheControl.h>

void __clear_cache(void *start, void *end) {
    sys_icache_invalidate(start, (char *)end - (char *)start);
}

#endif
#endif
