#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <errno.h>
#import "PSConfig.h"
#import "PSIdentity.h"

// Writes `value` into a sysctl caller's buffer using the kernel's own
// contract: report the required size, and fail with ENOMEM when it won't fit.
static int PSCopyOut(const char *value, void *oldp, size_t *oldlenp) {
    size_t needed = strlen(value) + 1;
    if (!oldp) {
        *oldlenp = needed;
        return 0;
    }
    if (*oldlenp < needed) {
        *oldlenp = needed;
        errno = ENOMEM;
        return -1;
    }
    strlcpy((char *)oldp, value, *oldlenp);
    *oldlenp = needed;
    return 0;
}

%hookf(int, sysctlbyname, const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!PSConfigActive() || !name || !oldlenp || newp) return %orig;

    PSProfile profile = PSIdentityProfile();

    if (strcmp(name, "hw.machine") == 0) {
        return PSCopyOut(profile.machine, oldp, oldlenp);
    }
    if (strcmp(name, "hw.model") == 0) {
        // Read from the same profile entry as hw.machine, so the two can never
        // contradict one another.
        return PSCopyOut(profile.board, oldp, oldlenp);
    }

    return %orig;
}

%hookf(int, uname, struct utsname *buf) {
    int result = %orig;
    if (result != 0 || !PSConfigActive() || !buf) return result;

    // uname() is the other well-known route to the model string.
    PSProfile profile = PSIdentityProfile();
    strlcpy(buf->machine, profile.machine, sizeof(buf->machine));
    return result;
}
