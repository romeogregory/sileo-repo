#import "AVLog.h"

#import <fcntl.h>
#import <unistd.h>

// A private directory, created 0700 and owned by mobile in postinst.
//
// NOT /var/jb/tmp. That is world-writable, which made the log readable by any
// process on the device and let anything pre-create the file as a symlink for
// our appends to follow.
static NSString *const kLogDirectory =
    @"/var/jb/var/mobile/Library/Logs/AppVersion";

static NSString *AVResolvePath(void) {
    NSString *preferred =
        [kLogDirectory stringByAppendingPathComponent:@"appversion.log"];

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:kLogDirectory isDirectory:&isDirectory] &&
        isDirectory && [fm isWritableFileAtPath:kLogDirectory]) {
        return preferred;
    }

    // The app's own container: private to this app by construction, so it is
    // the safer fallback even though it takes a find to locate over SSH. The
    // header line records wherever we ended up.
    NSString *fallback = [NSTemporaryDirectory()
                          stringByAppendingPathComponent:@"appversion.log"];
    NSLog(@"[AppVersion] %@ unavailable, logging to %@", kLogDirectory, fallback);
    return fallback;
}

NSString *AVLogPath(void) {
    static NSString *path;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        path = AVResolvePath();
    });
    return path;
}

void AVLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static NSDateFormatter *stamp;
    static dispatch_queue_t queue;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        stamp = [[NSDateFormatter alloc] init];
        stamp.dateFormat = @"HH:mm:ss.SSS";
        queue = dispatch_queue_create("com.romeo.appversion.log",
                                      DISPATCH_QUEUE_SERIAL);
    });

    NSString *line = [NSString stringWithFormat:@"%@  %@\n",
                      [stamp stringFromDate:[NSDate date]], body];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    dispatch_async(queue, ^{
        // O_NOFOLLOW refuses to open the final path component if it is a
        // symlink, and 0600 keeps the file readable only by its owner. Together
        // these are why this uses open() rather than NSFileHandle, which
        // follows links and inherits the directory's permissions.
        int fd = open([AVLogPath() fileSystemRepresentation],
                      O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0600);
        if (fd < 0) {
            NSLog(@"[AppVersion] log open failed (errno %d)", errno);
            return;
        }
        write(fd, data.bytes, data.length);
        close(fd);
    });
}
