#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "AVLog.h"

// Declared for the compiler only. Logos resolves hooked classes at runtime via
// objc_getClass, so naming a private class here creates no link dependency and
// the hook simply does not install if the class is absent on this iOS build.
@interface SSPurchase : NSObject
@property (nonatomic, copy) NSString *buyParameters;
@end

static NSString *const kPrefsPath =
    @"/var/jb/var/mobile/Library/Preferences/com.romeo.appversion.plist";

// Kill switch. Version 0.1.0 stalled the App Store, and recovering meant
// uninstalling the package from Sileo. Touching this file disables every hook
// on next launch, which is a far cheaper way out of the same situation.
static NSString *const kDisableFlag =
    @"/var/jb/var/mobile/Library/Logs/AppVersion/appversion.off";

static BOOL AVEnabled(void) {
    static BOOL enabled;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        enabled = ![[NSFileManager defaultManager] fileExistsAtPath:kDisableFlag];
    });
    return enabled;
}

static NSString *AVTargetVersionId(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    id value = prefs[@"TargetVersionId"];
    if ([value isKindOfClass:[NSString class]] && [value length]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return nil;
}

static NSString *AVTruncate(NSString *text, NSUInteger limit) {
    if (text.length <= limit) return text;
    return [[text substringToIndex:limit] stringByAppendingString:@" ...[cut]"];
}

// Buy parameters carry Apple account identifiers - guid, DSID, session tokens.
// The discovery value here is the SHAPE of the request, not the values, so key
// names and lengths are kept and everything outside a tight allowlist is
// dropped. Writing account identifiers to disk to learn a field name would be a
// bad trade.
static NSString *AVRedact(NSString *parameters) {
    if (!parameters.length) return @"(empty)";

    static NSSet *safe;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        // Non-secret and directly useful: the version we target, the public App
        // Store id of the app, and the product type.
        safe = [NSSet setWithArray:@[@"appExtVrsId", @"salableAdamId",
                                     @"productType"]];
    });

    NSMutableArray *out = [NSMutableArray array];
    for (NSString *field in [parameters componentsSeparatedByString:@"&"]) {
        NSRange split = [field rangeOfString:@"="];
        if (split.location == NSNotFound) {
            [out addObject:field];
            continue;
        }
        NSString *key = [field substringToIndex:split.location];
        NSString *value = [field substringFromIndex:split.location + 1];
        if ([safe containsObject:key]) {
            [out addObject:field];
        } else {
            [out addObject:[NSString stringWithFormat:@"%@=<redacted:%lu>",
                            key, (unsigned long)value.length]];
        }
    }
    return [out componentsJoinedByString:@"&"];
}

#pragma mark - Discovery

// Deliberately NOT run from %ctor. Enumerating every registered class before
// the app has started delays launch, and this is diagnostics rather than
// anything the hooks depend on.
static void AVReportEnvironment(void) {
    @try {
        AVLog(@"bundle=%@ ios=%@ log=%@",
              [[NSBundle mainBundle] bundleIdentifier],
              [[NSProcessInfo processInfo] operatingSystemVersionString],
              AVLogPath());
        AVLog(@"TargetVersionId=%@ (unset means observe only)",
              AVTargetVersionId() ?: @"(none)");

        unsigned int count = 0;
        Class *classes = objc_copyClassList(&count);
        if (classes) {
            NSMutableArray *matches = [NSMutableArray array];
            for (unsigned int i = 0; i < count; i++) {
                const char *raw = class_getName(classes[i]);
                // Compared as C strings: NSStringFromClass on tens of thousands
                // of classes allocates tens of thousands of objects for nothing.
                if (raw && strcasestr(raw, "purchase")) {
                    [matches addObject:@(raw)];
                }
            }
            free(classes);
            [matches sortUsingSelector:@selector(caseInsensitiveCompare:)];
            AVLog(@"classes matching 'purchase' (%lu of %u): %@",
                  (unsigned long)matches.count, count,
                  AVTruncate([matches componentsJoinedByString:@", "], 1200));
        }

        Class purchase = NSClassFromString(@"SSPurchase");
        if (!purchase) {
            AVLog(@"SSPurchase NOT PRESENT on this build");
            return;
        }
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(purchase, &methodCount);
        NSMutableArray *interesting = [NSMutableArray array];
        for (unsigned int i = 0; i < methodCount; i++) {
            const char *sel = sel_getName(method_getName(methods[i]));
            if (!sel) continue;
            if (strcasestr(sel, "buy") || strcasestr(sel, "param") ||
                strcasestr(sel, "vrs") || strcasestr(sel, "version") ||
                strcasestr(sel, "adam")) {
                [interesting addObject:@(sel)];
            }
        }
        if (methods) free(methods);
        [interesting sortUsingSelector:@selector(caseInsensitiveCompare:)];
        AVLog(@"SSPurchase selectors of interest (%lu of %u): %@",
              (unsigned long)interesting.count, methodCount,
              AVTruncate([interesting componentsJoinedByString:@", "], 1200));
    } @catch (NSException *exception) {
        AVLog(@"discovery threw %@: %@", exception.name, exception.reason);
    }
}

#pragma mark - Hooks

%hook SSPurchase

- (void)setBuyParameters:(NSString *)parameters {
    if (!AVEnabled()) {
        %orig;
        return;
    }
    AVLog(@"setBuyParameters IN  : %@", AVTruncate(AVRedact(parameters), 900));

    NSString *target = AVTargetVersionId();
    if (!target || !parameters.length) {
        %orig;
        return;
    }

    // The parameters are a key=value string, so this is a substitution rather
    // than a structured edit. Bounded to digits so it cannot eat the next field.
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"appExtVrsId=[0-9]+"
                             options:0
                               error:&error];
    if (!regex) {
        AVLog(@"regex failed: %@", error.localizedDescription);
        %orig;
        return;
    }

    NSString *rewritten = [regex
        stringByReplacingMatchesInString:parameters
                                 options:0
                                   range:NSMakeRange(0, parameters.length)
                            withTemplate:[NSString stringWithFormat:
                                          @"appExtVrsId=%@", target]];

    if ([rewritten isEqualToString:parameters]) {
        AVLog(@"no appExtVrsId field found, left unchanged");
        %orig;
        return;
    }

    AVLog(@"setBuyParameters OUT : %@", AVTruncate(AVRedact(rewritten), 900));
    %orig(rewritten);
}

%end

%hook NSMutableURLRequest

- (void)setHTTPBody:(NSData *)body {
    // Version 0.1.0 stringified every body and plist-parsed whatever was not
    // UTF-8, then searched the description. On a process that makes as many
    // requests as the App Store that was enough to stall it completely.
    //
    // This is now a raw byte search with no allocation, skipped entirely for
    // bodies too large to be a buy request. Nothing is decoded unless the key is
    // actually present, which is rare.
    if (!AVEnabled() || body.length == 0 || body.length > 65536) {
        %orig;
        return;
    }

    static NSData *needle;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        needle = [@"appExtVrsId" dataUsingEncoding:NSASCIIStringEncoding];
    });

    NSRange found = [body rangeOfData:needle
                              options:0
                                range:NSMakeRange(0, body.length)];
    if (found.location == NSNotFound) {
        %orig;
        return;
    }

    @try {
        // The body around this key is request state, not something worth
        // writing to disk. Only the field we came for is recorded.
        NSString *text = [[NSString alloc] initWithData:body
                                               encoding:NSUTF8StringEncoding];
        NSString *value = @"(binary)";
        if (text) {
            NSRegularExpression *regex = [NSRegularExpression
                regularExpressionWithPattern:@"appExtVrsId[=\":< ]+([0-9]+)"
                                     options:0
                                       error:NULL];
            NSTextCheckingResult *match =
                [regex firstMatchInString:text options:0
                                    range:NSMakeRange(0, text.length)];
            value = match ? [text substringWithRange:[match rangeAtIndex:1]]
                          : @"(present, unparsed)";
        }
        AVLog(@"setHTTPBody %@ (%lu bytes) appExtVrsId=%@", self.URL.host,
              (unsigned long)body.length, value);
    } @catch (NSException *exception) {
        AVLog(@"body log threw %@", exception.name);
    }
    %orig;
}

%end

%ctor {
    if (!AVEnabled()) {
        NSLog(@"[AppVersion] disabled by %@", kDisableFlag);
        return;
    }
    AVLog(@"==== AppVersion loaded ====");

    // Off the launch path. The App Store gets to start before any of this runs.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        AVReportEnvironment();
    });
}
