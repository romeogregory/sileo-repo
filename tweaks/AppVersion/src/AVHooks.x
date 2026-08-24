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

// Optional. Discovery works with this unset; if setBuyParameters turns out to be
// the right hook, setting it makes this build the working feature too rather
// than requiring another round trip.
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

#pragma mark - Discovery

// Which classes actually exist on this build is the thing I cannot determine
// from a Windows box, so the tweak reports it instead of me guessing.
static void AVReportClasses(NSString *needle) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (!classes) return;

    NSMutableArray *matches = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name rangeOfString:needle
                        options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [matches addObject:name];
        }
    }
    free(classes);

    [matches sortUsingSelector:@selector(caseInsensitiveCompare:)];
    AVLog(@"classes matching '%@' (%lu): %@", needle,
          (unsigned long)matches.count,
          AVTruncate([matches componentsJoinedByString:@", "], 1200));
}

static void AVReportSelectors(NSString *className, NSArray *needles) {
    Class cls = NSClassFromString(className);
    if (!cls) {
        AVLog(@"class %@ NOT PRESENT", className);
        return;
    }

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray *interesting = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        for (NSString *needle in needles) {
            if ([name rangeOfString:needle
                            options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [interesting addObject:name];
                break;
            }
        }
    }
    if (methods) free(methods);

    [interesting sortUsingSelector:@selector(caseInsensitiveCompare:)];
    AVLog(@"%@ selectors of interest (%lu of %u): %@", className,
          (unsigned long)interesting.count, count,
          AVTruncate([interesting componentsJoinedByString:@", "], 1200));
}

#pragma mark - Hooks

%hook SSPurchase

- (void)setBuyParameters:(NSString *)parameters {
    AVLog(@"setBuyParameters IN  : %@", AVTruncate(parameters, 900));

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

    NSString *replacement =
        [NSString stringWithFormat:@"appExtVrsId=%@", target];
    NSString *rewritten = [regex
        stringByReplacingMatchesInString:parameters
                                 options:0
                                   range:NSMakeRange(0, parameters.length)
                            withTemplate:replacement];

    if ([rewritten isEqualToString:parameters]) {
        AVLog(@"no appExtVrsId field found, left unchanged");
        %orig;
        return;
    }

    AVLog(@"setBuyParameters OUT : %@", AVTruncate(rewritten, 900));
    %orig(rewritten);
}

%end

%hook NSMutableURLRequest

- (void)setHTTPBody:(NSData *)body {
    // Matched by content, not by host or path. Apple has relocated these
    // endpoints before, and a filter that is subtly out of date is
    // indistinguishable from a request that never happens.
    if (body.length > 0 && body.length < 262144) {
        NSString *text = [[NSString alloc] initWithData:body
                                               encoding:NSUTF8StringEncoding];
        if (text && [text containsString:@"appExtVrsId"]) {
            AVLog(@"setHTTPBody text %@ : %@", self.URL.host,
                  AVTruncate(text, 900));
        } else {
            id plist = [NSPropertyListSerialization propertyListWithData:body
                                                                options:0
                                                                 format:NULL
                                                                  error:NULL];
            NSString *described = plist ? [plist description] : nil;
            if (described && [described containsString:@"appExtVrsId"]) {
                AVLog(@"setHTTPBody plist %@ : %@", self.URL.host,
                      AVTruncate(described, 900));
            }
        }
    }
    %orig;
}

%end

%ctor {
    AVLog(@"==== AppVersion loaded ====");
    AVLog(@"bundle=%@ ios=%@ log=%@",
          [[NSBundle mainBundle] bundleIdentifier],
          [[NSProcessInfo processInfo] operatingSystemVersionString],
          AVLogPath());

    NSString *target = AVTargetVersionId();
    AVLog(@"TargetVersionId=%@ (unset means observe only)",
          target ?: @"(none)");

    AVReportClasses(@"purchase");
    AVReportSelectors(@"SSPurchase",
                      @[@"buy", @"param", @"vrs", @"version", @"adam"]);
}
