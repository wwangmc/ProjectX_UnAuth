#import "SettingManager.h"
#import "PXConfiguration.h"
static NSDictionary *PXDefaultOptions(void) {
    return @{@"models":@[],@"versions":@[],@"carriers":@[],@"wifiPercent":@50,@"fiveGPercent":@50,
        @"useLocalModelOS":@NO,@"requireRealRAM":@NO,@"clearPasteboardOnNewPhone":@NO,@"clearPasteboardOnSwitch":@NO,
        @"stopAtLastProfile":@YES,@"clearRelatedContainers":@NO,@"backupKeychain":@NO,
        @"preservedPaths":@[],@"runtimeTemplate":@{},@"idfaEndpoint":@"",@"fallbackRandomIDFA":@NO};
}

@implementation SettingManager
+ (instancetype)sharedManager {
    static SettingManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (BOOL)saveToPrefs {
    if (!PXValidateOptions(self.options ?: @{}, NULL)) return NO;
    NSDictionary *dict = @{
        @"carrierCountryCode": self.carrierCountryCode ?: @"US",
        @"minVersion": self.minVersion ?: @"14.0",
        @"maxVersion": self.maxVersion ?: @"18.6",
        @"options": self.options ?: @{}
    };

    CFPreferencesSetValue(
        CFSTR("setting"),
        (__bridge CFPropertyListRef)dict,
        CFSTR("com.projectx.setting"),
        CFSTR("mobile"),
        kCFPreferencesAnyHost
    );


    BOOL success = CFPreferencesSynchronize(
        CFSTR("com.projectx.setting"),
        CFSTR("mobile"),
        kCFPreferencesAnyHost
    );

    return success;
}

- (void)loadFromPrefs {
    CFPreferencesSynchronize(CFSTR("com.projectx.setting"),CFSTR("mobile"),kCFPreferencesAnyHost);
    CFPropertyListRef value =
        CFPreferencesCopyValue(
            CFSTR("setting"),
            CFSTR("com.projectx.setting"),
            CFSTR("mobile"),          // ⚠️ 不用 CurrentUser
            kCFPreferencesAnyHost
        );


    if (!value || CFGetTypeID(value) != CFDictionaryGetTypeID()) {
        if (value) CFRelease(value);
        self.carrierCountryCode = @"US";
        self.minVersion = @"14.0";
        self.maxVersion = @"18.6";
        self.options = PXDefaultOptions();
        return;
    }

    NSDictionary *dict = CFBridgingRelease(value);
    self.carrierCountryCode = [dict[@"carrierCountryCode"] isKindOfClass:NSString.class] ? dict[@"carrierCountryCode"] : @"US";
    self.minVersion = [dict[@"minVersion"] isKindOfClass:NSString.class] ? dict[@"minVersion"] : @"14.0";
    self.maxVersion = [dict[@"maxVersion"] isKindOfClass:NSString.class] ? dict[@"maxVersion"] : @"18.6";
    NSMutableDictionary *options=[PXDefaultOptions() mutableCopy];
    [options addEntriesFromDictionary:PXValidateOptions(dict[@"options"] ?: @{}, NULL) ?: @{}];
    self.options=options;
}

@end
