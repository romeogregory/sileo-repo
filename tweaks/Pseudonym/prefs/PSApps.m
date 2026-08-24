#import "PSApps.h"
#import <objc/message.h>
#import <dlfcn.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
@end

@implementation PSApps

// NSClassFromString returns nil for a class whose framework has not been mapped
// into the process, and Preferences.app does not necessarily load
// LaunchServices. Left unhandled that makes the app list silently empty no
// matter what is installed.
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
// beats guessing: calling a missing one raises unrecognized selector and would
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

+ (instancetype)enumerate {
    PSApps *result = [[PSApps alloc] init];
    result->_apps = @[];

    Class workspaceClass = PSWorkspaceClass();
    result->_workspaceResolved = (workspaceClass != nil);
    if (!workspaceClass) {
        result->_failureReason = @"LaunchServices unavailable";
        return result;
    }

    NSArray *all = nil;
    @try {
        id workspace = [workspaceClass defaultWorkspace];
        all = PSAllApplications(workspace);
    } @catch (NSException *exception) {
        // A throw here would otherwise leave the pane blank with no explanation,
        // which is the failure mode this whole class exists to avoid.
        result->_failureReason = [NSString stringWithFormat:@"threw %@",
                                  exception.name];
        return result;
    }

    if (!all) {
        result->_failureReason = @"no enumeration selector";
        return result;
    }
    result->_reportedCount = all.count;

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
    // device, so fall back to the looser set.
    NSMutableArray *chosen = strict.count ? strict : loose;
    [chosen sortUsingComparator:^NSComparisonResult(LSApplicationProxy *a,
                                                    LSApplicationProxy *b) {
        return [(a.localizedName ?: a.applicationIdentifier)
                localizedCaseInsensitiveCompare:
                    (b.localizedName ?: b.applicationIdentifier)];
    }];

    result->_apps = chosen;
    return result;
}

@end
