#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
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
