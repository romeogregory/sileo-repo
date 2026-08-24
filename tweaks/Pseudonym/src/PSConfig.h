#import <Foundation/Foundation.h>

// Spoofing is OPT-IN per app. An app absent from the prefs plist is untouched,
// so installing this tweak changes nothing until you enable a specific app.
// Apple bundles are refused outright regardless of configuration.
BOOL PSConfigActive(void);

NSData *PSConfigSeed(void);
NSString *PSConfigBundleID(void);
NSInteger PSConfigGeneration(void);
