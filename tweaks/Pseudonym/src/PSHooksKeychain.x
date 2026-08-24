#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "PSConfig.h"
#import "PSIdentity.h"

// The Keychain is the identifier that actually survives. An app stores a UUID
// here and finds it again after being deleted and reinstalled, which is why
// spoofing IDFA/IDFV alone changes nothing for apps that do this.
//
// Rather than blocking access, every service/account name is namespaced with a
// per-app, per-generation prefix. The app reads and writes normally and keeps
// working; bumping Generation moves it to a fresh namespace, so its old entries
// become unreachable and it sees a first-run device.
//
// This is the invasive hook. Within an app it also namespaces saved credentials
// and Sign in with Apple state, so enable it per app and expect to log in again.
static CFDictionaryRef PSNamespaced(CFDictionaryRef input) {
    NSString *prefix = PSIdentityKeychainPrefix();
    if (!input || !prefix) return NULL;

    NSMutableDictionary *copy = [(__bridge NSDictionary *)input mutableCopy];
    NSArray *keys = @[(__bridge NSString *)kSecAttrService,
                      (__bridge NSString *)kSecAttrAccount];

    BOOL changed = NO;
    for (NSString *key in keys) {
        NSString *value = copy[key];
        if ([value isKindOfClass:[NSString class]] && ![value hasPrefix:prefix]) {
            copy[key] = [prefix stringByAppendingString:value];
            changed = YES;
        }
    }
    if (!changed) return NULL;

    return (__bridge_retained CFDictionaryRef)copy;
}

%hookf(OSStatus, SecItemAdd, CFDictionaryRef attributes, CFTypeRef *result) {
    if (!PSConfigActive()) return %orig;
    CFDictionaryRef patched = PSNamespaced(attributes);
    if (!patched) return %orig;

    OSStatus status = %orig(patched, result);
    CFRelease(patched);
    return status;
}

%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef query, CFTypeRef *result) {
    if (!PSConfigActive()) return %orig;
    CFDictionaryRef patched = PSNamespaced(query);
    if (!patched) return %orig;

    OSStatus status = %orig(patched, result);
    CFRelease(patched);
    return status;
}

%hookf(OSStatus, SecItemDelete, CFDictionaryRef query) {
    if (!PSConfigActive()) return %orig;
    CFDictionaryRef patched = PSNamespaced(query);
    if (!patched) return %orig;

    OSStatus status = %orig(patched);
    CFRelease(patched);
    return status;
}

%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (!PSConfigActive()) return %orig;

    CFDictionaryRef patchedQuery = PSNamespaced(query);
    CFDictionaryRef patchedAttrs = PSNamespaced(attributesToUpdate);

    OSStatus status = %orig(patchedQuery ?: query,
                            patchedAttrs ?: attributesToUpdate);

    if (patchedQuery) CFRelease(patchedQuery);
    if (patchedAttrs) CFRelease(patchedAttrs);
    return status;
}
