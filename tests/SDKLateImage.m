#import <Foundation/Foundation.h>
#import <dlfcn.h>
static int initializationCount;
static int otherCounts[5];
int PXSDKFixtureInitializationCount(void) { return initializationCount; }
int PXSDKFixtureOtherLoadCount(unsigned index) { return index<5?otherCounts[index]:-1; }
@interface PDXC : NSObject
@end
@interface YjAxOGE4YTAwODQ5MjMxZTY2_EC : NSObject @end
@implementation YjAxOGE4YTAwODQ5MjMxZTY2_EC
+ (void)load { otherCounts[0]++; }
@end
@interface MWFmMDM5OTk2ZTdkMWY4ZmUy_EC : NSObject @end
@implementation MWFmMDM5OTk2ZTdkMWY4ZmUy_EC
+ (void)load { otherCounts[1]++; }
@end
@interface NGMzNzhjNmI0NDQyMzdiNTc0_EC : NSObject @end
@implementation NGMzNzhjNmI0NDQyMzdiNTc0_EC
+ (void)load { otherCounts[2]++; }
@end
@interface NzY1YjdiMzkwYzc2N2U5YWMz_EC : NSObject @end
@implementation NzY1YjdiMzkwYzc2N2U5YWMz_EC
+ (void)load { otherCounts[3]++; }
@end
@interface PXUnrelatedSDKLoad : NSObject @end
@implementation PXUnrelatedSDKLoad
+ (void)load {
    otherCounts[4]++;
    const char *inner=getenv("PXSDK_TEST_NESTED_IMAGE");
    if (inner) dlopen(inner,RTLD_NOW|RTLD_GLOBAL);
}
@end
@implementation PDXC
+ (void)load { initializationCount++; }
- (BOOL)pc { return YES; }
- (void)disable_gdb {}
@end
@interface OneSignalJailbreakDetection : NSObject
@end
@implementation OneSignalJailbreakDetection
+ (BOOL)isJailbroken { return YES; }
@end
