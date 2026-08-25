#import "PSConfig.h"

static NSString *const kPrefsPath =
    @"/var/jb/var/mobile/Library/Preferences/com.romeo.pseudonym.plist";

static NSDictionary *PSPrefs(void) {
    static NSDictionary *prefs;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        // Read once per process. The tweak runs inside the host app's sandbox,
        // so this can legitimately fail; every accessor degrades to "inactive".
        prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    });
    return prefs;
}

// One depth counter per thread. Any hook that reads configuration wraps the
// read in Enter/Leave; a nested hook firing during that read sees depth > 0 and
// bails to the original function instead of recursing back into config.
static __thread int psHookDepth = 0;

BOOL PSHookReentered(void) { return psHookDepth > 0; }
void PSHookEnter(void) { psHookDepth++; }
void PSHookLeave(void) { if (psHookDepth > 0) psHookDepth--; }

NSString *PSConfigBundleID(void) {
    return [[NSBundle mainBundle] bundleIdentifier];
}

static NSDictionary *PSAppEntry(void) {
    NSString *bundleID = PSConfigBundleID();
    if (!bundleID.length) return nil;
    NSDictionary *apps = PSPrefs()[@"Apps"];
    return [apps isKindOfClass:[NSDictionary class]] ? apps[bundleID] : nil;
}

// Bundles that must never be touched: Apple's own, and the jailbreak's package
// managers and tools. Hiding jailbreak files from these breaks them outright.
static BOOL PSIsProtectedBundle(NSString *bundleID) {
    if ([bundleID hasPrefix:@"com.apple."]) return YES;

    static NSSet *protectedApps;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        protectedApps = [NSSet setWithArray:@[
            @"org.coolstar.SileoStore",   // Sileo
            @"xyz.willy.Zebra",           // Zebra
            @"com.saurik.Cydia",          // Cydia
            @"com.tigisoftware.Filza",    // Filza
            @"ws.hbang.Terminal",         // NewTerm
            @"com.opa334.Dopamine",       // Dopamine
            @"com.romeo.pseudonyminspector", // our own inspector reads truth
        ]];
    });
    return [protectedApps containsObject:bundleID];
}

BOOL PSConfigActive(void) {
    static BOOL active;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSString *bundleID = PSConfigBundleID();

        // Never touch Apple's own processes, or the jailbreak's own apps.
        // Spoofing identifiers inside SpringBoard or the App Store breaks
        // activation and push; hiding jailbreak files from Sileo, Zebra or a
        // terminal makes them unable to find their own files under /var/jb and
        // they stop launching. Neither has any reason to be spoofed.
        if (!bundleID.length || PSIsProtectedBundle(bundleID)) {
            active = NO;
            return;
        }

        NSDictionary *prefs = PSPrefs();
        if (![prefs[@"Enabled"] boolValue] || PSConfigSeed().length < 16) {
            active = NO;
            return;
        }
        active = [PSAppEntry()[@"Enabled"] boolValue];
    });
    return active;
}

NSData *PSConfigSeed(void) {
    static NSData *seed;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSString *encoded = PSPrefs()[@"Seed"];
        if ([encoded isKindOfClass:[NSString class]]) {
            seed = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
        }
    });
    return seed;
}

NSInteger PSConfigGeneration(void) {
    return [PSAppEntry()[@"Generation"] integerValue];
}

BOOL PSConfigLocationEnabled(void) {
    return [PSPrefs()[@"LocationEnabled"] boolValue];
}

// Stored as strings so the Settings text fields round-trip exactly what was
// typed. doubleValue yields 0 for anything unparseable, which is a real
// coordinate (off West Africa), so an explicitly missing key is treated as
// disabled by the caller rather than silently meaning null island.
double PSConfigLatitude(void) {
    return [PSPrefs()[@"Latitude"] doubleValue];
}

double PSConfigLongitude(void) {
    return [PSPrefs()[@"Longitude"] doubleValue];
}

double PSConfigAltitude(void) {
    return [PSPrefs()[@"Altitude"] doubleValue];
}

static NSString *PSString(NSString *key) {
    id value = PSPrefs()[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

BOOL PSConfigProxyEnabled(void) {
    return [PSPrefs()[@"ProxyEnabled"] boolValue];
}

NSString *PSConfigProxyHost(void) {
    return PSString(@"ProxyHost");
}

NSInteger PSConfigProxyPort(void) {
    return [PSString(@"ProxyPort") integerValue];
}

NSString *PSConfigProxyUser(void) {
    return PSString(@"ProxyUser");
}

// Stored in the same plist as everything else: mode 600 and owned by mobile, but
// plaintext. Anything running as mobile on a jailbroken device can read it, so
// this is not the place for credentials that matter elsewhere.
NSString *PSConfigProxyPassword(void) {
    return PSString(@"ProxyPassword");
}

NSString *PSConfigTimeZone(void) {
    id value = PSPrefs()[@"TimeZone"];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

BOOL PSConfigCloakEnabled(void) {
    return [PSPrefs()[@"CloakEnabled"] boolValue];
}

BOOL PSConfigDyldHideEnabled(void) {
    return [PSPrefs()[@"DyldHideEnabled"] boolValue];
}
