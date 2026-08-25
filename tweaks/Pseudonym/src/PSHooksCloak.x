#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <unistd.h>
#import <stdio.h>
#import <string.h>
#import <errno.h>
#import "PSConfig.h"

// Best-effort jailbreak hiding. It intercepts the checks apps commonly use -
// looking for jailbreak files, forking, probing package-manager URL schemes -
// and makes them come back the way they would on a stock device.
//
// It is NOT invisibility. A determined check (comparing a method's
// implementation address to its owning image, scanning the loaded dylib list,
// hardware attestation) will still see through it. This raises the floor, it
// does not close the door. Anything sold as undetectable is lying.
//
// Gated per app AND on a separate Hide Jailbreak switch, so it never touches an
// app you did not opt in.
static BOOL PSCloakActiveRaw(void) {
    return PSConfigActive() && PSConfigCloakEnabled();
}

// Guarded gate used by every hook below. If we are already inside a hook on
// this thread - which happens when config's own file read re-enters open/stat -
// return NO without touching config. That is what breaks the deadlock.
static BOOL PSCloakActive(void) {
    if (PSHookReentered()) return NO;
    PSHookEnter();
    BOOL active = PSCloakActiveRaw();
    PSHookLeave();
    return active;
}

// Paths a stock device does not have. Kept specific rather than blanket-hiding
// everything under /var/jb, because this tweak's own preferences live there and
// hiding them from ourselves would break the very config that gates this.
static BOOL PSPathIsJailbreakTell(const char *path) {
    if (!path) return NO;

    // Allowlist first. Our own preferences and anything in com.romeo.* must
    // stay visible or the gate above cannot read its own state.
    if (strstr(path, "com.romeo.")) return NO;

    static const char *tells[] = {
        "/var/jb",
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/usr/sbin/sshd",
        "/usr/bin/ssh",
        "/bin/bash",
        "/bin/sh",
        "/etc/apt",
        "/private/var/lib/apt",
        "/usr/lib/libjailbreak.dylib",
        "/usr/libexec/ellekit",
        "/usr/libexec/sileo",
        "/Library/MobileSubstrate",
        "/var/lib/dpkg",
        "/var/lib/cydia",
        "/.installed_unc0ver",
        "/.bootstrapped",
        "/taurine",
        "/palera1n",
        "/checkra1n",
    };
    for (size_t i = 0; i < sizeof(tells) / sizeof(tells[0]); i++) {
        if (strstr(path, tells[i])) return YES;
    }
    return NO;
}

#pragma mark - C file checks

// The workhorses. Most detection is a stat/access on a known path, so making
// those report "no such file" covers the common case.
%hookf(int, stat, const char *path, struct stat *buf) {
    if (PSCloakActive() && PSPathIsJailbreakTell(path)) {
        errno = ENOENT;
        return -1;
    }
    return %orig;
}

%hookf(int, lstat, const char *path, struct stat *buf) {
    if (PSCloakActive() && PSPathIsJailbreakTell(path)) {
        errno = ENOENT;
        return -1;
    }
    return %orig;
}

%hookf(int, access, const char *path, int mode) {
    if (PSCloakActive() && PSPathIsJailbreakTell(path)) {
        errno = ENOENT;
        return -1;
    }
    return %orig;
}

%hookf(FILE *, fopen, const char *path, const char *mode) {
    if (PSCloakActive() && PSPathIsJailbreakTell(path)) {
        errno = ENOENT;
        return NULL;
    }
    return %orig;
}

%hookf(int, open, const char *path, int flags, ...) {
    if (PSCloakActive() && PSPathIsJailbreakTell(path)) {
        errno = ENOENT;
        return -1;
    }
    // open is variadic: mode only matters when creating, and a blocked path
    // never reaches here, so forwarding without the mode argument is safe.
    return %orig(path, flags);
}

#pragma mark - fork

// A sandboxed app cannot fork; a jailbroken one can. Apps fork purely to see
// whether it succeeds, so returning the sandboxed failure is the honest stock
// answer.
%hookf(pid_t, fork) {
    if (PSCloakActive()) {
        errno = EPERM;
        return -1;
    }
    return %orig;
}

#pragma mark - Objective-C surface

%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    if (PSCloakActive() && path &&
        PSPathIsJailbreakTell(path.fileSystemRepresentation)) {
        return NO;
    }
    return %orig;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (PSCloakActive() && path &&
        PSPathIsJailbreakTell(path.fileSystemRepresentation)) {
        if (isDirectory) *isDirectory = NO;
        return NO;
    }
    return %orig;
}

%end

%hook UIApplication

// canOpenURL: for cydia://, sileo:// and the like reveals a package manager
// without ever touching the filesystem.
- (BOOL)canOpenURL:(NSURL *)url {
    if (PSCloakActive() && url.scheme) {
        static NSSet *schemes;
        static dispatch_once_t token;
        dispatch_once(&token, ^{
            schemes = [NSSet setWithArray:@[@"cydia", @"sileo", @"zbra",
                                            @"filza", @"activator", @"undecimus"]];
        });
        if ([schemes containsObject:url.scheme.lowercaseString]) return NO;
    }
    return %orig;
}

%end

#pragma mark - Environment

%hookf(char *, getenv, const char *name) {
    // DYLD_INSERT_LIBRARIES is how tweaks are injected; its mere presence is a
    // tell, so report it unset.
    if (PSCloakActive() && name && strcmp(name, "DYLD_INSERT_LIBRARIES") == 0) {
        return NULL;
    }
    return %orig;
}
