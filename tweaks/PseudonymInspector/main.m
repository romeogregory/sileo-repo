#import <UIKit/UIKit.h>
#import "PIViewController.h"

@interface PIAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation PIAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    UINavigationController *nav = [[UINavigationController alloc]
        initWithRootViewController:[[PIViewController alloc] init]];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // No storyboard: the delegate class is named explicitly instead.
        return UIApplicationMain(argc, argv, nil, @"PIAppDelegate");
    }
}
