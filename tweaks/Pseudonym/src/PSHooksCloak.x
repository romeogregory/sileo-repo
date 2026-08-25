#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <unistd.h>
#import <stdio.h>
#import <stdarg.h>
#import <fcntl.h>
#import <string.h>
#import <errno.h>
#import "PSConfig.h"

// Best-effort jailbreak hiding: the checks apps commonly use - jailbreak files,
// fork, package-manager URL schemes, the injection env var - answered the way a
// stock device would. Not invisibility; attestation and implementation-address
// checks still see through it.
//
// SAFETY, and the reason this whole file was rebuilt: the hooks install ONLY in
// an app that is actually opted in, from a %ctor gated on PSConfigActive().
// With nothing enabled, none of this code exists in any process - not
// SpringBoard, not Sileo, not the app you just installed. Earlier builds
// installed these process-wide, so a fault reached the whole device even with
// every switch off. That can no longer happen.
extern void MSHookFunction(void *symbol, void *replacement, void **result);
extern void MSHookMessageEx(Class cls, SEL selector, IMP imp, IMP *result);

static BOOL PSCloakActiveRaw(void) {
    return PSConfigActive() && PSConfigCloakEnabled();
}

// Guarded gate. If already inside a hook on this thread - which happens when
// config's own file read re-enters open/stat - return NO without touching
// config. Breaks the reentrancy that deadlocked earlier builds.
static BOOL PSCloakActive(void) {
    if (PSHookReentered()) return NO;
    PSHookEnter();
    BOOL active = PSCloakActiveRaw();
    PSHookLeave();
    return active;
}

// Only clearly non-stock paths, and never our own preferences - hiding those
// from ourselves would break the gate that controls this.
static BOOL PSPathIsJailbreakTell(const char *path) {
    if (!path) return NO;
    if (strstr(path, "com.romeo.")) return NO;

    static const char *tells[] = {
        "/var/jb", "/Applications/Cydia.app", "/Applications/Sileo.app",
        "/Applications/Zebra.app", "/usr/sbin/sshd", "/usr/bin/ssh",
        "/bin/bash", "/bin/sh", "/etc/apt", "/private/var/lib/apt",
        "/usr/lib/libjailbreak.dylib", "/usr/libexec/ellekit",
        "/usr/libexec/sileo", "/Library/MobileSubstrate", "/var/lib/dpkg",
        "/var/lib/cydia", "/.installed_unc0ver", "/.bootstrapped",
        "/taurine", "/palera1n", "/checkra1n",
    };
    for (size_t i = 0; i < sizeof(tells) / sizeof(tells[0]); i++) {
        if (strstr(path, tells[i])) return YES;
    }
    return NO;
}

#pragma mark - C hooks

static int (*o_stat)(const char *, struct stat *);
static int (*o_lstat)(const char *, struct stat *);
static int (*o_access)(const char *, int);
static FILE *(*o_fopen)(const char *, const char *);
static int (*o_open)(const char *, int, ...);
static pid_t (*o_fork)(void);
static char *(*o_getenv)(const char *);

static int h_stat(const char *path, struct stat *buf) {
    if (PSCloakActive() && PSPathIsJailbreakTell(path)) { errno = ENOENT; return -1; }
    return o_stat(path, buf);
}

static int h_lstat(const char *path, struct stat *buf) {
    if (PSCloakActive() && PSPathIsJailbreakTell(path)) { errno = ENOENT; return -1; }
    return o_lstat(path, buf);
}

static int h_access(const char *path, int mode) {
    if (PSCloakActive() && PSPathIsJailbreakTell(path)) { errno = ENOENT; return -1; }
    return o_access(path, mode);
}

static FILE *h_fopen(const char *path, const char *mode) {
    if (PSCloakActive() && PSPathIsJailbreakTell(path)) { errno = ENOENT; return NULL; }
    return o_fopen(path, mode);
}

// open is variadic. On arm64 the creation mode arrives as a stack arg, so it
// must be read with va_arg and forwarded; a fixed third parameter would read
// the wrong register and corrupt file creation.
static int h_open(const char *path, int flags, ...) {
    if (PSCloakActive() && PSPathIsJailbreakTell(path)) { errno = ENOENT; return -1; }
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode_t mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        return o_open(path, flags, mode);
    }
    return o_open(path, flags);
}

static pid_t h_fork(void) {
    if (PSCloakActive()) { errno = EPERM; return -1; }
    return o_fork();
}

static char *h_getenv(const char *name) {
    if (PSCloakActive() && name && strcmp(name, "DYLD_INSERT_LIBRARIES") == 0) {
        return NULL;
    }
    return o_getenv(name);
}

#pragma mark - Objective-C hooks

static BOOL (*o_fileExists)(id, SEL, NSString *);
static BOOL (*o_fileExistsIsDir)(id, SEL, NSString *, BOOL *);
static BOOL (*o_canOpenURL)(id, SEL, NSURL *);

static BOOL h_fileExists(id self, SEL _cmd, NSString *path) {
    if (PSCloakActive() && path &&
        PSPathIsJailbreakTell(path.fileSystemRepresentation)) {
        return NO;
    }
    return o_fileExists(self, _cmd, path);
}

static BOOL h_fileExistsIsDir(id self, SEL _cmd, NSString *path, BOOL *isDir) {
    if (PSCloakActive() && path &&
        PSPathIsJailbreakTell(path.fileSystemRepresentation)) {
        if (isDir) *isDir = NO;
        return NO;
    }
    return o_fileExistsIsDir(self, _cmd, path, isDir);
}

static BOOL h_canOpenURL(id self, SEL _cmd, NSURL *url) {
    if (PSCloakActive() && url.scheme) {
        static NSSet *schemes;
        static dispatch_once_t token;
        dispatch_once(&token, ^{
            schemes = [NSSet setWithArray:@[@"cydia", @"sileo", @"zbra",
                                            @"filza", @"activator", @"undecimus"]];
        });
        if ([schemes containsObject:url.scheme.lowercaseString]) return NO;
    }
    return o_canOpenURL(self, _cmd, url);
}

%ctor {
    // Install ONLY where an app is actually opted in. With nothing enabled this
    // returns before hooking anything, so Settings, Sileo and non-enabled apps
    // receive none of these hooks. The config read is guarded so it cannot
    // deadlock against the hooks being installed.
    // Gate installation on the switch too, not just app-enablement. Turning
    // Hide Jailbreak off must actually remove these hooks on next launch -
    // leaving the trampolines installed but passing through is still detectable
    // by an app that inspects its own functions, which made the switch feel
    // like it did nothing.
    PSHookEnter();
    BOOL install = PSConfigActive() && PSConfigCloakEnabled();
    PSHookLeave();
    if (!install) return;

    MSHookFunction((void *)&stat,   (void *)h_stat,   (void **)&o_stat);
    MSHookFunction((void *)&lstat,  (void *)h_lstat,  (void **)&o_lstat);
    MSHookFunction((void *)&access, (void *)h_access, (void **)&o_access);
    MSHookFunction((void *)&fopen,  (void *)h_fopen,  (void **)&o_fopen);
    MSHookFunction((void *)&open,   (void *)h_open,   (void **)&o_open);
    MSHookFunction((void *)&fork,   (void *)h_fork,   (void **)&o_fork);
    MSHookFunction((void *)&getenv, (void *)h_getenv, (void **)&o_getenv);

    MSHookMessageEx([NSFileManager class], @selector(fileExistsAtPath:),
                    (IMP)h_fileExists, (IMP *)&o_fileExists);
    MSHookMessageEx([NSFileManager class], @selector(fileExistsAtPath:isDirectory:),
                    (IMP)h_fileExistsIsDir, (IMP *)&o_fileExistsIsDir);
    MSHookMessageEx([UIApplication class], @selector(canOpenURL:),
                    (IMP)h_canOpenURL, (IMP *)&o_canOpenURL);
}
