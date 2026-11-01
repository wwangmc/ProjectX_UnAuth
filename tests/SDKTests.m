#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <stdatomic.h>
#import "PXSDKCompatibility.h"
#import "PXConfiguration.h"

static NSUInteger checks,installs;
#define CHECK(x) do { checks++; if (!(x)) { fprintf(stderr,"SDK FAIL %d: %s\n",__LINE__,#x); abort(); } } while(0)
static PhoneInfo *phone;
static NSMutableDictionary *results,*calls,*arguments;
static BOOL throwOriginal;
static NSString *InvocationKey(id self,SEL cmd) {
    BOOL meta=class_isMetaClass(object_getClass(self));
    return [NSString stringWithFormat:@"%@ %c%s",meta?NSStringFromClass((Class)self):NSStringFromClass([self class]),meta?'+':'-',sel_getName(cmd)];
}
static void Called(id self,SEL cmd,NSArray *args) {
    @synchronized (calls) { NSString *key=InvocationKey(self,cmd); calls[key]=@([calls[key] unsignedIntegerValue]+1); arguments[key]=args ?: @[]; }
}
static id Object(id self,SEL cmd) { Called(self,cmd,nil); return results[InvocationKey(self,cmd)]; }
static char Scalar(id self,SEL cmd) {
    Called(self,cmd,nil);
    if (throwOriginal && !strcmp(sel_getName(cmd),"checkJailbroken")) @throw [NSException exceptionWithName:@"fixture" reason:@"original exception" userInfo:nil];
    return -7;
}
static char SuperScalar(id self,SEL cmd) {
    struct objc_super parent={self,class_getSuperclass(object_getClass(self))};
    return ((char(*)(struct objc_super *,SEL))objc_msgSendSuper)(&parent,cmd)+1;
}
static char ScalarArg(id self,SEL cmd,BOOL arg) { Called(self,cmd,@[@(arg)]); return -7; }
static char ObjectArg(id self,SEL cmd,id arg) { Called(self,cmd,@[arg ?: NSNull.null]); return -7; }
static char Coordinates(id self,SEL cmd,double x,double y) { Called(self,cmd,@[@(x),@(y)]); return -7; }
static void Void(id self,SEL cmd) { Called(self,cmd,nil); }
static void VoidObject(id self,SEL cmd,id arg) { Called(self,cmd,@[arg ?: NSNull.null]); }
static void Write(id self,SEL cmd,id object,NSUInteger index) { Called(self,cmd,@[object ?: NSNull.null,@(index)]); }
static void Skip(id self,SEL cmd,BOOL arg) { Called(self,cmd,@[@(arg)]); }
static id Realm(id self,SEL cmd,id config,id queue,NSError **error) {
    Called(self,cmd,@[config ?: NSNull.null,queue ?: NSNull.null]);
    if (error) *error=[NSError errorWithDomain:@"fixture" code:42 userInfo:nil]; return nil;
}
static id Encrypt(id self,SEL cmd,id data,id key) { Called(self,cmd,@[data ?: NSNull.null,key ?: NSNull.null]); return data; }
static id Ads(id self,SEL cmd,id info,BOOL nested) { Called(self,cmd,@[info ?: NSNull.null,@(nested)]); return results[InvocationKey(self,cmd)]; }
static double Time(id self,SEL cmd) { Called(self,cmd,nil); return 12.5; }
static NSRange Invalid(id self,SEL cmd) { return NSMakeRange(4,8); }
static Class ClassNamed(const char *name) {
    Class cls=objc_lookUpClass(name);
    if (!cls) {
        Class parent=!strcmp(name,"OneSignalJailbreakDetection")?objc_lookUpClass("GADevice"):NSObject.class;
        cls=objc_allocateClassPair(parent,name,0); CHECK(cls!=Nil); objc_registerClassPair(cls);
    }
    return cls;
}
static NSString *TKey(const PXSDKTarget *t) { return [NSString stringWithFormat:@"%s %c%s",t->className,t->meta?'+':'-',t->selector]; }
static void AddTarget(const PXSDKTarget *t,BOOL bad) {
    Class cls=ClassNamed(t->className); if (t->meta) cls=object_getClass(cls);
    IMP imp=(IMP)Object; const char *encoding="@@:";
    switch (t->action) {
        case PXSDKEnvironmentZero: case PXSDKEnvironmentOne: case PXSDKProxyZero: case PXSDKWiFi:
            imp=(IMP)Scalar; encoding="c@:";
            if (strchr(t->selector,':')) { imp=(IMP)ScalarArg; encoding="c@:c"; }
            break;
        case PXSDKLocationObject: imp=(IMP)ObjectArg; encoding="c@:@"; break;
        case PXSDKLocationCoordinates: imp=(IMP)Coordinates; encoding="c@:dd"; break;
        case PXSDKCollector: case PXSDKInitialization: case PXSDKDisableDebugger: case PXSDKPassVoid:
            imp=strchr(t->selector,':')?(IMP)VoidObject:(IMP)Void; encoding=strchr(t->selector,':')?"v@:@":"v@:"; break;
        case PXSDKRealmCreate: imp=(IMP)Realm; encoding="@@:@@^@"; break;
        case PXSDKRealmWrite: imp=(IMP)Write; encoding="v@:@Q"; break;
        case PXSDKCrypto: imp=(IMP)Encrypt; encoding="@@:@@"; break;
        case PXSDKAdParameters: imp=(IMP)Ads; encoding="@@:@c"; break;
        case PXSDKSkipAdvanced: imp=(IMP)Skip; encoding="v@:c"; break;
        case PXSDKLaunchTime: imp=(IMP)Time; encoding="d@:"; break;
        default: break;
    }
    // The reference orientation and opaque Xi05UCs methods are OBJECT returns.
    if (!strcmp(t->selector,"Xi05UCs")) { imp=(IMP)Object; encoding="@@:"; }
    if (!strcmp(t->className,"OneSignalJailbreakDetection")) imp=(IMP)SuperScalar;
    if (bad && !strcmp(t->className,"SecurityWarnings") && !strcmp(t->selector,"isHooked")) { imp=(IMP)Invalid; encoding="{_NSRange=QQ}@:"; }
    CHECK(class_addMethod(cls,sel_registerName(t->selector),imp,encoding));
    results[TKey(t)]=@{@"idfa":@"original-id",@"idfv":@"original-vendor",@"jailbroken":@YES,@"cydia":@YES,@"jdb":@"1",@"deb":@"1",@"py":@{@"HTTPProxy":@"fixture"}};
}
static id Receiver(NSString *cls,BOOL meta) { Class c=NSClassFromString(cls); return meta?(id)c:[c new]; }
static id Get(NSString *cls,NSString *sel,BOOL meta) { return ((id(*)(id,SEL))objc_msgSend)(Receiver(cls,meta),NSSelectorFromString(sel)); }
static char Int(NSString *cls,NSString *sel,BOOL meta) { return ((char(*)(id,SEL))objc_msgSend)(Receiver(cls,meta),NSSelectorFromString(sel)); }
static void Config(NSDictionary *d) { phone.runtime=d; }
static void SetFlag(NSString *key,BOOL value) { NSMutableDictionary *d=[phone.runtime mutableCopy]; d[key]=@(value); Config(d); }
int main(int argc,const char **argv) { @autoreleasepool {
    BOOL bad=argc>1 && !strcmp(argv[1],"--bad-signatures");
    results=[NSMutableDictionary dictionary]; calls=[NSMutableDictionary dictionary]; arguments=[NSMutableDictionary dictionary];
    phone=[PhoneInfo new]; phone.idfa=@"CD0278A1-7DF9-4CE9-B2D3-459C5B919FE9"; phone.idfv=@"B283221C-5B03-4781-9F12-DA580DA0B331";
    phone.networkInfo=[NetworkInfo new]; phone.networkInfo.connectionType=1;
    NSUInteger count; const PXSDKTarget *targets=PXSDKTargetList(&count); CHECK(count==105);
    for (NSUInteger i=0;i<count;i++) if (strcmp(targets[i].className,"OneSignalJailbreakDetection")) AddTarget(&targets[i],bad);
    PXSDKConfigure(^PhoneInfo *{ return phone; },^IMP(Class cls,SEL sel,IMP hook,const char *type,unsigned args) {
        Method method=class_getInstanceMethod(cls,sel); IMP old=method_getImplementation(method); installs++;
        // Match Substrate's per-class behavior without mutating inherited methods.
        if (!class_addMethod(cls,sel,hook,method_getTypeEncoding(method))) method_setImplementation(method,hook);
        return old;
    });
    PXSDKInstallTargets(); NSDictionary *report=PXSDKCompatibilityReport(); CHECK(report.count==count);
    CHECK([report[@"OneSignalJailbreakDetection +isJailbroken"][@"status"] isEqual:@"missing"]);
    if (bad) {
        CHECK([report[@"SecurityWarnings +isHooked"][@"status"] isEqual:@"signature-mismatch"]);
        NSRange range=((NSRange(*)(id,SEL))objc_msgSend)(NSClassFromString(@"SecurityWarnings"),sel_registerName("isHooked"));
        CHECK(NSEqualRanges(range,NSMakeRange(4,8))); printf("PASS: %lu SDK signature checks\n",(unsigned long)checks); return 0;
    }
    for (NSUInteger i=0;i<count;i++) if (!strcmp(targets[i].className,"OneSignalJailbreakDetection")) AddTarget(&targets[i],NO);
    PXSDKInstallTargets(); report=PXSDKCompatibilityReport();
    for (NSUInteger i=0;i<count;i++) CHECK([report[TKey(&targets[i])][@"status"] isEqual:@"installed"]);
    CHECK(installs==count); PXSDKInstallTargets(); CHECK(installs==count);
    CHECK([report[@"PDXC +load"][@"loadTimingUnverified"] boolValue]);
    Config(@{}); CHECK(Int(@"GADevice",@"isJailbroken",YES)==-7);
    CHECK(Int(@"OneSignalJailbreakDetection",@"isJailbroken",YES)==-6);
    throwOriginal=YES; BOOL threw=NO;
    @try { Int(@"GADevice",@"checkJailbroken",NO); } @catch (NSException *e) { threw=YES; }
    CHECK(threw); throwOriginal=NO; CHECK(Int(@"GADevice",@"checkJailbroken",NO)==-7);
    CHECK([Get(@"SensesDevice",@"getDeviceIdfv",NO) isEqual:results[@"SensesDevice -getDeviceIdfv"]]);
    Config(@{@"sdkCompatibility":@YES,@"maskEnvironment":@YES,@"maskProxy":@YES});
    CHECK(Int(@"GADevice",@"isJailbroken",YES)==0); CHECK(Int(@"OKEnvironment",@"isOKCoin",NO)==1);
    CHECK(Int(@"SpectrumReachability",@"isConnectedViaVPN",NO)==0); CHECK(Int(@"SpectrumReachability",@"isReachableViaWiFiNoVPN",NO)==1);
    CHECK([Get(@"AIMetaDataCollector",@"getDeviceJailbrokenState",NO) isEqual:@NO]);
    CHECK(Get(@"PuGo29z",@"Xi05UCs",YES)==nil);
    CHECK([Get(@"AFSDKDevice",@"identifierForVendor",YES) isEqual:phone.idfv]);
    CHECK([Get(@"SensesDevice",@"getDeviceIdfv",NO) isEqual:phone.idfv]);
    CHECK(calls[@"AFSDKDevice +identifierForVendor"]==nil);
    CHECK(![Get(@"MPDevice",@"jailbrokenInfo",YES)[@"cydia"] boolValue]);
    NSDictionary *mobile=Get(@"GT3DataBase",@"mobileInfo",NO);
    CHECK([mobile[@"jdb"] isEqual:@"0"] && [mobile[@"deb"] isEqual:@"0"] && [mobile[@"py"] count]==0);
    CHECK([results[@"GT3DataBase -mobileInfo"][@"jdb"] isEqual:@"1"]);
    CHECK(Get(@"turing_HIreYaasq8l5EBASEOS",@"injectingImageNames",YES)==nil);
    results[@"AFSDKiAdClient -appleAdsAttributionToken"]=@"real-token";
    CHECK([Get(@"AFSDKiAdClient",@"appleAdsAttributionToken",NO) isEqual:@"real-token"]);
    SetFlag(@"sdkSuppressAttribution",YES); CHECK(Get(@"AFSDKiAdClient",@"appleAdsAttributionToken",NO)==nil);
    NSMutableDictionary *runtime=[phone.runtime mutableCopy]; runtime[@"interfaceOrientation"]=@4; runtime[@"timeSinceLastLaunch"]=@(-1); Config(runtime);
    CHECK([Get(@"AppsFlyerUtils",@"deviceOrientation",YES) isEqual:@"lr"]);
    runtime[@"interfaceOrientation"]=@1; Config(runtime); CHECK([Get(@"AppsFlyerUtils",@"deviceOrientation",YES) isEqual:@"p"]);
    CHECK(((double(*)(id,SEL))objc_msgSend)(Receiver(@"AppsFlyerTracker",NO),sel_registerName("getTimePassedSinceLastLaunch"))==-1);
    CHECK(PXValidateRuntime(@{@"timeSinceLastLaunch":@(-1),@"sdkBlockRealmWrites":@YES},NULL)!=nil);
    CHECK(PXValidateRuntime(@{@"sdkSuppressInitialization":@2},NULL)==nil);
    CHECK(PXValidateRuntime(@{@"sdkSuppressInitialization":@0.5},NULL)==nil);
    CHECK(PXValidateRuntime(@{@"interfaceOrientation":@1.5},NULL)==nil);
    id tracker=Receiver(@"AppsFlyerTracker",NO);
    ((void(*)(id,SEL,BOOL))objc_msgSend)(tracker,sel_registerName("setSkipAdvancedJailbreakValidation:"),NO);
    CHECK([arguments[@"AppsFlyerTracker -setSkipAdvancedJailbreakValidation:"][0] boolValue]);
    id collector=Receiver(@"HMDLaunchTimingUserTrace",YES); SEL span=sel_registerName("startSpanWithTaskName:");
    ((void(*)(id,SEL,id))objc_msgSend)(collector,span,@"task"); CHECK([calls[@"HMDLaunchTimingUserTrace +startSpanWithTaskName:"] intValue]==1);
    SetFlag(@"sdkSuppressCollectors",YES); ((void(*)(id,SEL,id))objc_msgSend)(collector,span,@"task"); CHECK([calls[@"HMDLaunchTimingUserTrace +startSpanWithTaskName:"] intValue]==1);
    id array=Receiver(@"RLMArray",NO); SEL write=sel_registerName("insertObject:atIndex:");
    ((void(*)(id,SEL,id,NSUInteger))objc_msgSend)(array,write,@"object",7);
    CHECK([arguments[@"RLMArray -insertObject:atIndex:"][1] unsignedIntegerValue]==7);
    SetFlag(@"sdkBlockRealmWrites",YES); ((void(*)(id,SEL,id,NSUInteger))objc_msgSend)(array,write,@"object",9); CHECK([calls[@"RLMArray -insertObject:atIndex:"] intValue]==1);
    NSError *error=nil; id realm=((id(*)(id,SEL,id,id,NSError **))objc_msgSend)(Receiver(@"RLMRealm",YES),sel_registerName("realmWithConfiguration:queue:error:"),@"configuration",@"queue",&error);
    CHECK(realm==nil && error.code==42); CHECK([calls[@"RLMRealm +realmWithConfiguration:queue:error:"] intValue]==1);
    NSData *data=[@"plaintext" dataUsingEncoding:NSUTF8StringEncoding]; NSDictionary *key=@{@"idfa":@"key-value"};
    id encrypted=((id(*)(id,SEL,id,id))objc_msgSend)(Receiver(@"AppsFlyerAES128Crypto",YES),sel_registerName("encrypt:withObject:"),data,key);
    CHECK(encrypted==data); CHECK(arguments[@"AppsFlyerAES128Crypto +encrypt:withObject:"][1]==key); CHECK([calls[@"AppsFlyerAES128Crypto +encrypt:withObject:"] intValue]==1);
    id ad=((id(*)(id,SEL,id,BOOL))objc_msgSend)(Receiver(@"ALDataCollector",NO),sel_registerName("requestParametersWithAdInfo:nested:"),@"ad",YES);
    CHECK([ad[@"idfa"] isEqual:phone.idfa]); CHECK([arguments[@"ALDataCollector -requestParametersWithAdInfo:nested:"][1] boolValue]);
    runtime=[phone.runtime mutableCopy]; runtime[@"location"]=@{@"latitude":@0,@"longitude":@0}; Config(runtime);
    CHECK(((char(*)(id,SEL,id))objc_msgSend)(Receiver(@"ABKLocationUtilities",YES),sel_registerName("isValidLocationAndAccurateEnough:"),@"location")==1);
    CHECK(((char(*)(id,SEL,double,double))objc_msgSend)(Receiver(@"ABKLocationUtilities",YES),sel_registerName("locationIsValidWithLatitude:longitude:"),1.25,2.5)==1);
    // Dedicated fingerprint payloads retain input representation and unrelated fields.
    results[@"FFMClassZeroOne -czoSymbolZeroSix"]=@{@"NETS":@"{\"en0\":{\"mac\":\"11:22:33:44:55:12\",\"other\":7},\"utun4\":{\"mac\":\"9\"}}",@"RDATES":@"[1700000000,1600000000,0]",@"keep":@"value"};
    SetFlag(@"sdkRewriteMetadata",YES);
    NSDictionary *ffm=Get(@"FFMClassZeroOne",@"czoSymbolZeroSix",NO);
    NSDictionary *nets=[NSJSONSerialization JSONObjectWithData:[ffm[@"NETS"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    CHECK(nets[@"utun4"]==nil && [nets[@"en0"][@"other"] intValue]==7);
    CHECK(![nets[@"en0"][@"mac"] isEqual:@"11:22:33:44:55:12"]);
    CHECK([ffm isEqual:Get(@"FFMClassZeroOne",@"czoSymbolZeroSix",NO)]);
    NSArray *dates=[NSJSONSerialization JSONObjectWithData:[ffm[@"RDATES"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    CHECK([dates[0] doubleValue]==0 && [dates[1] doubleValue]<1600000000 && [dates[2] doubleValue]<1700000000);
    CHECK([dates[1] doubleValue]>=1600000000-5184000);
    results[@"FFMClassZeroOne -czoSymbolZeroSix"]=@{@"NETS":@"not JSON",@"RDATES":@"[\"bad\"]"};
    CHECK([Get(@"FFMClassZeroOne",@"czoSymbolZeroSix",NO) isEqual:results[@"FFMClassZeroOne -czoSymbolZeroSix"]]);
    unichar loneSurrogate=0xd800;
    results[@"FFMClassZeroOne -czoSymbolZeroSix"]=@{@"NETS":[NSString stringWithCharacters:&loneSurrogate length:1]};
    CHECK([Get(@"FFMClassZeroOne",@"czoSymbolZeroSix",NO) isEqual:results[@"FFMClassZeroOne -czoSymbolZeroSix"]]);
    NSMutableDictionary *cycle=[NSMutableDictionary dictionary];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-circular-container"
    cycle[@"self"]=cycle;
#pragma clang diagnostic pop
    CHECK(PXSDKTransformValue(cycle,phone)!=nil); [cycle removeAllObjects];
    NSDictionary *nested=@{@"array":@[@{@"idfv":@"old"}],@"idfa":@42};
    NSDictionary *changed=PXSDKTransformValue(nested,phone); CHECK([changed[@"array"][0][@"idfv"] isEqual:phone.idfv] && [changed[@"idfa"] isEqual:@42]);
    SetFlag(@"sdkSuppressInitialization",YES);
    ((void(*)(id,SEL,id))objc_msgSend)(Receiver(@"PluginShieldfraudPlugin",YES),sel_registerName("registerWithRegistrar:"),@"registrar");
    CHECK(calls[@"PluginShieldfraudPlugin +registerWithRegistrar:"]==nil);
    // A manually invoked load exercises the adapter, not historical auto-load timing.
    ((void(*)(id,SEL))objc_msgSend)(Receiver(@"PDXC",YES),sel_registerName("load")); CHECK(calls[@"PDXC +load"]==nil);
    Config(@{}); ((void(*)(id,SEL))objc_msgSend)(Receiver(@"PDXC",YES),sel_registerName("load")); CHECK([calls[@"PDXC +load"] intValue]==1);
    ((void(*)(id,SEL,id,NSUInteger))objc_msgSend)(array,write,@"object",11); CHECK([calls[@"RLMArray -insertObject:atIndex:"] intValue]==2);
    CHECK(((double(*)(id,SEL))objc_msgSend)(tracker,sel_registerName("getTimePassedSinceLastLaunch"))==12.5);
    CHECK(((char(*)(id,SEL,double,double))objc_msgSend)(Receiver(@"ABKLocationUtilities",YES),sel_registerName("locationIsValidWithLatitude:longitude:"),1.25,2.5)==-7);
    CHECK([arguments[@"ABKLocationUtilities +locationIsValidWithLatitude:longitude:"][1] doubleValue]==2.5);
    atomic_int failures; atomic_init(&failures,0); atomic_int *failed=&failures;
    dispatch_apply(24,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^(size_t i) {
        @autoreleasepool {
            if (i%2) PXSDKInstallTargets();
            else if (Int(@"OneSignalJailbreakDetection",@"isJailbroken",YES)!=-6) atomic_fetch_add(failed,1);
        }
    });
    CHECK(atomic_load(&failures)==0); CHECK(installs==count);
    Config(@{@"sdkCompatibility":@YES,@"maskProxy":@YES});
    CHECK(Int(@"GADevice",@"isJailbroken",YES)==-7);
    CHECK(Int(@"SpectrumReachability",@"isConnectedViaVPN",NO)==0);
    Config(@{@"openUDID":@"configured-openudid"});
    CHECK([Get(@"OpenUDID",@"value",YES) isEqual:@"configured-openudid"]);
    phone=nil; CHECK(Int(@"GADevice",@"isJailbroken",YES)==-7);
    printf("PASS: %lu SDK checks (%lu targets)\n",(unsigned long)checks,(unsigned long)count);
} return 0; }
