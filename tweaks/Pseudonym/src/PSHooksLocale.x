#import <Foundation/Foundation.h>
#import "PSConfig.h"

// A spoofed position in one country while the clock reports another is the same
// class of contradiction as the hardware mismatch: two facts about one device
// that cannot both be true. Anything correlating them learns more from the
// disagreement than either value gives away on its own.
//
// Left unset this does nothing at all - an unchanged timezone is correct for an
// unchanged location, and changing it without reason would create the very
// mismatch it exists to remove.
static NSTimeZone *PSFakeTimeZone(void) {
    if (!PSConfigActive()) return nil;

    NSString *identifier = PSConfigTimeZone();
    if (!identifier.length) return nil;

    // Cached: these accessors are called constantly by date formatting, and
    // building a timezone per call would be a real cost.
    static NSTimeZone *cached;
    static NSString *cachedIdentifier;
    if (![cachedIdentifier isEqualToString:identifier]) {
        cached = [NSTimeZone timeZoneWithName:identifier];
        cachedIdentifier = [identifier copy];
    }
    return cached;
}

%hook NSTimeZone

+ (NSTimeZone *)systemTimeZone {
    NSTimeZone *fake = PSFakeTimeZone();
    return fake ?: %orig;
}

+ (NSTimeZone *)localTimeZone {
    NSTimeZone *fake = PSFakeTimeZone();
    return fake ?: %orig;
}

+ (NSTimeZone *)defaultTimeZone {
    NSTimeZone *fake = PSFakeTimeZone();
    return fake ?: %orig;
}

%end
