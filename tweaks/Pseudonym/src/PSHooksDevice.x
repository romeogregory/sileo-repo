#import <UIKit/UIKit.h>
#import "PSConfig.h"
#import "PSIdentity.h"

@interface ASIdentifierManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, readonly) NSUUID *advertisingIdentifier;
@end

// iOS hands out the all-zero UUID when App Tracking Transparency was denied.
static BOOL PSIsZeroUUID(NSUUID *uuid) {
    if (!uuid) return YES;
    uuid_t bytes;
    [uuid getUUIDBytes:bytes];
    for (int i = 0; i < 16; i++) {
        if (bytes[i]) return NO;
    }
    return YES;
}

%hook UIDevice

- (NSUUID *)identifierForVendor {
    if (!PSConfigActive()) return %orig;
    return PSIdentityUUID(@"idfv") ?: %orig;
}

- (NSString *)name {
    if (!PSConfigActive()) return %orig;
    // Unentitled apps on iOS 16 already get "iPhone" rather than the name the
    // user chose. Returning the same thing is the coherent answer, and it also
    // closes the leak for apps that do hold the entitlement.
    return @"iPhone";
}

// systemVersion is deliberately NOT hooked. The hardware profile is already
// constrained to devices that run 16.7.x, so the real version keeps the story
// consistent. Faking it buys nothing — millions of devices share a version
// string — and risks contradicting the model we just reported.

%end

%hook ASIdentifierManager

- (NSUUID *)advertisingIdentifier {
    if (!PSConfigActive()) return %orig;

    NSUUID *real = %orig;
    // If ATT was denied, iOS is already returning zeros. That leaks strictly
    // less than any plausible-looking UUID we could invent, so handing back a
    // fake here would make the app MORE able to track you, not less.
    if (PSIsZeroUUID(real)) return real;

    return PSIdentityUUID(@"idfa") ?: real;
}

- (BOOL)isAdvertisingTrackingEnabled {
    if (!PSConfigActive()) return %orig;
    return NO;
}

%end
