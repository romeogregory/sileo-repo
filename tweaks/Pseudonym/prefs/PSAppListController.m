#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "PSPrefsStore.h"

// Private, but the only way to enumerate installed apps.
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationType;
@end

// Declared for the compiler only. The class is looked up with
// NSClassFromString at runtime rather than referenced directly, because naming
// it creates a link-time dependency the iOS SDK cannot satisfy — the symbol is
// private and absent from MobileCoreServices.tbd.
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allApplications;
@end

@interface PSAppListController : PSListController
@end

@implementation PSAppListController

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
    [group setProperty:@"Enabling an app takes effect the next time it launches, "
                       @"so force-quit it afterwards.\n\nApple's own apps are "
                       @"deliberately absent: spoofing identifiers inside system "
                       @"processes breaks activation, push and iCloud."
                forKey:@"footerText"];

    NSMutableArray *specifiers = [NSMutableArray arrayWithObject:group];

    for (LSApplicationProxy *app in [self userApplications]) {
        NSString *bundleID = app.applicationIdentifier;
        NSString *name = app.localizedName.length ? app.localizedName : bundleID;

        PSSpecifier *spec =
            [PSSpecifier preferenceSpecifierNamed:name
                                           target:self
                                              set:@selector(setValue:forSpecifier:)
                                              get:@selector(valueForSpecifier:)
                                           detail:nil
                                             cell:PSSwitchCell
                                             edit:nil];
        [spec setProperty:bundleID forKey:@"bundleID"];
        [specifiers addObject:spec];
    }

    _specifiers = specifiers;
    return _specifiers;
}

- (NSArray *)userApplications {
    LSApplicationWorkspace *workspace =
        [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
    if (!workspace) return @[];

    NSArray *all = [workspace allApplications];
    NSMutableArray *filtered = [NSMutableArray array];

    for (LSApplicationProxy *app in all) {
        NSString *bundleID = app.applicationIdentifier;
        if (!bundleID.length) continue;
        // The tweak refuses com.apple.* regardless, so offering a switch that
        // silently does nothing would just be a lie in the UI.
        if ([bundleID hasPrefix:@"com.apple."]) continue;
        if (![app.applicationType isEqualToString:@"User"]) continue;
        [filtered addObject:app];
    }

    [filtered sortUsingComparator:^NSComparisonResult(LSApplicationProxy *a,
                                                      LSApplicationProxy *b) {
        return [(a.localizedName ?: a.applicationIdentifier)
                localizedCaseInsensitiveCompare:
                    (b.localizedName ?: b.applicationIdentifier)];
    }];
    return filtered;
}

- (id)valueForSpecifier:(PSSpecifier *)specifier {
    return @([PSPrefsStore enabledForApp:[specifier propertyForKey:@"bundleID"]]);
}

- (void)setValue:(id)value forSpecifier:(PSSpecifier *)specifier {
    [PSPrefsStore setEnabled:[value boolValue]
                      forApp:[specifier propertyForKey:@"bundleID"]];
}

@end
