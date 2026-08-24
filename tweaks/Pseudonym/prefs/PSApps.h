#import <Foundation/Foundation.h>

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationType;
@end

// Enumerating installed apps, with the failure modes reported rather than
// collapsed into an empty array.
@interface PSApps : NSObject

@property (nonatomic, readonly) BOOL workspaceResolved;
@property (nonatomic, readonly) NSUInteger reportedCount;
@property (nonatomic, readonly) NSString *failureReason;
@property (nonatomic, readonly) NSArray *apps;

+ (instancetype)enumerate;

@end
