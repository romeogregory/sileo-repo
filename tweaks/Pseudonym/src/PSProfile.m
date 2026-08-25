#import "PSProfile.h"

static const PSProfile kProfiles[] = {
    // 3GB and 6 cores are the real iPhone X figures. A claimed model whose
    // memory or core count disagrees with it is the same kind of impossible
    // pairing the screen mismatch was.
    { "iPhone10,3", "D22AP",  "iPhone X", 3221225472ULL, 6 },
    { "iPhone10,6", "D221AP", "iPhone X", 3221225472ULL, 6 },
};

NSUInteger PSProfileCount(void) {
    return sizeof(kProfiles) / sizeof(kProfiles[0]);
}

PSProfile PSProfileAtIndex(NSUInteger index) {
    return kProfiles[index % PSProfileCount()];
}
