#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "AVLog.h"
#import "AVRedact.h"

// Declared for the compiler only. Logos resolves hooked classes at runtime via
// objc_getClass, so naming private classes here creates no link dependency and
// a hook simply does not install if its class is absent on this build.
@interface SSPurchase : NSObject
@property (nonatomic, copy) NSString *buyParameters;
@end

// ASD is AppStoreDaemon. appendValue:forBuyParameter: is a named setter, which
// makes it the cleanest interception point on this build: the version can be
// substituted by key with no string surgery at all.
@interface ASDPurchase : NSObject
@property (nonatomic, copy) id buyParameters;
- (void)appendValue:(id)value forBuyParameter:(NSString *)parameter;
@end

@interface AMSPurchaseInfo : NSObject
@property (nonatomic, copy) id buyParams;
@end

static NSString *const kPrefsPath =
    @"/var/jb/var/mobile/Library/Preferences/com.romeo.appversion.plist";

// Kill switch. 0.1.0 stalled the App Store and recovering meant uninstalling
// from Sileo; touching this file makes every hook inert on next launch instead.
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

static NSString *AVProcess(void) {
    return [[NSProcessInfo processInfo] processName];
}

static NSString *AVTruncate(NSString *text, NSUInteger limit) {
    if (text.length <= limit) return text;
    return [[text substringToIndex:limit] stringByAppendingString:@" ...[cut]"];
}

// Returns a rewritten copy of the same type, or nil when nothing changed.
static id AVRewrite(id parameters, NSString *target) {
    if (!target.length) return nil;

    if ([parameters isKindOfClass:[NSDictionary class]]) {
        id existing = parameters[AVVersionKey];
        if (!existing) return nil;
        NSMutableDictionary *copy = [parameters mutableCopy];
        // Match the existing type: these dictionaries hold numbers on some
        // paths and strings on others, and a mismatch is rejected server-side.
        copy[AVVersionKey] = [existing isKindOfClass:[NSNumber class]]
            ? (id)@([target longLongValue]) : (id)target;
        return copy;
    }

    if (![parameters isKindOfClass:[NSString class]]) return nil;

    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:
            [NSString stringWithFormat:@"%@=[0-9]+", AVVersionKey]
                             options:0
                               error:NULL];
    if (!regex) return nil;

    NSString *rewritten = [regex
        stringByReplacingMatchesInString:parameters
                                 options:0
                                   range:NSMakeRange(0, [parameters length])
                            withTemplate:[NSString stringWithFormat:@"%@=%@",
                                          AVVersionKey, target]];
    return [rewritten isEqualToString:parameters] ? nil : rewritten;
}

// appendValue:forBuyParameter: never fires on this build - the whole parameter
// string is set in one call - so the observed version has to be pulled back out
// of it for the Settings pane to have anything to show.
static void AVNoteVersion(id parameters) {
    NSString *found = nil;

    if ([parameters isKindOfClass:[NSDictionary class]]) {
        id value = parameters[AVVersionKey];
        if (value) found = [value description];
    } else if ([parameters isKindOfClass:[NSString class]]) {
        NSRegularExpression *regex = [NSRegularExpression
            regularExpressionWithPattern:
                [NSString stringWithFormat:@"%@=([0-9]+)", AVVersionKey]
                                 options:0
                                   error:NULL];
        NSTextCheckingResult *match = [regex
            firstMatchInString:parameters
                       options:0
                         range:NSMakeRange(0, [parameters length])];
        if (match) found = [parameters substringWithRange:[match rangeAtIndex:1]];
    }

    if (found.length) AVRecordLastSeen(found);
}

#pragma mark - Discovery

static void AVReportEnvironment(void) {
    @try {
        AVLog(@"process=%@ bundle=%@ ios=%@", AVProcess(),
              [[NSBundle mainBundle] bundleIdentifier] ?: @"(none)",
              [[NSProcessInfo processInfo] operatingSystemVersionString]);
        AVLog(@"TargetVersionId=%@",
              AVTargetVersionId() ?: @"(none, observe only)");

        for (NSString *className in @[@"SSPurchase", @"AMSPurchase",
                                      @"AMSPurchaseInfo", @"ASDPurchase"]) {
            Class cls = NSClassFromString(className);
            if (!cls) {
                AVLog(@"%@ NOT PRESENT here", className);
                continue;
            }
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            NSMutableArray *interesting = [NSMutableArray array];
            for (unsigned int i = 0; i < methodCount; i++) {
                const char *sel = sel_getName(method_getName(methods[i]));
                if (!sel) continue;
                if (strcasestr(sel, "buy") || strcasestr(sel, "param") ||
                    strcasestr(sel, "vrs") || strcasestr(sel, "version")) {
                    [interesting addObject:@(sel)];
                }
            }
            if (methods) free(methods);
            [interesting sortUsingSelector:@selector(caseInsensitiveCompare:)];
            AVLog(@"%@ (%lu of %u): %@", className,
                  (unsigned long)interesting.count, methodCount,
                  AVTruncate([interesting componentsJoinedByString:@", "], 700));
        }
    } @catch (NSException *exception) {
        AVLog(@"discovery threw %@: %@", exception.name, exception.reason);
    }
}

#pragma mark - ASDPurchase, the likely path on iOS 16

%hook ASDPurchase

- (void)appendValue:(id)value forBuyParameter:(NSString *)parameter {
    if (!AVEnabled()) {
        %orig;
        return;
    }

    if (![parameter isEqualToString:AVVersionKey]) {
        // Only the field name for everything else: those values are account
        // state and there is no reason to write them to disk.
        AVLog(@"[%@] ASD append %@", AVProcess(), parameter);
        %orig;
        return;
    }

    NSString *target = AVTargetVersionId();
    AVRecordLastSeen([value description]);
    AVLog(@"[%@] ASD append %@=%@%@", AVProcess(), parameter, value,
          target ? [NSString stringWithFormat:@" -> %@", target] : @"");

    if (!target.length) {
        %orig;
        return;
    }
    // Substituting by key, with no string surgery. This is why ASDPurchase is
    // the right hook rather than rewriting a serialised parameter blob.
    id replacement = [value isKindOfClass:[NSNumber class]]
        ? (id)@([target longLongValue]) : (id)target;
    %orig(replacement, parameter);
}

- (void)setBuyParameters:(id)parameters {
    if (!AVEnabled()) {
        %orig;
        return;
    }
    AVNoteVersion(parameters);
    AVLog(@"[%@] ASD setBuyParameters (%@) : %@", AVProcess(),
          NSStringFromClass([parameters class]),
          AVTruncate(AVRedact(parameters), 700));

    id rewritten = AVRewrite(parameters, AVTargetVersionId());
    if (!rewritten) {
        %orig;
        return;
    }
    AVLog(@"[%@] ASD rewritten : %@", AVProcess(),
          AVTruncate(AVRedact(rewritten), 700));
    %orig(rewritten);
}

%end

#pragma mark - AppleMediaServices

%hook AMSPurchaseInfo

- (void)setBuyParams:(id)parameters {
    if (!AVEnabled()) {
        %orig;
        return;
    }
    AVNoteVersion(parameters);
    AVLog(@"[%@] AMS setBuyParams (%@) : %@", AVProcess(),
          NSStringFromClass([parameters class]),
          AVTruncate(AVRedact(parameters), 700));

    id rewritten = AVRewrite(parameters, AVTargetVersionId());
    if (!rewritten) {
        %orig;
        return;
    }
    AVLog(@"[%@] AMS rewritten : %@", AVProcess(),
          AVTruncate(AVRedact(rewritten), 700));
    %orig(rewritten);
}

%end

#pragma mark - StoreServices, the pre-iOS 16 path

%hook SSPurchase

- (void)setBuyParameters:(NSString *)parameters {
    if (!AVEnabled()) {
        %orig;
        return;
    }
    AVNoteVersion(parameters);
    AVLog(@"[%@] SS setBuyParameters : %@", AVProcess(),
          AVTruncate(AVRedact(parameters), 700));

    id rewritten = AVRewrite(parameters, AVTargetVersionId());
    if (!rewritten) {
        %orig;
        return;
    }
    AVLog(@"[%@] SS rewritten : %@", AVProcess(),
          AVTruncate(AVRedact(rewritten), 700));
    %orig(rewritten);
}

%end

#pragma mark - Fallback

%hook NSMutableURLRequest

- (void)setHTTPBody:(NSData *)body {
    // A raw byte search with no allocation, skipped for bodies too large to be
    // a buy request. 0.1.0 stringified and plist-parsed every body here and
    // stalled the App Store outright.
    if (!AVEnabled() || body.length == 0 || body.length > 65536) {
        %orig;
        return;
    }

    static NSData *needle;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        needle = [AVVersionKey dataUsingEncoding:NSASCIIStringEncoding];
    });

    if ([body rangeOfData:needle
                  options:0
                    range:NSMakeRange(0, body.length)].location != NSNotFound) {
        AVLog(@"[%@] setHTTPBody %@ carries %@ (%lu bytes)", AVProcess(),
              self.URL.host, AVVersionKey, (unsigned long)body.length);
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

    // Off the launch path: this is diagnostics, and enumerating every
    // registered class before the app starts delays it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        AVReportEnvironment();
    });
}
