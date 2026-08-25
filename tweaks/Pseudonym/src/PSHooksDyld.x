#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <string.h>
#import "PSConfig.h"

// Hides injected images from the loaded-dylib list - the check that sees
// Pseudonym.dylib sitting in the process by name, which the file-based cloak
// cannot touch. Separate switch from the file cloak because it is the riskier
// of the two: the four dyld enumeration functions share one index space, and
// if they disagree about it the app crashes.
//
// ellekit exports MSHookFunction; declared here rather than pulling in
// substrate.h, which is not reliably present in the SDK. The tweak already
// links the substrate shim via %hook, so the symbol resolves at load.
extern void MSHookFunction(void *symbol, void *replacement, void **result);

static uint32_t (*o_dyld_count)(void);
static const char *(*o_dyld_name)(uint32_t);
static const struct mach_header *(*o_dyld_header)(uint32_t);
static intptr_t (*o_dyld_slide)(uint32_t);

static BOOL PSDyldHideActive(void) {
    return PSConfigActive() && PSConfigDyldHideEnabled();
}

// Only clearly-injected images. Hiding a system library would desync the list
// and crash the app, so the match is deliberately narrow and never touches the
// shared cache or the main executable.
static BOOL PSImageHidden(const char *name) {
    if (!name) return NO;
    return strstr(name, "Pseudonym.dylib")
        || strstr(name, "/MobileSubstrate/DynamicLibraries/")
        || strstr(name, "/TweakInject/")
        || strstr(name, "ellekit")
        || strstr(name, "libhooker")
        || strstr(name, "libsubstitute")
        || strstr(name, "CydiaSubstrate");
}

// Map an index the app sees to a real dyld index, skipping hidden images. All
// four hooks below route through this one function, which is what keeps their
// view of the list consistent. UINT32_MAX means past the end, which is exactly
// what real dyld reports for an out-of-range index.
static uint32_t PSMapIndex(uint32_t visibleIndex) {
    uint32_t real = o_dyld_count();
    uint32_t seen = 0;
    for (uint32_t i = 0; i < real; i++) {
        if (PSImageHidden(o_dyld_name(i))) continue;
        if (seen == visibleIndex) return i;
        seen++;
    }
    return UINT32_MAX;
}

static uint32_t h_dyld_count(void) {
    if (!PSDyldHideActive()) return o_dyld_count();
    uint32_t real = o_dyld_count(), hidden = 0;
    for (uint32_t i = 0; i < real; i++) {
        if (PSImageHidden(o_dyld_name(i))) hidden++;
    }
    return real - hidden;
}

static const char *h_dyld_name(uint32_t index) {
    if (!PSDyldHideActive()) return o_dyld_name(index);
    uint32_t real = PSMapIndex(index);
    return real == UINT32_MAX ? NULL : o_dyld_name(real);
}

static const struct mach_header *h_dyld_header(uint32_t index) {
    if (!PSDyldHideActive()) return o_dyld_header(index);
    uint32_t real = PSMapIndex(index);
    return real == UINT32_MAX ? NULL : o_dyld_header(real);
}

static intptr_t h_dyld_slide(uint32_t index) {
    if (!PSDyldHideActive()) return o_dyld_slide(index);
    uint32_t real = PSMapIndex(index);
    // Real dyld returns 0 for an out-of-range slide, not an error.
    return real == UINT32_MAX ? 0 : o_dyld_slide(real);
}

%ctor {
    // Only install in a process that is actually being spoofed. This is not an
    // optimisation - it is why 2.1.0 crashed Settings.
    //
    // The main tweak injects into everything linking UIKit, Settings included.
    // Hooking the dyld enumeration family is special: even a gated pass-through
    // routes every call through our trampoline, and these functions run while
    // dyld holds its loader lock. The gate's first call does a file read, and
    // doing that under the loader lock deadlocks or crashes the process. So the
    // hooks must never exist in Settings or any Apple process. PSConfigActive()
    // is false for com.apple.* and for apps not opted in, which is exactly the
    // set that must stay untouched.
    // Guard the config reads: with the cloak's open/stat hooks installed, these
    // reads open a file and would otherwise re-enter those hooks and deadlock.
    PSHookEnter();
    BOOL active = PSConfigActive();
    (void)PSConfigDyldHideEnabled();  // warm the cache on this stack
    PSHookLeave();
    if (!active) return;

    // The four are hooked together or not at all - a partial install would be
    // the index desync that crashes.
    MSHookFunction((void *)&_dyld_image_count,
                   (void *)h_dyld_count, (void **)&o_dyld_count);
    MSHookFunction((void *)&_dyld_get_image_name,
                   (void *)h_dyld_name, (void **)&o_dyld_name);
    MSHookFunction((void *)&_dyld_get_image_header,
                   (void *)h_dyld_header, (void **)&o_dyld_header);
    MSHookFunction((void *)&_dyld_get_image_vmaddr_slide,
                   (void *)h_dyld_slide, (void **)&o_dyld_slide);
}
