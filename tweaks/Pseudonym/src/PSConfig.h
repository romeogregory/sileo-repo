#import <Foundation/Foundation.h>

// Spoofing is OPT-IN per app. An app absent from the prefs plist is untouched,
// so installing this tweak changes nothing until you enable a specific app.
// Apple bundles are refused outright regardless of configuration.
BOOL PSConfigActive(void);

// Reentrancy guard. The cloak hooks open/stat, and reading configuration itself
// opens a file - which lands back in those hooks. Without this, that recursion
// deadlocks the process (it hung every UIKit app, SpringBoard included).
// A hook checks PSHookReentered() first and passes through if it is already
// inside a guarded region on this thread.
BOOL PSHookReentered(void);
void PSHookEnter(void);
void PSHookLeave(void);

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

// Best-effort jailbreak hiding, separate from identity spoofing so an app can
// have one without the other.
BOOL PSConfigCloakEnabled(void);

// Hides injected images from the dyld list. Its own switch because it is the
// riskier hook - see PSHooksDyld.x.
BOOL PSConfigDyldHideEnabled(void);

// HTTP/HTTPS proxy for enabled apps. Kept separate from the location toggle so
// the two can be used independently, though pairing them is usually the point:
// a GPS fix in one country and an egress IP in another is a louder signal than
// either spoof suppresses.
BOOL PSConfigProxyEnabled(void);
NSString *PSConfigProxyHost(void);
NSInteger PSConfigProxyPort(void);
NSString *PSConfigProxyUser(void);
NSString *PSConfigProxyPassword(void);
