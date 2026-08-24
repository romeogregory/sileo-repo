#import <Foundation/Foundation.h>
#import "PSConfig.h"
#import "PSIdentity.h"

%ctor {
    // The filter injects into anything linking UIKit, which is nearly every
    // process on the device. Gating here keeps the cost to a single prefs read
    // for apps that were never enabled.
    if (!PSConfigActive()) return;

    PSProfile profile = PSIdentityProfile();
    NSLog(@"[Pseudonym] active for %@ — presenting as %s (%s), generation %ld",
          PSConfigBundleID(), profile.marketing, profile.machine,
          (long)PSConfigGeneration());
}
