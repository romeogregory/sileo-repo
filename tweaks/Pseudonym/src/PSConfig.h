#import <Foundation/Foundation.h>

// Spoofing is OPT-IN per app. An app absent from the prefs plist is untouched,
// so installing this tweak changes nothing until you enable a specific app.
// Apple bundles are refused outright regardless of configuration.
BOOL PSConfigActive(void);

NSData *PSConfigSeed(void);
NSString *PSConfigBundleID(void);
NSInteger PSConfigGeneration(void);

// Location is a separate global toggle on top of the per-app switch, so
// enabling identity spoofing for an app does not also relocate it.
BOOL PSConfigLocationEnabled(void);
double PSConfigLatitude(void);
double PSConfigLongitude(void);
double PSConfigAltitude(void);
