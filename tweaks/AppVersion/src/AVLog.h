#import <Foundation/Foundation.h>

// Logs to a file rather than NSLog. Reading NSLog from a sandboxed App Store
// needs a syslog viewer on the device; a file under /var/jb/tmp can be read
// straight over issh, which is the whole point of a discovery build.
//
// AVLogPath resolves once and is reported in the header line, so if the
// preferred location is not writable the fallback is still findable.
void AVLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *AVLogPath(void);

// Records the version id the App Store last asked for, so the Settings pane can
// show it. This is why the value does not have to be looked up with ipatool or
// read out of a terminal: the tweak already observes it.
void AVRecordLastSeen(NSString *value);
NSString *AVLastSeenPath(void);
