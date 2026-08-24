#import "PSProfile.h"

static const PSProfile kProfiles[] = {
    { "iPhone8,1",  "N71AP",  "iPhone 6s"      },
    { "iPhone8,2",  "N66AP",  "iPhone 6s Plus" },
    { "iPhone8,4",  "N69AP",  "iPhone SE"      },
    { "iPhone9,1",  "D10AP",  "iPhone 7"       },
    { "iPhone9,2",  "D11AP",  "iPhone 7 Plus"  },
    { "iPhone9,3",  "D101AP", "iPhone 7"       },
    { "iPhone9,4",  "D111AP", "iPhone 7 Plus"  },
    { "iPhone10,1", "D20AP",  "iPhone 8"       },
    { "iPhone10,2", "D21AP",  "iPhone 8 Plus"  },
    { "iPhone10,3", "D22AP",  "iPhone X"       },
    { "iPhone10,4", "D201AP", "iPhone 8"       },
    { "iPhone10,5", "D211AP", "iPhone 8 Plus"  },
    { "iPhone10,6", "D221AP", "iPhone X"       },
};

NSUInteger PSProfileCount(void) {
    return sizeof(kProfiles) / sizeof(kProfiles[0]);
}

PSProfile PSProfileAtIndex(NSUInteger index) {
    return kProfiles[index % PSProfileCount()];
}
