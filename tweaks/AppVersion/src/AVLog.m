#import "AVLog.h"

static NSString *AVResolvePath(void) {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Preferred: readable over issh without hunting for a container UUID.
    NSString *shared = @"/var/jb/tmp/appversion.log";
    if ([fm createFileAtPath:shared contents:nil attributes:nil] ||
        [fm isWritableFileAtPath:shared]) {
        return shared;
    }

    // Fallback inside the app's own container. Still findable, because the
    // header line records wherever we ended up.
    NSString *fallback = [NSTemporaryDirectory()
                          stringByAppendingPathComponent:@"appversion.log"];
    NSLog(@"[AppVersion] /var/jb/tmp not writable, logging to %@", fallback);
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
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        stamp = [[NSDateFormatter alloc] init];
        stamp.dateFormat = @"HH:mm:ss.SSS";
    });

    NSString *line = [NSString stringWithFormat:@"%@  %@\n",
                      [stamp stringFromDate:[NSDate date]], body];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    // Append via a file handle rather than rewriting the whole file: the App
    // Store makes many of these calls and a read-modify-write would both lose
    // lines and grow quadratically.
    static dispatch_queue_t queue;
    static dispatch_once_t queueToken;
    dispatch_once(&queueToken, ^{
        queue = dispatch_queue_create("com.romeo.appversion.log",
                                      DISPATCH_QUEUE_SERIAL);
    });

    dispatch_async(queue, ^{
        NSFileHandle *handle =
            [NSFileHandle fileHandleForWritingAtPath:AVLogPath()];
        if (!handle) {
            [[NSFileManager defaultManager] createFileAtPath:AVLogPath()
                                                    contents:data
                                                  attributes:nil];
            return;
        }
        @try {
            [handle seekToEndOfFile];
            [handle writeData:data];
        } @catch (NSException *exception) {
            NSLog(@"[AppVersion] log write failed: %@", exception.name);
        }
        [handle closeFile];
    });
}
