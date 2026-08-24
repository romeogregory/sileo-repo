#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "PSPrefsStore.h"

@interface PSRootListController : PSListController
@end

@implementation PSRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// Root.plist drives the layout, but the values live in a plain plist rather
// than a CFPreferences domain, so the standard read/write path is redirected.
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    if ([specifier.properties[@"key"] isEqualToString:@"Enabled"]) {
        return @([PSPrefsStore globalEnabled]);
    }
    return specifier.properties[@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if ([specifier.properties[@"key"] isEqualToString:@"Enabled"]) {
        [PSPrefsStore setGlobalEnabled:[value boolValue]];
    }
}

- (void)regenerateAll {
    UIAlertController *confirm = [UIAlertController
        alertControllerWithTitle:@"Regenerate All Identities"
                         message:@"Every enabled app will see a brand-new device "
                                 @"next time it launches. Apps that stored a "
                                 @"login will sign you out."
                  preferredStyle:UIAlertControllerStyleAlert];

    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];

    [confirm addAction:[UIAlertAction
        actionWithTitle:@"Regenerate"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    NSInteger changed = [PSPrefsStore bumpAllEnabledGenerations];
                    [self reportRegenerated:changed];
                }]];

    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)reportRegenerated:(NSInteger)changed {
    NSString *message = changed
        ? [NSString stringWithFormat:@"%ld app%@ reset. Force-quit them to take "
                                     @"effect.", (long)changed,
                                     changed == 1 ? @"" : @"s"]
        : @"No apps are enabled yet.";

    UIAlertController *done = [UIAlertController
        alertControllerWithTitle:@"Done"
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK"
                                             style:UIAlertActionStyleDefault
                                           handler:nil]];
    [self presentViewController:done animated:YES completion:nil];
}

@end
