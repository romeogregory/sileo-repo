#import <Foundation/Foundation.h>
#import "PSProfile.h"

// Every value derives from HMAC-SHA256(seed, "<bundleID>:<generation>:<purpose>").
//
// Deterministic by design: an app sees the same device on every launch, so it
// keeps working normally, while a different app sees an unrelated one. Bumping
// that app's Generation in prefs yields a wholly new identity on demand — that
// is the "new phone" lever, pulled deliberately rather than every launch.
NSUUID *PSIdentityUUID(NSString *purpose);
PSProfile PSIdentityProfile(void);
NSString *PSIdentityKeychainPrefix(void);
