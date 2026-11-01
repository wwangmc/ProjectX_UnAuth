#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <limits.h>
#import "PXSDKCompatibility.h"
#import "PXSDKEarlyLoad.h"
static NSUInteger checks,installs;
#define CHECK(x) do { checks++; if (!(x)) { fprintf(stderr,"ABI FAIL %d: %s\n",__LINE__,#x); abort(); } } while(0)
#define RETURN(name,type,value) static type name(id self,SEL cmd) { return (type)(value); }
RETURN(RB,_Bool,1) RETURN(Rc,char,-7) RETURN(RC,unsigned char,249)
RETURN(Rs,short,-1234) RETURN(RS,unsigned short,65000)
RETURN(Ri,int,INT_MIN+123) RETURN(RI,unsigned int,UINT_MAX-17)
RETURN(Rl,long,LONG_MIN+12345) RETURN(RL,unsigned long,ULONG_MAX-12345)
RETURN(Rq,long long,LLONG_MIN+444) RETURN(RQ,unsigned long long,ULLONG_MAX-555)
static float TimeFloat(id self,SEL cmd) { return 3.25f; }
static id Dummy(id self,SEL cmd) { return @"unchanged"; }
static Class NewClass(const char *name) {
    Class cls=objc_lookUpClass(name);
    if (!cls) { cls=objc_allocateClassPair(NSObject.class,name,0); CHECK(cls!=Nil); objc_registerClassPair(cls); }
    return cls;
}
int main(void) { @autoreleasepool {
    // Both audited dispatcher bridge forms; mutation must fail closed rather
    // than selecting an unrelated branch or guessing a private function ABI.
    const uint32_t bridge[]={0xd503237f,0xd100c3ff,0xa9027bfd,0x910083fd,
        0xa90003e1,0xa9017fff,0x910003e0,0x94000040,0xa9427bfd,0x9100c3ff,0xd65f0fff};
    uintptr_t target=0; PXSDKLoadABI abi=PXSDKLoadUnknown;
    CHECK(PXSDKDecodeLoadBridge(bridge,11,0x200000,&target,&abi) && target==0x20011c && abi==PXSDKLoadInfo);
    const uint32_t legacy[]={0x14000040};
    CHECK(PXSDKDecodeLoadBridge(legacy,1,0x200000,&target,&abi) && target==0x200100 && abi==PXSDKLoadLegacy);
    const uint32_t negative[]={0x17ffffc0};
    CHECK(PXSDKDecodeLoadBridge(negative,1,0x200000,&target,&abi) && target==0x1fff00);
    for (unsigned i=0;i<6;i++) {
        uint32_t changed[11]; memcpy(changed,bridge,sizeof(bridge));
        const unsigned offsets[]={4,5,6,7,8,9};
        const uint32_t mutations[]={0xa90007e0,0xd503201f,0x910003e1,0xd63f0200,0x94000040,0xd503201f};
        changed[offsets[i]]=mutations[i]; CHECK(!PXSDKDecodeLoadBridge(changed,11,0x200000,&target,&abi));
    }
    CHECK(!PXSDKDecodeLoadBridge(bridge,33,0x200000,&target,&abi));
    CHECK(!PXSDKDecodeLoadBridge(NULL,0,0x200000,&target,&abi));
    PhoneInfo *phone=[PhoneInfo new];
    struct Case { const char *name,*sel,*type; BOOL meta; IMP imp; } cases[]={
        {"GADevice","isJailbroken","B@:",YES,(IMP)RB},
        {"MRDeviceUtils","isJB","c@:",YES,(IMP)Rc},
        {"MTRGDeviceUtils","isJB","C@:",YES,(IMP)RC},
        {"OneSignalJailbreakDetection","isJailbroken","s@:",YES,(IMP)Rs},
        {"UMUtils","isDeviceJailBreak","S@:",YES,(IMP)RS},
        {"MOBFDevice","hasJailBroken","i@:",YES,(IMP)Ri},
        {"OKBCydia","isJailbroken","I@:",YES,(IMP)RI},
        {"MobClick","isJailbroken","l@:",YES,(IMP)Rl},
        {"PPRiskDeviceData","isJailBroken","L@:",YES,(IMP)RL},
        {"ANSMetadata","computeIsJailbroken","q@:",NO,(IMP)Rq},
        {"BLYDevice","isJailbroken","Q@:",NO,(IMP)RQ}
    };
    NSMutableArray *receivers=[NSMutableArray array];
    for (unsigned i=0;i<11;i++) {
        Class cls=NewClass(cases[i].name);
        [receivers addObject:cases[i].meta?(id)cls:[cls new]];
        CHECK(class_addMethod(cases[i].meta?object_getClass(cls):cls,sel_registerName(cases[i].sel),cases[i].imp,cases[i].type));
    }
    Class tracker=NewClass("AppsFlyerTracker");
    CHECK(class_addMethod(tracker,sel_registerName("getTimePassedSinceLastLaunch"),(IMP)TimeFloat,"f@:"));
    struct Rejected { const char *name,*sel,*type; BOOL meta; } rejected[]={
        {"ABKLocationUtilities","isValidLocationAndAccurateEnough:","B@:@?",YES},
        {"ABKLocationUtilities","locationIsValidWithLatitude:longitude:","B@:ff",YES},
        {"RLMRealm","realmWithConfiguration:queue:error:","@@:@@^v",YES},
        {"HMDLaunchTimingUserTrace","startSpanWithTaskName:","v@:q",YES},
        {"AppsFlyerAES128Crypto","encrypt:withObject:","@?@:@@",YES},
        {"PluginShieldfraudPlugin","registerWithRegistrar:","v@:@@",YES}
    };
    for (unsigned i=0;i<6;i++) {
        Class cls=NewClass(rejected[i].name);
        CHECK(class_addMethod(rejected[i].meta?object_getClass(cls):cls,sel_registerName(rejected[i].sel),(IMP)Dummy,rejected[i].type));
    }
    PXSDKConfigure(^PhoneInfo *{ return phone; },^IMP(Class cls,SEL sel,IMP hook,const char *type,unsigned args) {
        installs++; return method_setImplementation(class_getInstanceMethod(cls,sel),hook);
    });
    PXSDKInstallTargets(); CHECK(installs==12);
    NSDictionary *report=PXSDKCompatibilityReport();
    for (unsigned i=0;i<6;i++) {
        NSString *key=[NSString stringWithFormat:@"%s %c%s",rejected[i].name,rejected[i].meta?'+':'-',rejected[i].sel];
        CHECK([report[key][@"status"] isEqual:@"signature-mismatch"]);
        Class cls=objc_lookUpClass(rejected[i].name); if (rejected[i].meta) cls=object_getClass(cls);
        CHECK(method_getImplementation(class_getInstanceMethod(cls,sel_registerName(rejected[i].sel)))==(IMP)Dummy);
    }
    for (unsigned enabled=0;enabled<3;enabled++) {
        phone.runtime=enabled==1?@{@"sdkCompatibility":@YES,@"maskEnvironment":@YES,@"timeSinceLastLaunch":@(-1)}:@{};
#define EXPECT_RETURN(index,type,value) CHECK(((type(*)(id,SEL))objc_msgSend)(receivers[index],sel_registerName(cases[index].sel))==(type)(enabled==1?0:(value)))
        EXPECT_RETURN(0,_Bool,1); EXPECT_RETURN(1,char,-7); EXPECT_RETURN(2,unsigned char,249);
        EXPECT_RETURN(3,short,-1234); EXPECT_RETURN(4,unsigned short,65000);
        EXPECT_RETURN(5,int,INT_MIN+123); EXPECT_RETURN(6,unsigned int,UINT_MAX-17);
        EXPECT_RETURN(7,long,LONG_MIN+12345); EXPECT_RETURN(8,unsigned long,ULONG_MAX-12345);
        EXPECT_RETURN(9,long long,LLONG_MIN+444); EXPECT_RETURN(10,unsigned long long,ULLONG_MAX-555);
#undef EXPECT_RETURN
        CHECK(((float(*)(id,SEL))objc_msgSend)([tracker new],sel_registerName("getTimePassedSinceLastLaunch"))==(enabled==1?-1.0f:3.25f));
    }
    printf("PASS: %lu SDK ABI checks\n",(unsigned long)checks);
} return 0; }
