#import "AVRedact.h"

NSString *const AVVersionKey = @"appExtVrsId";

// Non-secret and directly useful: the version we target, the public App Store
// id of the app, and the product type. Everything else is reduced to a length.
static NSSet *AVSafeKeys(void) {
    static NSSet *safe;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        safe = [NSSet setWithArray:@[AVVersionKey, @"salableAdamId",
                                     @"productType", @"pricingParameters"]];
    });
    return safe;
}

static NSString *AVRedactString(NSString *parameters) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *field in [parameters componentsSeparatedByString:@"&"]) {
        NSRange split = [field rangeOfString:@"="];
        if (split.location == NSNotFound) {
            [out addObject:field];
            continue;
        }
        NSString *key = [field substringToIndex:split.location];
        NSString *value = [field substringFromIndex:split.location + 1];
        if ([AVSafeKeys() containsObject:key]) {
            [out addObject:field];
        } else {
            [out addObject:[NSString stringWithFormat:@"%@=<redacted:%lu>",
                            key, (unsigned long)value.length]];
        }
    }
    return [out componentsJoinedByString:@"&"];
}

static NSString *AVRedactDictionary(NSDictionary *parameters) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *key in [[parameters allKeys]
            sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        id value = parameters[key];
        if ([AVSafeKeys() containsObject:key]) {
            [out addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
        } else {
            NSString *described = [value description];
            [out addObject:[NSString stringWithFormat:@"%@=<redacted:%lu>",
                            key, (unsigned long)described.length]];
        }
    }
    return [out componentsJoinedByString:@"&"];
}

NSString *AVRedact(id parameters) {
    if (!parameters) return @"(nil)";
    if ([parameters isKindOfClass:[NSString class]]) {
        return [parameters length] ? AVRedactString(parameters) : @"(empty)";
    }
    if ([parameters isKindOfClass:[NSDictionary class]]) {
        return AVRedactDictionary(parameters);
    }
    // Unexpected type: report the class rather than its contents, since we do
    // not know what is inside it and it may not be safe to print.
    return [NSString stringWithFormat:@"(%@)",
            NSStringFromClass([parameters class])];
}
