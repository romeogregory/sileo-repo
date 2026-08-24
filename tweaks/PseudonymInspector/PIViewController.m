#import "PIViewController.h"
#import <AdSupport/AdSupport.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>

@interface PIViewController ()
@property (nonatomic, strong) NSArray *sections;
@end

@implementation PIViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Inspector";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(reload)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                      target:self
                                                      action:@selector(copyAll)];
    [self reload];
}

#pragma mark - Reading the device

static NSString *PISysctl(const char *name) {
    size_t length = 0;
    if (sysctlbyname(name, NULL, &length, NULL, 0) != 0 || length == 0) {
        return @"unavailable";
    }
    char *buffer = malloc(length);
    if (!buffer) return @"unavailable";

    NSString *value = @"unavailable";
    if (sysctlbyname(name, buffer, &length, NULL, 0) == 0) {
        value = [NSString stringWithUTF8String:buffer] ?: @"unavailable";
    }
    free(buffer);
    return value;
}

static NSString *PIUnameMachine(void) {
    struct utsname system;
    if (uname(&system) != 0) return @"unavailable";
    return [NSString stringWithUTF8String:system.machine] ?: @"unavailable";
}

static NSString *PIAdvertisingID(void) {
    ASIdentifierManager *manager = [ASIdentifierManager sharedManager];
    NSUUID *identifier = manager.advertisingIdentifier;
    NSString *value = identifier.UUIDString ?: @"nil";

    // All zeros is what iOS returns when App Tracking Transparency was denied.
    // Calling that out matters: it is the privacy-preserving answer, and a
    // plausible-looking UUID here would be strictly worse.
    if ([value isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
        return @"zeroed (ATT denied)";
    }
    return value;
}

- (void)reload {
    UIDevice *device = [UIDevice currentDevice];

    self.sections = @[
        @{@"title": @"This app",
          @"rows": @[
              @[@"Bundle ID", [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown"],
          ]},
        @{@"title": @"Identifiers",
          @"rows": @[
              @[@"IDFA", PIAdvertisingID()],
              @[@"IDFV", device.identifierForVendor.UUIDString ?: @"nil"],
          ]},
        @{@"title": @"Hardware",
          @"rows": @[
              @[@"hw.machine", PISysctl("hw.machine")],
              @[@"hw.model", PISysctl("hw.model")],
              @[@"uname machine", PIUnameMachine()],
          ]},
        @{@"title": @"Device",
          @"rows": @[
              @[@"Name", device.name ?: @"unknown"],
              @[@"Model", device.model ?: @"unknown"],
              @[@"System", [NSString stringWithFormat:@"%@ %@",
                            device.systemName, device.systemVersion]],
          ]},
    ];
    [self.tableView reloadData];
}

- (void)copyAll {
    NSMutableString *dump = [NSMutableString string];
    for (NSDictionary *section in self.sections) {
        [dump appendFormat:@"[%@]\n", section[@"title"]];
        for (NSArray *row in section[@"rows"]) {
            [dump appendFormat:@"%@: %@\n", row[0], row[1]];
        }
        [dump appendString:@"\n"];
    }
    [UIPasteboard generalPasteboard].string = dump;

    UIAlertController *done = [UIAlertController
        alertControllerWithTitle:@"Copied"
                         message:@"All values are on the clipboard."
                  preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"OK"
                                             style:UIAlertActionStyleDefault
                                           handler:nil]];
    [self presentViewController:done animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    return [self.sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView
titleForHeaderInSection:(NSInteger)section {
    return self.sections[section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView
titleForFooterInSection:(NSInteger)section {
    if (section != (NSInteger)self.sections.count - 1) return nil;
    return @"Enable this bundle ID in Settings > Pseudonym, force-quit this app, "
           @"then reopen it. Every value above should change except the system "
           @"version, which is left alone on purpose so it cannot contradict the "
           @"reported hardware.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const identifier = @"PIValueCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
        // UUIDs do not fit on one line on an iPhone X, and a truncated
        // identifier is useless for comparing before and after.
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.font =
            [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    NSArray *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    cell.textLabel.text = row[0];
    cell.detailTextLabel.text = row[1];
    return cell;
}

@end
