#import "PSIdentity.h"
#import "PSConfig.h"
#import <CommonCrypto/CommonHMAC.h>

static NSData *PSDerive(NSString *purpose) {
    NSData *seed = PSConfigSeed();
    NSString *bundleID = PSConfigBundleID();
    if (seed.length < 16 || !bundleID.length) return nil;

    NSString *label = [NSString stringWithFormat:@"%@:%ld:%@",
                       bundleID, (long)PSConfigGeneration(), purpose];
    NSData *message = [label dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableData *out = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, seed.bytes, seed.length,
           message.bytes, message.length, out.mutableBytes);
    return out;
}

NSUUID *PSIdentityUUID(NSString *purpose) {
    NSData *material = PSDerive(purpose);
    if (material.length < 16) return nil;

    uuid_t bytes;
    memcpy(bytes, material.bytes, 16);
    // Real IDFAs and IDFVs are RFC 4122 version 4 UUIDs. Handing back bytes
    // that don't carry the version and variant bits is itself a tell.
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    return [[NSUUID alloc] initWithUUIDBytes:bytes];
}

PSProfile PSIdentityProfile(void) {
    NSData *material = PSDerive(@"hardware");
    NSUInteger index = 0;
    if (material.length) {
        index = ((const uint8_t *)material.bytes)[0];
    }
    return PSProfileAtIndex(index);
}

NSString *PSIdentityKeychainPrefix(void) {
    NSData *material = PSDerive(@"keychain");
    if (material.length < 8) return nil;

    const uint8_t *b = material.bytes;
    return [NSString stringWithFormat:@"ps_%02x%02x%02x%02x%02x%02x%02x%02x_",
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7]];
}
