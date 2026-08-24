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
