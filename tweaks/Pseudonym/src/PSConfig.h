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

// Empty means leave the clock alone, which is correct for an unchanged
// location. Set it to match a spoofed position so the two cannot contradict
// each other.
NSString *PSConfigTimeZone(void);

// HTTP/HTTPS proxy for enabled apps. Kept separate from the location toggle so
// the two can be used independently, though pairing them is usually the point:
// a GPS fix in one country and an egress IP in another is a louder signal than
// either spoof suppresses.
BOOL PSConfigProxyEnabled(void);
NSString *PSConfigProxyHost(void);
NSInteger PSConfigProxyPort(void);
NSString *PSConfigProxyUser(void);
NSString *PSConfigProxyPassword(void);
