#import <Foundation/Foundation.h>

// Buy parameters carry Apple account identifiers - guid, DSID, session tokens.
// The useful thing to log is the SHAPE of the request, so key names and value
// lengths survive and everything outside a tight allowlist is dropped.
//
// Accepts a query string or a dictionary, because the four purchase classes on
// this build disagree about which they use.
NSString *AVRedact(id parameters);

// The one field this tweak exists to change.
extern NSString *const AVVersionKey;
