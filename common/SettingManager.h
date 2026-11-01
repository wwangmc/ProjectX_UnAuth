#import <Foundation/Foundation.h>

@interface SettingManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, strong) NSString *carrierCountryCode;
@property (nonatomic, strong) NSString *minVersion;
@property (nonatomic, strong) NSString *maxVersion;
@property (nonatomic, copy) NSDictionary *options;
- (BOOL)saveToPrefs;
- (void)loadFromPrefs;
@end
