#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "PSPrefsStore.h"

// Private, but the only way to enumerate installed apps. Declared for the
// compiler only — the class is resolved at runtime, because naming it directly
// creates a link dependency the iOS SDK cannot satisfy.
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationType;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
@end

@interface PSAppListController : PSListController {
    NSUInteger _reportedCount;
    BOOL _workspaceResolved;
}
@end

@implementation PSAppListController

// NSClassFromString returns nil for a class whose framework has not been mapped
// into the process, and Preferences.app does not necessarily load
// LaunchServices. Left unhandled that makes the app list silently empty no
// matter what is installed — indistinguishable from having no apps.
static Class PSWorkspaceClass(void) {
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    if (cls) return cls;

    static const char *frameworks[] = {
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
        "LaunchServices.framework/LaunchServices",
        "/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
    };
    for (size_t i = 0; i < sizeof(frameworks) / sizeof(frameworks[0]); i++) {
        if (dlopen(frameworks[i], RTLD_LAZY)) {
            cls = NSClassFromString(@"LSApplicationWorkspace");
            if (cls) return cls;
        }
    }
    return nil;
}

// The enumeration selector has been spelled both ways across releases. Probing
// beats guessing: calling a missing one would raise unrecognized selector and
// take Settings down with it.
static NSArray *PSAllApplications(id workspace) {
    for (NSString *name in @[@"allApplications", @"allInstalledApplications"]) {
        SEL selector = NSSelectorFromString(name);
        if ([workspace respondsToSelector:selector]) {
            return ((NSArray *(*)(id, SEL))objc_msgSend)(workspace, selector);
        }
    }
    return nil;
}

- (NSArray *)userApplications {
    Class workspaceClass = PSWorkspaceClass();
    _workspaceResolved = (workspaceClass != nil);
    if (!workspaceClass) return @[];

    id workspace = [workspaceClass defaultWorkspace];
    NSArray *all = PSAllApplications(workspace);
    _reportedCount = all.count;

    NSMutableArray *strict = [NSMutableArray array];
    NSMutableArray *loose = [NSMutableArray array];

    for (LSApplicationProxy *app in all) {
        NSString *bundleID = app.applicationIdentifier;
        if (!bundleID.length) continue;
        // The tweak refuses com.apple.* regardless, so offering a switch that
        // silently does nothing would just be a lie in the UI.
        if ([bundleID hasPrefix:@"com.apple."]) continue;

        [loose addObject:app];
        if ([app.applicationType isEqualToString:@"User"]) {
            [strict addObject:app];
        }
    }

    // applicationType is private and its values have moved between releases. If
    // filtering on it discards everything, the filter is what is wrong, not the
    // device — fall back to the looser set rather than show an empty pane.
    NSMutableArray *result = strict.count ? strict : loose;

    [result sortUsingComparator:^NSComparisonResult(LSApplicationProxy *a,
                                                    LSApplicationProxy *b) {
        return [(a.localizedName ?: a.applicationIdentifier)
                localizedCaseInsensitiveCompare:
                    (b.localizedName ?: b.applicationIdentifier)];
    }];
    return result;
}

// A PSGroupCell with no rows beneath it renders nothing — no header, no
// footer. Putting diagnostics in a footer therefore hid them in precisely the
// case they exist for: an empty list. Rows always render, so the status goes in
// cells instead.
static PSSpecifier *PSStatusRow(id target, NSString *label, NSString *value) {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label
                                                       target:target
                                                          set:NULL
                                                          get:@selector(statusValue:)
                                                       detail:nil
                                                         cell:PSTitleValueCell
                                                         edit:nil];
    [spec setProperty:value forKey:@"psStatusValue"];
    return spec;
}

- (id)statusValue:(PSSpecifier *)specifier {
    return [specifier propertyForKey:@"psStatusValue"];
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    NSArray *apps = [self userApplications];
    NSMutableArray *specifiers = [NSMutableArray array];

    [specifiers addObject:[PSSpecifier groupSpecifierWithName:@"Status"]];
    [specifiers addObject:PSStatusRow(self, @"LaunchServices",
                                      _workspaceResolved ? @"OK" : @"unavailable")];
    [specifiers addObject:PSStatusRow(self, @"Reported by system",
                                      [@(_reportedCount) stringValue])];
    [specifiers addObject:PSStatusRow(self, @"Listed here",
                                      [@(apps.count) stringValue])];

    PSSpecifier *appGroup = [PSSpecifier groupSpecifierWithName:@"Apps"];
    [appGroup setProperty:@"Enabling an app takes effect the next time it "
                          @"launches, so force-quit it afterwards. Apple's "
                          @"own apps are deliberately absent: spoofing "
                          @"identifiers inside system processes breaks "
                          @"activation, push and iCloud."
                   forKey:@"footerText"];
    [specifiers addObject:appGroup];

    for (LSApplicationProxy *app in apps) {
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

- (id)valueForSpecifier:(PSSpecifier *)specifier {
    return @([PSPrefsStore enabledForApp:[specifier propertyForKey:@"bundleID"]]);
}

- (void)setValue:(id)value forSpecifier:(PSSpecifier *)specifier {
    [PSPrefsStore setEnabled:[value boolValue]
                      forApp:[specifier propertyForKey:@"bundleID"]];
}

@end
