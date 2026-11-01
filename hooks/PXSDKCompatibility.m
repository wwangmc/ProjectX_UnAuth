#import "PXSDKCompatibility.h"
#import "PXSDKTargets.h"
#import "PXSDKEarlyLoad.h"
#import <math.h>
#import <stdint.h>

static PhoneInfo *(^PhoneProvider)(void);
static IMP (^MethodInstaller)(Class, SEL, IMP, const char *, unsigned);
@interface PXSDKMethod : NSObject
@property(nonatomic,assign) Class owner;
@property(nonatomic,assign) IMP original;
@property(nonatomic,assign) PXSDKAction action;
@end
@implementation PXSDKMethod
@end
static NSMutableDictionary<NSString *,PXSDKMethod *> *Methods;
static NSMutableDictionary *Statuses;
static NSRecursiveLock *RegistryLock(void) {
    static NSRecursiveLock *lock; static dispatch_once_t once;
    dispatch_once(&once,^{ lock=[NSRecursiveLock new]; }); return lock;
}
static NSString *Key(Class cls,SEL cmd) { return [NSString stringWithFormat:@"%p:%s",cls,sel_getName(cmd)]; }
static NSString *TargetKey(const PXSDKTarget *t) { return [NSString stringWithFormat:@"%s %c%s",t->className,t->meta?'+':'-',t->selector]; }

// A hooked override calling super must resolve the superclass's original IMP.
typedef struct PXSDKFrame {
    __unsafe_unretained id receiver;
    SEL selector;
    Class owner;
    struct PXSDKFrame *previous;
} PXSDKFrame;
static _Thread_local PXSDKFrame *OriginalFrame;
static PXSDKMethod *Record(id self,SEL cmd) {
    Class start=object_getClass(self);
    if (OriginalFrame && OriginalFrame->receiver==self && OriginalFrame->selector==cmd)
        start=class_getSuperclass(OriginalFrame->owner);
    [RegistryLock() lock]; @try {
        for (Class cls=start;cls;cls=class_getSuperclass(cls)) {
            PXSDKMethod *r=Methods[Key(cls,cmd)]; if (r) return r;
        }
    } @finally { [RegistryLock() unlock]; }
    return nil;
}
#define ORIGINAL(expression) do { \
    PXSDKFrame frame={self,cmd,r.owner,OriginalFrame}; OriginalFrame=&frame; \
    @try { expression; } @finally { OriginalFrame=frame.previous; } \
} while(0)
static PhoneInfo *Phone(void) { return PhoneProvider?PhoneProvider():nil; }
static BOOL Flag(PhoneInfo *p,NSString *key) { return [p.runtime[key] boolValue]; }
static BOOL SDK(PhoneInfo *p) { return p && Flag(p,@"sdkCompatibility"); }
BOOL PXSDKShouldSuppressInitialization(void) { PhoneInfo *p=Phone(); return SDK(p) && Flag(p,@"sdkSuppressInitialization"); }
static BOOL Environment(PhoneInfo *p) { return SDK(p) && Flag(p,@"maskEnvironment"); }
static BOOL Proxy(PhoneInfo *p) { return SDK(p) && Flag(p,@"maskProxy"); }
static BOOL Enabled(PXSDKAction action,PhoneInfo *p) {
    switch (action) {
        case PXSDKEnvironmentZero: case PXSDKEnvironmentOne: case PXSDKNumberFalse:
        case PXSDKInjectedImages: case PXSDKDisableDebugger: case PXSDKSkipAdvanced: return Environment(p);
        case PXSDKProxyZero: case PXSDKWiFi: return Proxy(p);
        case PXSDKCollector: return SDK(p) && Flag(p,@"sdkSuppressCollectors");
        case PXSDKInitialization: return SDK(p) && Flag(p,@"sdkSuppressInitialization");
        case PXSDKRealmWrite: return SDK(p) && Flag(p,@"sdkBlockRealmWrites");
        case PXSDKAttributionToken: return SDK(p) && Flag(p,@"sdkSuppressAttribution");
        case PXSDKOrientation: return SDK(p) && p.runtime[@"interfaceOrientation"]!=nil;
        case PXSDKLaunchTime: return SDK(p) && p.runtime[@"timeSinceLastLaunch"]!=nil;
        case PXSDKLocationObject: case PXSDKLocationCoordinates: return SDK(p) && p.runtime[@"location"]!=nil;
        default: return NO;
    }
}
static id Transform(id value,PhoneInfo *p,NSUInteger depth,NSHashTable *seen,NSUInteger *budget) {
    if (depth>16 || !*budget || (![value isKindOfClass:NSDictionary.class] && ![value isKindOfClass:NSArray.class])) return value;
    if ([seen containsObject:value]) return value;
    (*budget)--; [seen addObject:value];
    id result;
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *array=[NSMutableArray arrayWithCapacity:[value count]];
        for (id item in value) [array addObject:Transform(item,p,depth+1,seen,budget)];
        result=array;
    } else {
        NSMutableDictionary *dict=[value mutableCopy];
        for (id key in value) {
            id old=value[key];
            if (![key isKindOfClass:NSString.class]) continue;
            NSString *lower=[key lowercaseString];
            if (Environment(p) && ([@[@"jailbroken",@"isjailbroken",@"jailbreak",@"is_jailbroken",@"isrooted",@"is_debugged"] containsObject:lower]))
                dict[key]=[old isKindOfClass:NSString.class]?@"0":@NO;
            else if (Proxy(p) && [@[@"vpn",@"isvpn",@"is_vpn",@"proxy",@"isproxy"] containsObject:lower])
                dict[key]=[old isKindOfClass:NSString.class]?@"0":@NO;
            else if ([@[@"idfa",@"advertisingid",@"advertising_id"] containsObject:lower] && p.idfa.length && ([old isKindOfClass:NSString.class] || [old isKindOfClass:NSUUID.class]))
                dict[key]=[old isKindOfClass:NSUUID.class]?[[NSUUID alloc] initWithUUIDString:p.idfa] ?: old:p.idfa;
            else if ([@[@"idfv",@"vendorid",@"vendor_id"] containsObject:lower] && p.idfv.length && ([old isKindOfClass:NSString.class] || [old isKindOfClass:NSUUID.class]))
                dict[key]=[old isKindOfClass:NSUUID.class]?[[NSUUID alloc] initWithUUIDString:p.idfv] ?: old:p.idfv;
            else dict[key]=Transform(old,p,depth+1,seen,budget);
        }
        result=dict;
    }
    [seen removeObject:value]; return result;
}
id PXSDKTransformValue(id value,PhoneInfo *phone) {
    if (!SDK(phone)) return value;
    NSUInteger budget=4096;
    NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    return Transform(value,phone,0,seen,&budget);
}
static uint64_t Stable(NSString *seed,NSString *field) {
    NSData *bytes=[[seed stringByAppendingFormat:@"/%@",field] dataUsingEncoding:NSUTF8StringEncoding];
    uint64_t h=14695981039346656037ULL; const uint8_t *p=bytes.bytes;
    for (NSUInteger i=0;i<bytes.length;i++) { h^=p[i]; h*=1099511628211ULL; }
    return h;
}
static id Decode(id value) {
    if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) return value;
    if (![value isKindOfClass:NSString.class] || [value length]>(1<<20)) return nil;
    NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding];
    return data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
}
static id EncodeLike(id object,id original) {
    if (![original isKindOfClass:NSString.class]) return object;
    NSData *data=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:NULL];
    return data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:original;
}
static BOOL VPNInterface(NSString *name) {
    for (NSString *prefix in @[@"utun",@"tun",@"tap",@"ppp",@"ipsec"]) if ([name hasPrefix:prefix]) return YES;
    return NO;
}
static id Fingerprint(id value,PhoneInfo *p) {
    if (![value isKindOfClass:NSDictionary.class]) return value;
    NSMutableDictionary *result=[PXSDKTransformValue(value,p) mutableCopy];
    NSString *seed=p.idfv.length?p.idfv:p.idfa;
    // GPT 0x11d398: NETS is a JSON string whose interface entries contain mac.
    // Preserve representation; changes stay stable for the active profile.
    id nets=Decode(value[@"NETS"]);
    if ([nets isKindOfClass:NSDictionary.class] && (Proxy(p) || (Flag(p,@"sdkRewriteMetadata") && seed.length))) {
        NSMutableDictionary *changed=[nets mutableCopy];
        for (id name in nets) {
            if (![name isKindOfClass:NSString.class]) continue;
            if (Proxy(p) && VPNInterface(name)) { [changed removeObjectForKey:name]; continue; }
            id entry=nets[name];
            if (!Flag(p,@"sdkRewriteMetadata") || !seed.length || ![entry isKindOfClass:NSDictionary.class]) continue;
            NSString *mac=entry[@"mac"]; if (![mac isKindOfClass:NSString.class]) continue;
            NSRange separator=[mac rangeOfString:@":" options:NSBackwardsSearch];
            if (separator.location==NSNotFound || separator.location+1>=mac.length) continue;
            NSString *last=[mac substringFromIndex:separator.location+1];
            if ([last rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound || last.longLongValue<=0) continue;
            NSMutableDictionary *item=[entry mutableCopy];
            item[@"mac"]=[[mac substringToIndex:separator.location+1] stringByAppendingFormat:@"%llu",13ULL+Stable(seed,name)%100];
            changed[name]=item;
        }
        result[@"NETS"]=EncodeLike(changed,value[@"NETS"]);
    }
    id dates=Decode(value[@"RDATES"]);
    if (Flag(p,@"sdkRewriteMetadata") && seed.length && [dates isKindOfClass:NSArray.class]) {
        NSMutableArray *changed=[NSMutableArray array]; BOOL valid=YES; NSUInteger index=0;
        for (id number in dates) {
            if (![number isKindOfClass:NSNumber.class] || !isfinite([number doubleValue])) { valid=NO; break; }
            double d=[number doubleValue];
            if (d>0) d=fmax(0,d-(double)(Stable(seed,[NSString stringWithFormat:@"RDATES/%lu/%@",(unsigned long)index,number])%5184000));
            [changed addObject:@(d)]; index++;
        }
        if (valid) result[@"RDATES"]=EncodeLike([changed sortedArrayUsingSelector:@selector(compare:)],value[@"RDATES"]);
    }
    return result;
}
static long long ScalarValue(PXSDKMethod *r,PhoneInfo *p) {
    switch (r.action) {
        case PXSDKEnvironmentOne: case PXSDKLocationObject: case PXSDKLocationCoordinates: return 1;
        case PXSDKWiFi: return p.networkInfo.connectionType==1;
        case PXSDKOrientation: return [p.runtime[@"interfaceOrientation"] longLongValue];
        default: return 0;
    }
}
// Match return width/sign. The scalar argument in this inventory is a BOOL.
#define SCALARS(suffix,type) \
static type Scalar0##suffix(id self,SEL cmd) { \
    PXSDKMethod *r=Record(self,cmd); PhoneInfo *p=Phone(); \
    if (Enabled(r.action,p)) return (type)ScalarValue(r,p); \
    type result=0; if (r.original) ORIGINAL(result=((type(*)(id,SEL))r.original)(self,cmd)); return result; \
} \
static type Scalar1##suffix(id self,SEL cmd,BOOL arg) { \
    PXSDKMethod *r=Record(self,cmd); PhoneInfo *p=Phone(); \
    if (Enabled(r.action,p)) return (type)ScalarValue(r,p); \
    type result=0; if (r.original) ORIGINAL(result=((type(*)(id,SEL,BOOL))r.original)(self,cmd,arg)); return result; \
} \
static type Object1##suffix(id self,SEL cmd,id arg) { \
    PXSDKMethod *r=Record(self,cmd); PhoneInfo *p=Phone(); \
    if (Enabled(r.action,p)) return (type)ScalarValue(r,p); \
    type result=0; if (r.original) ORIGINAL(result=((type(*)(id,SEL,id))r.original)(self,cmd,arg)); return result; \
} \
static type Coordinates##suffix(id self,SEL cmd,double lat,double lng) { \
    PXSDKMethod *r=Record(self,cmd); PhoneInfo *p=Phone(); \
    if (Enabled(r.action,p)) return (type)ScalarValue(r,p); \
    type result=0; if (r.original) ORIGINAL(result=((type(*)(id,SEL,double,double))r.original)(self,cmd,lat,lng)); return result; \
}
SCALARS(Bool,_Bool) SCALARS(Char,char) SCALARS(UChar,unsigned char)
SCALARS(Short,short) SCALARS(UShort,unsigned short) SCALARS(Int,int) SCALARS(UInt,unsigned int)
SCALARS(Long,long) SCALARS(ULong,unsigned long) SCALARS(LongLong,long long) SCALARS(ULongLong,unsigned long long)
#undef SCALARS
static id Object0(id self,SEL cmd) {
    PXSDKMethod *r=Record(self,cmd); PhoneInfo *p=Phone();
    if (r.action==PXSDKOpenUDID && [p.runtime[@"openUDID"] length]) return p.runtime[@"openUDID"];
    if (SDK(p) && r.action==PXSDKIDFV && p.idfv.length) return p.idfv;
    if (Enabled(r.action,p)) {
        switch (r.action) {
            case PXSDKNumberFalse: return @NO;
            case PXSDKEnvironmentZero: case PXSDKProxyZero: case PXSDKInjectedImages: case PXSDKAttributionToken: return nil;
            case PXSDKOrientation: return [p.runtime[@"interfaceOrientation"] integerValue]>=3?@"lr":@"p";
            default: break;
        }
    }
    id value=nil; if (r.original) ORIGINAL(value=((id(*)(id,SEL))r.original)(self,cmd));
    if (!SDK(p)) return value;
    if (r.action==PXSDKFingerprint) return Fingerprint(value,p);
    if (r.action==PXSDKPassObject || r.action==PXSDKAttributionToken || r.action==PXSDKOpenUDID) return value;
    id result=PXSDKTransformValue(value,p);
    if ([result isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *dict=[result mutableCopy];
        if (r.action==PXSDKMobileInfo) {
            if (Environment(p)) { dict[@"jdb"]=@"0"; dict[@"deb"]=@"0"; }
            if (Proxy(p)) dict[@"py"]=@{};
        }
        if (r.action==PXSDKJailbreakInfo && Environment(p)) dict[@"cydia"]=@NO;
        return dict;
    }
    return result;
}
static void Void0(id self,SEL cmd) {
    PXSDKMethod *r=Record(self,cmd); if (Enabled(r.action,Phone())) return;
    if (r.original) ORIGINAL(((void(*)(id,SEL))r.original)(self,cmd));
}
static void VoidObject(id self,SEL cmd,id arg) {
    PXSDKMethod *r=Record(self,cmd); if (Enabled(r.action,Phone())) return;
    if (r.original) ORIGINAL(((void(*)(id,SEL,id))r.original)(self,cmd,arg));
}
static void RealmWrite(id self,SEL cmd,id object,NSUInteger index) {
    PXSDKMethod *r=Record(self,cmd); if (Enabled(r.action,Phone())) return;
    if (r.original) ORIGINAL(((void(*)(id,SEL,id,NSUInteger))r.original)(self,cmd,object,index));
}
static id RealmCreate(id self,SEL cmd,id config,id queue,NSError **error) {
    PXSDKMethod *r=Record(self,cmd); id value=nil;
    if (r.original) ORIGINAL(value=((id(*)(id,SEL,id,id,NSError **))r.original)(self,cmd,config,queue,error));
    return value;
}
static id Crypto(id self,SEL cmd,id data,id key) {
    // GPT logs here. Preserve both arguments and call once, without logging secrets.
    PXSDKMethod *r=Record(self,cmd); id value=nil;
    if (r.original) ORIGINAL(value=((id(*)(id,SEL,id,id))r.original)(self,cmd,data,key));
    return value;
}
static id AdParameters(id self,SEL cmd,id adInfo,BOOL nested) {
    PXSDKMethod *r=Record(self,cmd); id value=nil;
    if (r.original) ORIGINAL(value=((id(*)(id,SEL,id,BOOL))r.original)(self,cmd,adInfo,nested));
    return PXSDKTransformValue(value,Phone());
}
static void SkipAdvanced(id self,SEL cmd,BOOL skip) {
    PXSDKMethod *r=Record(self,cmd);
    if (r.original) ORIGINAL(((void(*)(id,SEL,BOOL))r.original)(self,cmd,Enabled(r.action,Phone())?YES:skip));
}
static double LaunchDouble(id self,SEL cmd) {
    PXSDKMethod *r=Record(self,cmd); PhoneInfo *p=Phone();
    if (Enabled(r.action,p)) return [p.runtime[@"timeSinceLastLaunch"] doubleValue];
    double v=0; if (r.original) ORIGINAL(v=((double(*)(id,SEL))r.original)(self,cmd)); return v;
}
static float LaunchFloat(id self,SEL cmd) {
    PXSDKMethod *r=Record(self,cmd); PhoneInfo *p=Phone();
    if (Enabled(r.action,p)) return [p.runtime[@"timeSinceLastLaunch"] floatValue];
    float v=0; if (r.original) ORIGINAL(v=((float(*)(id,SEL))r.original)(self,cmd)); return v;
}
static const char *Unqualified(const char *type) {
    while (*type && strchr("rnNoORV",*type)) type++; return type;
}
static BOOL ObjectType(const char *type) {
    const char *t=Unqualified(type); return *t=='@' && (t[1]=='\0' || t[1]=='"');
}
static BOOL Argument(Method method,unsigned index,const char *expected) {
    char type[512]={0}; method_getArgumentType(method,index,type,sizeof(type)); const char *t=Unqualified(type);
    if (!strcmp(expected,"@")) return ObjectType(t);
    if (!strcmp(expected,"BOOL")) return !strcmp(t,"B") || !strcmp(t,"c");
    return !strcmp(t,expected);
}
static IMP ScalarIMP(char encoding,unsigned shape) {
#define PICK(code,suffix) case code: return shape==0?(IMP)Scalar0##suffix:shape==1?(IMP)Scalar1##suffix:shape==2?(IMP)Object1##suffix:(IMP)Coordinates##suffix
    switch (encoding) {
        PICK('B',Bool); PICK('c',Char); PICK('C',UChar); PICK('s',Short); PICK('S',UShort);
        PICK('i',Int); PICK('I',UInt); PICK('l',Long); PICK('L',ULong); PICK('q',LongLong); PICK('Q',ULongLong);
        default: return NULL;
    }
#undef PICK
}
static IMP Replacement(PXSDKAction action,Method method) {
    char encoded[512]={0}; method_getReturnType(method,encoded,sizeof(encoded));
    const char *type=Unqualified(encoded); unsigned count=method_getNumberOfArguments(method);
    BOOL scalar=*type && !type[1] && strchr("BcCsSiIlLqQ",*type);
    switch (action) {
        case PXSDKEnvironmentZero: case PXSDKEnvironmentOne: case PXSDKProxyZero:
        case PXSDKNumberFalse: case PXSDKWiFi: case PXSDKOrientation:
            if (scalar && count==2) return ScalarIMP(*type,0);
            if (scalar && count==3 && Argument(method,2,"BOOL") && action==PXSDKEnvironmentZero) return ScalarIMP(*type,1);
            if (ObjectType(type) && count==2 && action!=PXSDKEnvironmentOne && action!=PXSDKWiFi) return (IMP)Object0;
            break;
        case PXSDKLocationObject:
            if (scalar && count==3 && Argument(method,2,"@")) return ScalarIMP(*type,2); break;
        case PXSDKLocationCoordinates:
            if (scalar && count==4 && Argument(method,2,"d") && Argument(method,3,"d")) return ScalarIMP(*type,3); break;
        case PXSDKLaunchTime:
            if (count==2 && !strcmp(type,"d")) return (IMP)LaunchDouble;
            if (count==2 && !strcmp(type,"f")) return (IMP)LaunchFloat; break;
        case PXSDKSkipAdvanced:
            if (!strcmp(type,"v") && count==3 && Argument(method,2,"BOOL")) return (IMP)SkipAdvanced; break;
        case PXSDKCollector: case PXSDKInitialization: case PXSDKDisableDebugger: case PXSDKPassVoid:
            if (!strcmp(type,"v") && count==2) return (IMP)Void0;
            if (!strcmp(type,"v") && count==3 && Argument(method,2,"@") && (action==PXSDKCollector || action==PXSDKInitialization)) return (IMP)VoidObject;
            break;
        case PXSDKRealmWrite:
            if (!strcmp(type,"v") && count==4 && Argument(method,2,"@") && Argument(method,3,@encode(NSUInteger))) return (IMP)RealmWrite; break;
        case PXSDKRealmCreate:
            if (ObjectType(type) && count==5 && Argument(method,2,"@") && Argument(method,3,"@") && Argument(method,4,"^@")) return (IMP)RealmCreate; break;
        case PXSDKCrypto:
            if (ObjectType(type) && count==4 && Argument(method,2,"@") && Argument(method,3,"@")) return (IMP)Crypto; break;
        case PXSDKAdParameters:
            if (ObjectType(type) && count==4 && Argument(method,2,"@") && Argument(method,3,"BOOL")) return (IMP)AdParameters; break;
        default:
            if (ObjectType(type) && count==2) return (IMP)Object0; break;
    }
    return NULL;
}
void PXSDKConfigure(PhoneInfo *(^provider)(void),IMP (^installer)(Class,SEL,IMP,const char *,unsigned)) {
    [RegistryLock() lock]; @try { PhoneProvider=[provider copy]; MethodInstaller=[installer copy]; }
    @finally { [RegistryLock() unlock]; }
}
const PXSDKTarget *PXSDKTargetList(NSUInteger *count) {
    if (count) *count=sizeof(PXSDKTargets)/sizeof(PXSDKTargets[0]); return PXSDKTargets;
}
NSString *PXSDKActionName(PXSDKAction a) {
    NSArray *names=@[@"environment-zero",@"environment-one",@"proxy-zero",@"number-false",@"idfv-string",@"openudid",
        @"device-dictionary",@"gt3-mobile-info",@"mp-cydia",@"ffm-nets-rdates",@"injected-images",@"attribution-token",
        @"orientation",@"wifi",@"location-object",@"location-coordinates",@"launch-time",@"skip-advanced",
        @"disable-debugger",@"optional-collector",@"optional-initialization",@"optional-realm-write",
        @"realm-create-pass-through",@"object-pass-through",@"void-pass-through",@"crypto-pass-through",@"ad-parameters"];
    return a<names.count?names[a]:@"unknown";
}
static void InstallLocked(void) {
    @autoreleasepool {
        if (!Methods) Methods=[NSMutableDictionary dictionary];
        if (!Statuses) Statuses=[NSMutableDictionary dictionary];
        NSUInteger count=0; const PXSDKTarget *targets=PXSDKTargetList(&count);
        for (NSUInteger i=0;i<count;i++) {
            const PXSDKTarget *t=&targets[i]; NSString *key=TargetKey(t);
            Class cls=objc_lookUpClass(t->className); if (t->meta && cls) cls=object_getClass(cls);
            SEL cmd=sel_registerName(t->selector); Method method=cls?class_getInstanceMethod(cls,cmd):NULL;
            NSString *status=@"missing";
            PXSDKEarlyLoadStatus early=PXSDKGetEarlyLoadStatus(t->className);
            BOOL load=t->action==PXSDKInitialization && !strcmp(t->selector,"load");
            if (load && early.installed) status=@"early-load-installed";
            else if (method && MethodInstaller) {
                PXSDKMethod *existing=Methods[Key(cls,cmd)];
                if (existing) status=@"installed";
                else {
                    IMP replacement=Replacement(t->action,method);
                    status=replacement?@"install-failed":@"signature-mismatch";
                    if (replacement) {
                        char result[512]={0}; method_getReturnType(method,result,sizeof(result));
                        PXSDKMethod *ancestor=nil;
                        for (Class parent=class_getSuperclass(cls);parent;parent=class_getSuperclass(parent)) {
                            ancestor=Methods[Key(parent,cmd)]; if (ancestor) break;
                        }
                        if (ancestor && ancestor.action==t->action && method_getImplementation(method)==replacement) status=@"inherited";
                        else {
                            PXSDKMethod *record=[PXSDKMethod new]; record.owner=cls; record.action=t->action;
                            record.original=method_getImplementation(method); Methods[Key(cls,cmd)]=record;
                            IMP original=MethodInstaller(cls,cmd,replacement,result,method_getNumberOfArguments(method));
                            if (original) {
                                record.original=original; status=@"installed";
                            } else [Methods removeObjectForKey:Key(cls,cmd)];
                        }
                    }
                }
            } else if (method) status=@"not-configured";
            NSDictionary *entry=@{@"status":status,@"action":PXSDKActionName(t->action),
                @"loadTimingUnverified":@(load && early.automaticCalls==0),
                @"automaticLoadCalls":@(load?early.automaticCalls:0),
                @"suppressedLoadCalls":@(load?early.suppressedCalls:0),
                @"forwardedLoadCalls":@(load?early.forwardedCalls:0)};
            if (![Statuses[key] isEqual:entry] && ![status isEqual:@"missing"])
                NSLog(@"[ProjectX SDK] %@: %@ (%@)",key,status,entry[@"action"]);
            Statuses[key]=entry;
        }
    }
}
void PXSDKInstallTargets(void) {
    [RegistryLock() lock]; @try { InstallLocked(); } @finally { [RegistryLock() unlock]; }
}
NSDictionary *PXSDKCompatibilityReport(void) {
    [RegistryLock() lock]; @try {
        NSMutableDictionary *report=[Statuses mutableCopy] ?: [NSMutableDictionary dictionary];
        NSUInteger count=0; const PXSDKTarget *targets=PXSDKTargetList(&count);
        for (NSUInteger i=0;i<count;i++) {
            const PXSDKTarget *t=&targets[i];
            if (t->action!=PXSDKInitialization || strcmp(t->selector,"load")) continue;
            PXSDKEarlyLoadStatus early=PXSDKGetEarlyLoadStatus(t->className); if (!early.installed) continue;
            NSString *key=TargetKey(t); NSMutableDictionary *entry=[report[key] mutableCopy] ?: [NSMutableDictionary dictionary];
            entry[@"status"]=@"early-load-installed"; entry[@"action"]=PXSDKActionName(t->action);
            entry[@"loadTimingUnverified"]=@(early.automaticCalls==0);
            entry[@"automaticLoadCalls"]=@(early.automaticCalls); entry[@"suppressedLoadCalls"]=@(early.suppressedCalls);
            entry[@"forwardedLoadCalls"]=@(early.forwardedCalls); report[key]=entry;
        }
        return report;
    } @finally { [RegistryLock() unlock]; }
}
