#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import "PSPrefsStore.h"
#import "PSApps.h"

// Everything lives in this one pane on purpose. A PSLinkCell pointing at a
// second controller resolved to something other than our class, producing a
// blank detail pane with no rows at all, so the app list is built here instead
// in the controller PreferenceLoader demonstrably loads.
@interface PSRootListController : PSListController
@end

@implementation PSRootListController

static PSSpecifier *PSGroup(NSString *name, NSString *footer) {
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:name];
    if (footer) [group setProperty:footer forKey:@"footerText"];
    return group;
}

static PSSpecifier *PSInfoRow(id target, NSString *label, NSString *value) {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label
                                                       target:target
                                                          set:NULL
                                                          get:@selector(infoValue:)
                                                       detail:nil
                                                         cell:PSTitleValueCell
                                                         edit:nil];
    [spec setProperty:value forKey:@"psInfoValue"];
    return spec;
}

static PSSpecifier *PSTextRow(id target, NSString *label, NSString *key,
                              NSString *placeholder, UIKeyboardType keyboard,
                              BOOL secure) {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label
                                                       target:target
                                                          set:@selector(setText:specifier:)
                                                          get:@selector(text:)
                                                       detail:nil
                                                         cell:PSEditTextCell
                                                         edit:nil];
    [spec setProperty:key forKey:@"psKey"];
    [spec setProperty:placeholder forKey:@"placeholder"];
    [spec setProperty:@(keyboard) forKey:@"keyboardType"];
    [spec setProperty:@NO forKey:@"autoCaps"];
    [spec setProperty:@NO forKey:@"autoCorrection"];
    if (secure) {
        [spec setProperty:@YES forKey:@"isSecure"];
        [spec setProperty:@YES forKey:@"secure"];
    }
    return spec;
}

// NumbersAndPunctuation, not DecimalPad: coordinates need a minus sign and the
// decimal pad has none, which would make the southern and western hemispheres
// untypeable.
static PSSpecifier *PSCoordRow(id target, NSString *label, NSString *key,
                               NSString *placeholder) {
    return PSTextRow(target, label, key, placeholder,
                     UIKeyboardTypeNumbersAndPunctuation, NO);
}

- (id)flag:(PSSpecifier *)specifier {
    return @([PSPrefsStore boolForKey:[specifier propertyForKey:@"psKey"]]);
}

- (void)setFlag:(id)value specifier:(PSSpecifier *)specifier {
    [PSPrefsStore setBool:[value boolValue]
                   forKey:[specifier propertyForKey:@"psKey"]];
}

- (id)text:(PSSpecifier *)specifier {
    return [PSPrefsStore stringForKey:[specifier propertyForKey:@"psKey"]] ?: @"";
}

- (void)setText:(id)value specifier:(PSSpecifier *)specifier {
    [PSPrefsStore setString:value
                     forKey:[specifier propertyForKey:@"psKey"]];
}

- (id)infoValue:(PSSpecifier *)specifier {
    return [specifier propertyForKey:@"psInfoValue"];
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    PSApps *scan = [PSApps enumerate];
    NSMutableArray *specs = [NSMutableArray array];

    [specs addObject:PSGroup(nil,
        @"Each enabled app sees its own stable fake device instead of your real "
        @"one. The identity stays the same across launches, so apps keep "
        @"working, but no two apps see the same device.")];

    PSSpecifier *toggle =
        [PSSpecifier preferenceSpecifierNamed:@"Enabled"
                                       target:self
                                          set:@selector(setGlobal:specifier:)
                                          get:@selector(global:)
                                       detail:nil
                                         cell:PSSwitchCell
                                         edit:nil];
    [specs addObject:toggle];

    // Surfaced deliberately. An empty app list is otherwise identical whether
    // the device has no apps, the lookup failed, or the filter discarded
    // everything, and guessing between those cost several rounds.
    NSString *version = [[NSBundle bundleForClass:[self class]]
                         objectForInfoDictionaryKey:@"CFBundleShortVersionString"];

    [specs addObject:PSGroup(@"Status", nil)];
    [specs addObject:PSInfoRow(self, @"Version", version ?: @"unknown")];
    [specs addObject:PSInfoRow(self, @"LaunchServices",
                               scan.workspaceResolved
                                   ? @"OK"
                                   : (scan.failureReason ?: @"failed"))];
    [specs addObject:PSInfoRow(self, @"Reported by system",
                               [@(scan.reportedCount) stringValue])];
    [specs addObject:PSInfoRow(self, @"Listed below",
                               [@(scan.apps.count) stringValue])];
    if (scan.failureReason && scan.workspaceResolved) {
        [specs addObject:PSInfoRow(self, @"Note", scan.failureReason)];
    }

    [specs addObject:PSGroup(@"Location",
        @"Reports a fixed position to enabled apps instead of the real one. "
        @"Applies only to apps switched on below, and only while this is on, so "
        @"spoofing an identity does not silently relocate the app as well.")];

    PSSpecifier *locationToggle =
        [PSSpecifier preferenceSpecifierNamed:@"Spoof Location"
                                       target:self
                                          set:@selector(setFlag:specifier:)
                                          get:@selector(flag:)
                                       detail:nil
                                         cell:PSSwitchCell
                                         edit:nil];
    [locationToggle setProperty:@"LocationEnabled" forKey:@"psKey"];
    [specs addObject:locationToggle];

    [specs addObject:PSTextRow(self, @"Address", @"Address",
                               @"Dam 1, Amsterdam", UIKeyboardTypeDefault, NO)];

    PSSpecifier *lookup =
        [PSSpecifier preferenceSpecifierNamed:@"Look Up Address"
                                       target:self
                                          set:NULL
                                          get:NULL
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    lookup->action = @selector(lookUpAddress);
    [specs addObject:lookup];

    [specs addObject:PSCoordRow(self, @"Latitude", @"Latitude", @"52.3676")];
    [specs addObject:PSCoordRow(self, @"Longitude", @"Longitude", @"4.9041")];
    [specs addObject:PSCoordRow(self, @"Altitude (m)", @"Altitude", @"0")];
    [specs addObject:PSTextRow(self, @"Time zone", @"TimeZone",
                               @"Europe/Amsterdam", UIKeyboardTypeDefault, NO)];

    [specs addObject:PSGroup(@"Apps",
        @"Enabling an app takes effect the next time it launches, so force-quit "
        @"it afterwards. Apple's own apps are deliberately absent: spoofing "
        @"identifiers inside system processes breaks activation, push and "
        @"iCloud.")];

    for (LSApplicationProxy *app in scan.apps) {
        NSString *bundleID = app.applicationIdentifier;
        NSString *name = app.localizedName.length ? app.localizedName : bundleID;

        PSSpecifier *spec =
            [PSSpecifier preferenceSpecifierNamed:name
                                           target:self
                                              set:@selector(setAppEnabled:specifier:)
                                              get:@selector(appEnabled:)
                                           detail:nil
                                             cell:PSSwitchCell
                                             edit:nil];
        [spec setProperty:bundleID forKey:@"bundleID"];
        [specs addObject:spec];
    }

    [specs addObject:PSGroup(@"Hide Jailbreak",
        @"Best-effort: hides jailbreak files, fork and package-manager URL "
        @"schemes from enabled apps, so apps that refuse to run on a jailbroken "
        @"device will start. It is not invisibility - a determined check still "
        @"sees through it, and it does not touch DeviceCheck or attestation.")];

    PSSpecifier *cloakToggle =
        [PSSpecifier preferenceSpecifierNamed:@"Hide Jailbreak"
                                       target:self
                                          set:@selector(setFlag:specifier:)
                                          get:@selector(flag:)
                                       detail:nil
                                         cell:PSSwitchCell
                                         edit:nil];
    [cloakToggle setProperty:@"CloakEnabled" forKey:@"psKey"];
    [specs addObject:cloakToggle];

    [specs addObject:PSGroup(@"Proxy",
        @"Routes enabled apps through an HTTP/HTTPS proxy. Pair it with a "
        @"location in the same country: a GPS fix in one place and an egress IP "
        @"in another is a louder signal than either spoof suppresses. Covers "
        @"apps using NSURLSession, which is most of them, but not ones that open "
        @"raw sockets or ship their own TLS stack. The password is stored in "
        @"plaintext in the preferences file.")];

    PSSpecifier *proxyToggle =
        [PSSpecifier preferenceSpecifierNamed:@"Use Proxy"
                                       target:self
                                          set:@selector(setFlag:specifier:)
                                          get:@selector(flag:)
                                       detail:nil
                                         cell:PSSwitchCell
                                         edit:nil];
    [proxyToggle setProperty:@"ProxyEnabled" forKey:@"psKey"];
    [specs addObject:proxyToggle];

    [specs addObject:PSTextRow(self, @"Host", @"ProxyHost", @"proxy.example.com",
                               UIKeyboardTypeURL, NO)];
    [specs addObject:PSTextRow(self, @"Port", @"ProxyPort", @"8080",
                               UIKeyboardTypeNumberPad, NO)];
    [specs addObject:PSTextRow(self, @"Username", @"ProxyUser", @"optional",
                               UIKeyboardTypeDefault, NO)];
    [specs addObject:PSTextRow(self, @"Password", @"ProxyPassword", @"optional",
                               UIKeyboardTypeDefault, YES)];

    [specs addObject:PSGroup(nil,
        @"Gives every enabled app a brand-new device. This is the deliberate "
        @"version of appearing as a new phone: pulled when you want it, rather "
        @"than on every launch, which would log you out constantly and stand "
        @"out as anomalous.")];

    PSSpecifier *button =
        [PSSpecifier preferenceSpecifierNamed:@"Regenerate All Identities"
                                       target:self
                                          set:NULL
                                          get:NULL
                                       detail:nil
                                         cell:PSButtonCell
                                         edit:nil];
    [button setProperty:@YES forKey:@"isDestructive"];
    button->action = @selector(regenerateAll);
    [specs addObject:button];

    _specifiers = specs;
    return _specifiers;
}

- (id)global:(PSSpecifier *)specifier {
    return @([PSPrefsStore globalEnabled]);
}

- (void)setGlobal:(id)value specifier:(PSSpecifier *)specifier {
    [PSPrefsStore setGlobalEnabled:[value boolValue]];
}

- (id)appEnabled:(PSSpecifier *)specifier {
    return @([PSPrefsStore enabledForApp:[specifier propertyForKey:@"bundleID"]]);
}

- (void)setAppEnabled:(id)value specifier:(PSSpecifier *)specifier {
    [PSPrefsStore setEnabled:[value boolValue]
                      forApp:[specifier propertyForKey:@"bundleID"]];
}

- (void)lookUpAddress {
    NSString *address = [PSPrefsStore stringForKey:@"Address"];
    if (!address.length) {
        [self alert:@"No Address" message:@"Type an address in the field first."];
        return;
    }

    // Geocoding sends the address to Apple, the same as any Maps search. It is
    // also unaffected by this tweak: com.apple.* is refused, so Preferences is
    // never spoofed and the lookup runs against the real network.
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    [geocoder geocodeAddressString:address
                completionHandler:^(NSArray<CLPlacemark *> *placemarks,
                                    NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CLPlacemark *place = placemarks.firstObject;
            if (error || !place.location) {
                [self alert:@"Not Found"
                    message:error.localizedDescription
                            ?: @"No coordinates for that address."];
                return;
            }

            CLLocationCoordinate2D c = place.location.coordinate;
            [PSPrefsStore setString:[NSString stringWithFormat:@"%.6f", c.latitude]
                             forKey:@"Latitude"];
            [PSPrefsStore setString:[NSString stringWithFormat:@"%.6f", c.longitude]
                             forKey:@"Longitude"];

            // Rebuild rather than reload: specifiers are cached, so the new
            // coordinates would not otherwise appear in their fields.
            self->_specifiers = nil;
            [self reloadSpecifiers];

            NSString *resolved = place.name.length ? place.name : address;
            if (place.locality.length) {
                resolved = [NSString stringWithFormat:@"%@, %@", resolved,
                            place.locality];
            }
            if (place.country.length) {
                resolved = [NSString stringWithFormat:@"%@, %@", resolved,
                            place.country];
            }
            [self alert:@"Location Set"
                message:[NSString stringWithFormat:@"%@ (%.6f, %.6f)",
                         resolved, c.latitude, c.longitude]];
        });
    }];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)regenerateAll {
    UIAlertController *confirm = [UIAlertController
        alertControllerWithTitle:@"Regenerate All Identities"
                         message:@"Every enabled app will see a brand-new device "
                                 @"next time it launches. Apps that stored a "
                                 @"login will sign you out."
                  preferredStyle:UIAlertControllerStyleAlert];

    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [confirm addAction:[UIAlertAction
        actionWithTitle:@"Regenerate"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    NSInteger changed = [PSPrefsStore bumpAllEnabledGenerations];
                    [self report:changed];
                }]];

    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)report:(NSInteger)changed {
    NSString *message = changed
        ? [NSString stringWithFormat:
               @"%ld app(s) reset. Force-quit them to take effect.", (long)changed]
        : @"No apps are enabled yet.";

    UIAlertController *done = [UIAlertController
        alertControllerWithTitle:@"Done"
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK"
                                             style:UIAlertActionStyleDefault
                                           handler:nil]];
    [self presentViewController:done animated:YES completion:nil];
}

@end
