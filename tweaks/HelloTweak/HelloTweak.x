#import <UIKit/UIKit.h>

// Scaffold only. The point here is proving the toolchain and the repo pipeline
// line up; replace this hook with whatever you actually want to change.
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    NSLog(@"[HelloTweak] SpringBoard launched - hook is live");
}

%end
