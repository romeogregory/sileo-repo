#import <Foundation/Foundation.h>

typedef struct {
    const char *machine;    // hw.machine, e.g. "iPhone10,3"
    const char *board;      // hw.model board id, e.g. "D22AP"
    const char *marketing;  // human-readable, for the log line only
} PSProfile;

// Profiles are deliberately limited to A9-A11 hardware — the only devices that
// can run the iOS 16.7 branch. Reporting an iPhone 15 while the OS reports
// 16.7.x is a pairing Apple never shipped, and an impossible pairing is a
// STRONGER fingerprint than not spoofing at all: it puts you in a population of
// one. Coherence is the whole point of this table.
//
// machine and board are always read from the same entry so they cannot
// disagree with each other. NOTE: the board ids below are from memory and are
// worth verifying against real devices — a wrong machine/board pairing is
// exactly the incoherence this table exists to avoid.
NSUInteger PSProfileCount(void);
PSProfile PSProfileAtIndex(NSUInteger index);
