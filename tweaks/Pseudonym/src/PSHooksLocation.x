#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import "PSConfig.h"

// %new adds these at runtime, but the compiler still needs to see them
// declared before they can be called from the hooks above.
@interface CLLocationManager (Pseudonym)
- (void)psStartFakeUpdates;
- (void)psStopFakeUpdates;
- (void)psDeliverFake;
@end

// Location is gated on BOTH the per-app switch and a separate global Location
// toggle, so turning identity spoofing on for an app does not silently move it
// somewhere else too.
static BOOL PSLocationActive(void) {
    return PSConfigActive() && PSConfigLocationEnabled();
}

static CLLocation *PSFakeLocation(void) {
    CLLocationCoordinate2D coordinate =
        CLLocationCoordinate2DMake(PSConfigLatitude(), PSConfigLongitude());

    // The timestamp must be current. Apps routinely discard a fix older than a
    // few seconds as stale, so a fixed date would be silently ignored by
    // exactly the apps that matter.
    return [[CLLocation alloc] initWithCoordinate:coordinate
                                         altitude:PSConfigAltitude()
                               horizontalAccuracy:5.0
                                 verticalAccuracy:5.0
                                           course:0.0
                                            speed:0.0
                                        timestamp:[NSDate date]];
}

static char kPSTimerKey;

%hook CLLocationManager

- (CLLocation *)location {
    if (!PSLocationActive()) return %orig;
    return PSFakeLocation();
}

- (void)startUpdatingLocation {
    if (!PSLocationActive()) {
        %orig;
        return;
    }
    // Deliberately NOT calling %orig: if the real hardware updates never start,
    // a genuine fix cannot arrive alongside ours and leak the true position.
    [self psStartFakeUpdates];
}

- (void)stopUpdatingLocation {
    [self psStopFakeUpdates];
    if (!PSLocationActive()) %orig;
}

- (void)requestLocation {
    if (!PSLocationActive()) {
        %orig;
        return;
    }
    [self psDeliverFake];
}

// Apps check these before they will even ask for a position. Left untouched, a
// spoofed location is unreachable for any app the user has not separately
// granted real location access to.
+ (CLAuthorizationStatus)authorizationStatus {
    if (!PSLocationActive()) return %orig;
    return kCLAuthorizationStatusAuthorizedWhenInUse;
}

- (CLAuthorizationStatus)authorizationStatus {
    if (!PSLocationActive()) return %orig;
    return kCLAuthorizationStatusAuthorizedWhenInUse;
}

+ (BOOL)locationServicesEnabled {
    if (!PSLocationActive()) return %orig;
    return YES;
}

%new
- (void)psDeliverFake {
    id delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        return;
    }
    CLLocation *fake = PSFakeLocation();
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate locationManager:self didUpdateLocations:@[fake]];
    });
}

%new
- (void)psStartFakeUpdates {
    [self psStopFakeUpdates];

    // A repeating timer stands in for the hardware's update stream. Apps that
    // wait for a second fix before trusting the first would otherwise hang.
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                     repeats:YES
                                                       block:^(NSTimer *t) {
        [self psDeliverFake];
    }];
    objc_setAssociatedObject(self, &kPSTimerKey, timer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self psDeliverFake];
}

%new
- (void)psStopFakeUpdates {
    NSTimer *timer = objc_getAssociatedObject(self, &kPSTimerKey);
    [timer invalidate];
    objc_setAssociatedObject(self, &kPSTimerKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end
