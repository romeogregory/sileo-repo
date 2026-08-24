#import <UIKit/UIKit.h>

// Reads this process's own device identity through public APIs and shows it.
//
// The point is independence: nothing here shares code with the tweak, so the
// values are whatever the hooks genuinely produce in a real sandboxed app. With
// Pseudonym disabled for this bundle it prints ground truth; with it enabled the
// values change. That difference is the only actual proof the spoof works.
@interface PIViewController : UITableViewController
@end
