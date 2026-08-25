#import <Foundation/Foundation.h>

typedef struct {
    const char *machine;    // hw.machine, e.g. "iPhone10,3"
    const char *board;      // hw.model board id, e.g. "D22AP"
    const char *marketing;  // human-readable, for the log line only
    uint64_t memsize;       // hw.memsize, must match the claimed model
    int ncpu;               // hw.ncpu, likewise
} PSProfile;

// Limited to the two iPhone X variants, and that is a deliberate reduction.
//
// Reporting an iPhone 6s while UIScreen still returns 1125x2436 at 3x describes
// a device Apple never built. Spoofing the screen too would wreck app layout,
// so the only coherent option is to stop lying about the model: an honest
// iPhone X is one of tens of millions, while an impossible pairing is a
// population of one and is a STRONGER identifier than no spoofing at all.
//
// The privacy win was never the model. It is the per-app IDFA, IDFV and
// keychain namespace, and those are untouched by this.
//
// 10,3 is the global iPhone X and 10,6 the variant sold in some markets; they
// are physically identical, so either is coherent with your hardware.
NSUInteger PSProfileCount(void);
PSProfile PSProfileAtIndex(NSUInteger index);
