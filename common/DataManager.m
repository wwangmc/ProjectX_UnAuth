#import "DataManager.h"
#import "DaemonApiManager.h"

static void PXPhoneInfoChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                              const void *object, CFDictionaryRef userInfo) {
    [(__bridge DataManager *)observer freshCacheData];
}

@interface DataManager()
@property (nonatomic, strong) PhoneInfo *phoneInfo;
@end

@implementation DataManager
static __thread BOOL PXInitializingDataManager;
+ (instancetype)sharedManager {
    // CFPreferences can call hooked file/NSBundle APIs while the cache is first
    // loaded. Nested hooks must use their original API rather than reenter once.
    if (PXInitializingDataManager) return nil;
    static DataManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    PXInitializingDataManager=YES;
    @try {
        dispatch_once(&onceToken, ^{ sharedInstance = [[self alloc] init]; });
    } @finally { PXInitializingDataManager=NO; }
    return sharedInstance;
}
-(instancetype) init{
    self = [super init];
    if (self) {
        [self freshCacheData];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self,
            PXPhoneInfoChanged, CFSTR("com.projectx.phoneinfo.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}
- (PhoneInfo *) getPhoneInfo{
    @synchronized (self) { return _phoneInfo; }
}
- (void) freshCacheData{
    CFPreferencesSynchronize(CFSTR("com.projectx.phoneinfo"), kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
    PhoneInfo *info = [PhoneInfo loadFromPrefs];
    @synchronized (self) { _phoneInfo = info; }
}
- (void)dealloc { CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self); }
@end
