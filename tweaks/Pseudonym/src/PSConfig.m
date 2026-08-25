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

NSString *PSConfigBundleID(void) {
    return [[NSBundle mainBundle] bundleIdentifier];
}

static NSDictionary *PSAppEntry(void) {
    NSString *bundleID = PSConfigBundleID();
    if (!bundleID.length) return nil;
    NSDictionary *apps = PSPrefs()[@"Apps"];
    return [apps isKindOfClass:[NSDictionary class]] ? apps[bundleID] : nil;
}

BOOL PSConfigActive(void) {
    static BOOL active;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSString *bundleID = PSConfigBundleID();

        // Never touch Apple's own processes. Spoofing identifiers inside
        // SpringBoard, the App Store or system services breaks activation,
        // push and iCloud in ways that are tedious to unpick.
        if (!bundleID.length || [bundleID hasPrefix:@"com.apple."]) {
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
