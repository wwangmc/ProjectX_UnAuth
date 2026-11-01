#import <Foundation/Foundation.h>
#import "PhoneInfo.h"

@interface DataGenManager : NSObject
+ (instancetype)sharedManager;
- (PhoneInfo *) generatePhoneInfo;
- (PhoneInfo *)generatePhoneInfoWithVersion:(NSString *)version model:(NSString *)model;
// - (IosVersion *) generateIOSVersion;
@end
