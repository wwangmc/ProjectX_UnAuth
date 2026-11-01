#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "PXHookSupport.h"
#import "PXSDKCompatibility.h"
#import "PXSDKEarlyLoad.h"
static PhoneInfo *phone;
static NSMutableDictionary *originals;
static NSUInteger checks;
#ifdef PX_SDK_NATIVE_HOOKS
extern int DobbyHook(void *,void *,void **);
#endif
void MSHookFunction(void *target,void *replacement,void **original) {
    *original=NULL;
#ifdef PX_SDK_NATIVE_HOOKS
    if (!getenv("PXSDK_TEST_DISABLE_EARLY") && !getenv("PXSDK_TEST_DELAY_EARLY") && DobbyHook(target,replacement,original)!=0) *original=NULL;
#endif
}
// Exercise the checked exported-bridge resolver, not a guessed private symbol.
void *MSFindSymbol(void *image,const char *name) { return NULL; }
static bool LateInstaller(void *target,void *replacement,void **original) {
    MSHookFunction(target,replacement,original); return *original!=NULL;
}
#define CHECK(x) do { checks++; if (!(x)) { fprintf(stderr,"LOADER FAIL %d: %s\n",__LINE__,#x); abort(); } } while(0)
// Runtime hook backend for exercising the production image observer on macOS.
BOOL PXInstallMethod(Class cls,SEL sel,IMP hook,const char *type,unsigned count) {
    if (!originals) originals=[NSMutableDictionary dictionary];
    NSString *key=[NSString stringWithFormat:@"%p:%s",cls,sel_getName(sel)];
    Method method=class_getInstanceMethod(cls,sel); if (!method) return NO;
    if (originals[key]) return YES;
    originals[key]=[NSValue valueWithPointer:method_getImplementation(method)];
    if (!class_addMethod(cls,sel,hook,method_getTypeEncoding(method))) method_setImplementation(method,hook);
    return YES;
}
IMP PXOriginalForClass(Class cls,SEL sel) { return [originals[[NSString stringWithFormat:@"%p:%s",cls,sel_getName(sel)]] pointerValue]; }
@implementation DataManager
+ (instancetype)sharedManager { static DataManager *d; if (!d) d=[DataManager new]; return d; }
- (PhoneInfo *)getPhoneInfo { return phone; }
- (void)freshCacheData {}
@end
int main(int argc,const char **argv) { @autoreleasepool {
    CHECK(argc==2 || argc==3); CHECK(objc_lookUpClass("OneSignalJailbreakDetection")==Nil);
    BOOL threaded=argc==3 && !strcmp(argv[2],"--threaded-load");
    BOOL enabled=argc==2 || threaded;
    phone=[PhoneInfo new]; phone.runtime=@{@"sdkCompatibility":@YES,@"maskEnvironment":@YES,@"sdkSuppressInitialization":@(enabled)};
    PXSDKConfigure(^PhoneInfo *{ return phone; },^IMP(Class cls,SEL sel,IMP imp,const char *type,unsigned count) {
        return PXInstallMethod(cls,sel,imp,type,count)?PXOriginalForClass(cls,sel):NULL;
    });
    __block void *handle=NULL;
    if (threaded) {
        dispatch_semaphore_t done=dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
            handle=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL); dispatch_semaphore_signal(done);
        });
        NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:3];
        while (dispatch_semaphore_wait(done,DISPATCH_TIME_NOW) && limit.timeIntervalSinceNow>0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    } else handle=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    CHECK(handle!=NULL);
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
    while (![PXSDKCompatibilityReport()[@"OneSignalJailbreakDetection +isJailbroken"][@"status"] isEqual:@"installed"] && deadline.timeIntervalSinceNow>0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK([PXSDKCompatibilityReport()[@"OneSignalJailbreakDetection +isJailbroken"][@"status"] isEqual:@"installed"]);
    Class cls=objc_lookUpClass("OneSignalJailbreakDetection");
    CHECK(((BOOL(*)(id,SEL))objc_msgSend)(cls,sel_registerName("isJailbroken"))==NO);
    int (*loadCount)(void)=dlsym(handle,"PXSDKFixtureInitializationCount"); CHECK(loadCount!=NULL);
    BOOL early=PXSDKEarlyLoadDispatcherABI()!=PXSDKLoadUnknown;
#ifdef PX_SDK_NATIVE_HOOKS
    if (!getenv("PXSDK_TEST_DISABLE_EARLY") && !getenv("PXSDK_TEST_DELAY_EARLY")) CHECK(early);
#endif
    int observed=loadCount(); CHECK(observed==(early && enabled?0:1));
    int (*otherCounts)(unsigned)=dlsym(handle,"PXSDKFixtureOtherLoadCount"); CHECK(otherCounts!=NULL);
    for (unsigned i=0;i<4;i++) CHECK(otherCounts(i)==(early && enabled?0:1));
    CHECK(otherCounts(4)==1);
    if (getenv("PXSDK_TEST_NESTED_IMAGE")) {
        int (*inner)(void)=dlsym(RTLD_DEFAULT,"PXSDKInnerInitializationCount"); CHECK(inner!=NULL); CHECK(inner()==1);
    }
    PXSDKEarlyLoadStatus coverage=PXSDKGetEarlyLoadStatus("PDXC");
    if (early) {
        CHECK(coverage.installed && coverage.automaticCalls==1);
        CHECK(coverage.suppressedCalls==(enabled?1:0));
        CHECK(coverage.forwardedCalls==(enabled?0:1));
        CHECK(![PXSDKCompatibilityReport()[@"PDXC +load"][@"loadTimingUnverified"] boolValue]);
    } else CHECK([PXSDKCompatibilityReport()[@"PDXC +load"][@"loadTimingUnverified"] boolValue]);
    if (getenv("PXSDK_TEST_DELAY_EARLY")) {
        unsetenv("PXSDK_TEST_DELAY_EARLY");
        CHECK(PXSDKStartEarlyLoad(LateInstaller,NULL));
        CHECK(loadCount()==observed); // Historical initialization isn't replayed.
        CHECK(PXSDKGetEarlyLoadStatus("PDXC").automaticCalls==0);
        CHECK([PXSDKCompatibilityReport()[@"PDXC +load"][@"loadTimingUnverified"] boolValue]);
    }
    ((void(*)(id,SEL))objc_msgSend)(objc_lookUpClass("PDXC"),sel_registerName("load")); CHECK(loadCount()==observed+(enabled?0:1));
    phone.runtime=@{};
    CHECK(((BOOL(*)(id,SEL))objc_msgSend)(cls,sel_registerName("isJailbroken"))==YES);
    unsigned before=loadCount();
    ((void(*)(id,SEL))objc_msgSend)(objc_lookUpClass("PDXC"),sel_registerName("load")); CHECK(loadCount()==before+1);
    printf("PASS: %lu SDK loader checks (early: %d, enabled: %d, initial +load count: %d)\n",(unsigned long)checks,early,enabled,observed);
} return 0; }
