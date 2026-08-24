#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

// Everything in one pane, built in code. A PSLinkCell to a second controller
// resolved to the wrong class in the sibling tweak and produced a blank page,
// so this does not use one.
//
// The point of this pane is that nothing here needs a terminal: the version the
// App Store last asked for is shown, the override is a text field, and the log
// goes to the clipboard with one tap.
@interface AVRootListController : PSListController
@end

static NSString *const kLogDirectory =
    @"/var/jb/var/mobile/Library/Logs/AppVersion";
static NSString *const kPrefsPath =
    @"/var/jb/var/mobile/Library/Preferences/com.romeo.appversion.plist";

@implementation AVRootListController

#pragma mark - Lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // These rows are a view onto files that change while this pane is not
    // visible, so the cache has to be dropped rather than trusted.
    _specifiers = nil;
    [self reloadSpecifiers];
}

#pragma mark - Files

+ (NSString *)logPath {
    return [kLogDirectory stringByAppendingPathComponent:@"appversion.log"];
}

+ (NSString *)lastSeenPath {
    return [kLogDirectory stringByAppendingPathComponent:@"lastseen.txt"];
}

+ (NSString *)lastSeen {
    NSString *raw = [NSString stringWithContentsOfFile:[self lastSeenPath]
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    raw = [raw stringByTrimmingCharactersInSet:
           [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return raw.length ? raw : nil;
}

+ (NSArray *)logTail:(NSUInteger)count {
    NSString *contents = [NSString stringWithContentsOfFile:[self logPath]
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL];
    if (!contents.length) return @[];

    NSMutableArray *lines = [[contents componentsSeparatedByString:@"\n"] mutableCopy];
    [lines removeObject:@""];
    if (lines.count > count) {
        [lines removeObjectsInRange:NSMakeRange(0, lines.count - count)];
    }
    return lines;
}

#pragma mark - Preferences

- (NSMutableDictionary *)prefs {
    NSMutableDictionary *prefs =
        [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath];
    return prefs ?: [NSMutableDictionary dictionary];
}

- (id)text:(PSSpecifier *)specifier {
    return [self prefs][[specifier propertyForKey:@"psKey"]] ?: @"";
}

- (void)setText:(id)value specifier:(PSSpecifier *)specifier {
    NSMutableDictionary *prefs = [self prefs];
    NSString *key = [specifier propertyForKey:@"psKey"];
    NSString *trimmed = [value stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length) {
        prefs[key] = trimmed;
    } else {
        [prefs removeObjectForKey:key];
    }
    [prefs writeToFile:kPrefsPath atomically:YES];
}

- (id)infoValue:(PSSpecifier *)specifier {
    return [specifier propertyForKey:@"psInfoValue"];
}

#pragma mark - Specifiers

static PSSpecifier *AVGroup(NSString *name, NSString *footer) {
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:name];
    if (footer) [group setProperty:footer forKey:@"footerText"];
    return group;
}

static PSSpecifier *AVInfo(id target, NSString *label, NSString *value) {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label
                                                       target:target
                                                          set:NULL
                                                          get:@selector(infoValue:)
                                                       detail:nil
                                                         cell:PSTitleValueCell
                                                         edit:nil];
    [spec setProperty:value forKey:@"psInfoValue"];
    return spec;
}

static PSSpecifier *AVButton(id target, NSString *label, SEL action) {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label
                                                       target:target
                                                          set:NULL
                                                          get:NULL
                                                       detail:nil
                                                         cell:PSButtonCell
                                                         edit:nil];
    spec->action = action;
    return spec;
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    NSString *seen = [[self class] lastSeen];
    NSMutableArray *specs = [NSMutableArray array];

    NSString *version = [[NSBundle bundleForClass:[self class]]
                         objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    BOOL recorded = [[NSFileManager defaultManager]
                     fileExistsAtPath:[[self class] lastSeenPath]];

    [specs addObject:AVGroup(@"Current",
        @"The version the App Store last asked Apple for. It is recorded "
        @"automatically when you tap Install or Update, so there is nothing to "
        @"look up by hand.")];
    [specs addObject:AVInfo(self, @"Tweak version", version ?: @"unknown")];
    [specs addObject:AVInfo(self, @"Last seen", seen ?: @"none yet")];
    // Distinguishes "never written" from "written but unreadable", which look
    // identical from the row above.
    [specs addObject:AVInfo(self, @"Record file",
                            recorded ? @"present" : @"not created yet")];

    [specs addObject:AVGroup(@"Override",
        @"Leave empty to observe only. Set a version id and the App Store will "
        @"install that build instead - Apple still checks your purchase history, "
        @"so this only reaches versions your Apple ID can already get. Delete "
        @"the app first, then install it from the App Store.")];

    PSSpecifier *field =
        [PSSpecifier preferenceSpecifierNamed:@"Version id"
                                       target:self
                                          set:@selector(setText:specifier:)
                                          get:@selector(text:)
                                       detail:nil
                                         cell:PSEditTextCell
                                         edit:nil];
    [field setProperty:@"TargetVersionId" forKey:@"psKey"];
    [field setProperty:seen ?: @"846675561" forKey:@"placeholder"];
    [field setProperty:@(UIKeyboardTypeNumberPad) forKey:@"keyboardType"];
    [field setProperty:@NO forKey:@"autoCaps"];
    [field setProperty:@NO forKey:@"autoCorrection"];
    [specs addObject:field];

    [specs addObject:AVGroup(@"Log", nil)];
    [specs addObject:AVButton(self, @"Copy Log to Clipboard",
                              @selector(copyLog))];
    [specs addObject:AVButton(self, @"Clear Log", @selector(clearLog))];

    NSArray *tail = [[self class] logTail:8];
    [specs addObject:AVGroup(@"Recent", tail.count
        ? @"Newest last. Force-quit the App Store after changing anything above."
        : @"Nothing logged yet. Open the App Store and tap Install on any app.")];
    for (NSString *line in tail) {
        // Timestamp as the label, message as the value: the values are long and
        // a plain info row wraps them, where a header would truncate.
        NSRange split = [line rangeOfString:@"  "];
        NSString *stamp = split.location == NSNotFound
            ? @"-" : [line substringToIndex:split.location];
        NSString *body = split.location == NSNotFound
            ? line : [line substringFromIndex:split.location + 2];
        [specs addObject:AVInfo(self, stamp, body)];
    }

    _specifiers = specs;
    return _specifiers;
}

#pragma mark - Actions

- (void)copyLog {
    NSString *contents =
        [NSString stringWithContentsOfFile:[[self class] logPath]
                                  encoding:NSUTF8StringEncoding
                                     error:NULL];
    if (!contents.length) {
        [self alert:@"Nothing to Copy" message:@"The log is empty."];
        return;
    }
    [UIPasteboard generalPasteboard].string = contents;
    [self alert:@"Copied"
        message:[NSString stringWithFormat:@"%lu characters on the clipboard.",
                 (unsigned long)contents.length]];
}

- (void)clearLog {
    [@"" writeToFile:[[self class] logPath]
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:NULL];
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
