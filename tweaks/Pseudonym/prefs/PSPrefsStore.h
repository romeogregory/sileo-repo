#import <Foundation/Foundation.h>

// The tweak reads a plain plist rather than a CFPreferences domain, because it
// has to be readable from inside every hooked app's sandbox. The UI therefore
// has to read and write that same file directly instead of going through
// NSUserDefaults.
//
// Every write is read-modify-write on the whole dictionary: the Seed lives in
// there too, and clobbering it would silently re-roll every app's identity.
@interface PSPrefsStore : NSObject

+ (NSMutableDictionary *)load;
+ (BOOL)save:(NSDictionary *)prefs;

+ (BOOL)globalEnabled;
+ (void)setGlobalEnabled:(BOOL)enabled;

+ (BOOL)enabledForApp:(NSString *)bundleID;
+ (void)setEnabled:(BOOL)enabled forApp:(NSString *)bundleID;

+ (NSInteger)generationForApp:(NSString *)bundleID;
+ (void)bumpGenerationForApp:(NSString *)bundleID;
+ (NSInteger)bumpAllEnabledGenerations;

@end
