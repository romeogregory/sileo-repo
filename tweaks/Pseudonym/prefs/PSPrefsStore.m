#import "PSPrefsStore.h"

static NSString *const kPrefsPath =
    @"/var/jb/var/mobile/Library/Preferences/com.romeo.pseudonym.plist";

@implementation PSPrefsStore

+ (NSMutableDictionary *)load {
    NSMutableDictionary *prefs =
        [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath];
    if (!prefs) {
        // postinst normally creates this. If it is missing the Seed is gone
        // too, and inventing one here would hand every app a new identity
        // without the user asking, so leave Seed absent and let the tweak stay
        // inactive until the package is reinstalled.
        prefs = [NSMutableDictionary dictionary];
    }
    if (![prefs[@"Apps"] isKindOfClass:[NSDictionary class]]) {
        prefs[@"Apps"] = [NSMutableDictionary dictionary];
    } else {
        prefs[@"Apps"] = [prefs[@"Apps"] mutableCopy];
    }
    return prefs;
}

+ (BOOL)save:(NSDictionary *)prefs {
    return [prefs writeToFile:kPrefsPath atomically:YES];
}

+ (BOOL)globalEnabled {
    return [[self load][@"Enabled"] boolValue];
}

+ (void)setGlobalEnabled:(BOOL)enabled {
    NSMutableDictionary *prefs = [self load];
    prefs[@"Enabled"] = @(enabled);
    [self save:prefs];
}

+ (NSMutableDictionary *)entryIn:(NSMutableDictionary *)prefs
                          forApp:(NSString *)bundleID {
    NSMutableDictionary *apps = prefs[@"Apps"];
    NSMutableDictionary *entry = [apps[bundleID] mutableCopy];
    if (!entry) {
        entry = [NSMutableDictionary dictionary];
    }
    apps[bundleID] = entry;
    return entry;
}

+ (BOOL)enabledForApp:(NSString *)bundleID {
    return [[self load][@"Apps"][bundleID][@"Enabled"] boolValue];
}

+ (void)setEnabled:(BOOL)enabled forApp:(NSString *)bundleID {
    NSMutableDictionary *prefs = [self load];
    NSMutableDictionary *entry = [self entryIn:prefs forApp:bundleID];
    entry[@"Enabled"] = @(enabled);
    if (!entry[@"Generation"]) {
        entry[@"Generation"] = @0;
    }
    [self save:prefs];
}

+ (NSInteger)generationForApp:(NSString *)bundleID {
    return [[self load][@"Apps"][bundleID][@"Generation"] integerValue];
}

+ (void)bumpGenerationForApp:(NSString *)bundleID {
    NSMutableDictionary *prefs = [self load];
    NSMutableDictionary *entry = [self entryIn:prefs forApp:bundleID];
    entry[@"Generation"] = @([entry[@"Generation"] integerValue] + 1);
    [self save:prefs];
}

+ (NSInteger)bumpAllEnabledGenerations {
    NSMutableDictionary *prefs = [self load];
    NSMutableDictionary *apps = prefs[@"Apps"];
    NSInteger changed = 0;

    for (NSString *bundleID in [apps allKeys]) {
        if (![apps[bundleID][@"Enabled"] boolValue]) continue;
        NSMutableDictionary *entry = [self entryIn:prefs forApp:bundleID];
        entry[@"Generation"] = @([entry[@"Generation"] integerValue] + 1);
        changed++;
    }
    if (changed) [self save:prefs];
    return changed;
}

+ (BOOL)boolForKey:(NSString *)key {
    return [[self load][key] boolValue];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    NSMutableDictionary *prefs = [self load];
    prefs[key] = @(value);
    [self save:prefs];
}

+ (NSString *)stringForKey:(NSString *)key {
    id value = [self load][key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

+ (void)setString:(NSString *)value forKey:(NSString *)key {
    NSMutableDictionary *prefs = [self load];
    if (value.length) {
        prefs[key] = value;
    } else {
        [prefs removeObjectForKey:key];
    }
    [self save:prefs];
}

@end
