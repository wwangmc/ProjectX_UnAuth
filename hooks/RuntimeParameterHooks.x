#import "PXHookSupport.h"
#import "PXConfiguration.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Network/Network.h>
#import <Metal/Metal.h>
#import <mach/mach.h>
#import <substrate.h>
#import <dlfcn.h>

static __thread BOOL PXReadingTimeZone;
static NSTimeZone *PXTimeZone(void) {
    if (PXReadingTimeZone) return nil;
    NSString *name=PXRuntime()[@"timeZoneName"]; if (!name.length) return nil;
    PXReadingTimeZone=YES;
    @try { return [NSTimeZone timeZoneWithName:name]; }
    @finally { PXReadingTimeZone=NO; }
}
static NSInteger PXSeconds(NSTimeZone *zone, NSDate *date) {
    PXReadingTimeZone=YES;
    NSInteger result=[zone secondsFromGMTForDate:date ?: NSDate.date];
    PXReadingTimeZone=NO;
    return result;
}
%hook NSTimeZone
+ (NSTimeZone *)localTimeZone { return PXTimeZone() ?: %orig; }
+ (NSTimeZone *)defaultTimeZone { return PXTimeZone() ?: %orig; }
+ (NSTimeZone *)systemTimeZone { return PXTimeZone() ?: %orig; }
%end
%hook __NSLocalTimeZoneI
- (NSString *)name { return !PXReadingTimeZone && [PXRuntime()[@"timeZoneName"] length]?PXRuntime()[@"timeZoneName"]:%orig; }
- (NSInteger)secondsFromGMT { NSTimeZone *zone=PXTimeZone(); return zone?PXSeconds(zone,NSDate.date):%orig; }
- (NSInteger)secondsFromGMTForDate:(NSDate *)date { NSTimeZone *zone=PXTimeZone(); return zone?PXSeconds(zone,date):%orig; }
%end
%hook __NSTimeZone
- (NSString *)name { return !PXReadingTimeZone && [PXRuntime()[@"timeZoneName"] length]?PXRuntime()[@"timeZoneName"]:%orig; }
- (NSInteger)secondsFromGMT { NSTimeZone *zone=PXTimeZone(); return zone?PXSeconds(zone,NSDate.date):%orig; }
%end
%hook AVAudioSession
- (float)outputVolume { NSNumber *volume=PXRuntime()[@"outputVolume"]; return volume?volume.floatValue:%orig; }
- (float)getOutputVolume { NSNumber *volume=PXRuntime()[@"outputVolume"]; return volume?volume.floatValue:%orig; }
%end
%hook NSProcessInfo
- (NSString *)hostName { return PXScopedPhone().deviceName.length?PXScopedPhone().deviceName:%orig; }
- (NSUInteger)activeProcessorCount { NSUInteger count=PXScopedPhone().deviceModel.cpuCoreCount.unsignedIntegerValue; return count?count:%orig; }
%end
%hook UIScreenMode
- (CGSize)size {
    NSArray *parts=[PXScopedPhone().deviceModel.resolution componentsSeparatedByString:@"x"];
    if (parts.count!=2) parts=[PXScopedPhone().deviceModel.resolution componentsSeparatedByString:@"×"];
    if (parts.count==2 && [parts[0] doubleValue]>0 && [parts[1] doubleValue]>0) return CGSizeMake([parts[0] doubleValue],[parts[1] doubleValue]);
    return %orig;
}
%end
%hook UIWindow
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets=%orig;
    NSDictionary *d=PXRuntime();
    if (d[@"screenTopInset"]) insets.top=[d[@"screenTopInset"] doubleValue];
    if (d[@"screenBottomInset"]) insets.bottom=[d[@"screenBottomInset"] doubleValue];
    return insets;
}
%end

static int PXConnection(void) { PhoneInfo *p=PXScopedPhone(); return p?p.networkInfo.connectionType:0; }
static bool (*OldUses)(nw_path_t,nw_interface_type_t);
static bool Uses(nw_path_t p,nw_interface_type_t t) {
    int c=PXConnection(); if (!c) return OldUses(p,t);
    return (c==1 && t==nw_interface_type_wifi)||(c==2 && t==nw_interface_type_cellular);
}
static bool (*OldIPv4)(nw_path_t); static bool IPv4(nw_path_t p) { int c=PXConnection(); return c?c!=3:OldIPv4(p); }
static bool (*OldIPv6)(nw_path_t); static bool IPv6(nw_path_t p) {
    int c=PXConnection(); return c?(c!=3 && PXScopedPhone().networkInfo.localIPv6Address.length>0):OldIPv6(p);
}
static nw_interface_type_t (*OldType)(nw_interface_t);
static nw_interface_type_t Type(nw_interface_t i) { int c=PXConnection(); return c==1?nw_interface_type_wifi:c==2?nw_interface_type_cellular:c==3?nw_interface_type_other:OldType(i); }
static const char *(*OldName)(nw_interface_t);
static const char *Name(nw_interface_t i) { int c=PXConnection(); return c==1?"en0":c==2?"pdp_ip0":OldName(i); }
static kern_return_t (*OldHostInfo)(host_t,host_flavor_t,host_info_t,mach_msg_type_number_t *);
static kern_return_t HostInfo(host_t host,host_flavor_t flavor,host_info_t info,mach_msg_type_number_t *count) {
    kern_return_t r=OldHostInfo(host,flavor,info,count);
    DeviceModel *m=PXScopedPhone().deviceModel;
    if (r==KERN_SUCCESS && info && count && flavor==HOST_BASIC_INFO && *count>=HOST_BASIC_INFO_COUNT && m) {
        host_basic_info_t b=(host_basic_info_t)info;
        if (m.cpuCoreCount.intValue>0) b->max_cpus=b->avail_cpus=b->physical_cpu=b->physical_cpu_max=b->logical_cpu=b->logical_cpu_max=m.cpuCoreCount.intValue;
        uint64_t bytes=PXDeviceMemoryBytes(m);
        if (bytes>0) {
            b->max_mem=bytes; b->memory_size=(uint32_t)MIN(bytes,UINT32_MAX);
        }
    }
    return r;
}
static NSString *GPUName(id self,SEL cmd) {
    NSString *name=PXScopedPhone().deviceModel.gpuFamily;
    IMP old=PXOriginalMethod(self,cmd); return name.length?name:old?((id(*)(id,SEL))old)(self,cmd):nil;
}
static uint64_t GPUMemory(id self,SEL cmd) { NSNumber *n=PXRuntime()[@"gpuWorkingSetSize"]; IMP old=PXOriginalMethod(self,cmd); return n?n.unsignedLongLongValue:old?((uint64_t(*)(id,SEL))old)(self,cmd):0; }
static BOOL GPURaytracing(id self,SEL cmd) { NSNumber *n=PXRuntime()[@"gpuRaytracing"]; IMP old=PXOriginalMethod(self,cmd); return n?n.boolValue:old?((BOOL(*)(id,SEL))old)(self,cmd):NO; }
static id<MTLDevice> (*OldMetal)(void);
static id<MTLDevice> Metal(void) {
    id<MTLDevice> device=OldMetal();
    if (device) {
        Class cls=object_getClass(device);
        PXInstallMethod(cls,@selector(name),(IMP)GPUName,"@",2);
        PXInstallMethod(cls,@selector(recommendedMaxWorkingSetSize),(IMP)GPUMemory,"Q",2);
        PXInstallMethod(cls,@selector(supportsRaytracing),(IMP)GPURaytracing,"B",2);
    }
    return device;
}
%ctor {
    %init;
    MSHookFunction((void *)nw_path_uses_interface_type,(void *)Uses,(void **)&OldUses);
    MSHookFunction((void *)nw_path_has_ipv4,(void *)IPv4,(void **)&OldIPv4);
    MSHookFunction((void *)nw_path_has_ipv6,(void *)IPv6,(void **)&OldIPv6);
    MSHookFunction((void *)nw_interface_get_type,(void *)Type,(void **)&OldType);
    MSHookFunction((void *)nw_interface_get_name,(void *)Name,(void **)&OldName);
    MSHookFunction((void *)host_info,(void *)HostInfo,(void **)&OldHostInfo);
    MSHookFunction((void *)MTLCreateSystemDefaultDevice,(void *)Metal,(void **)&OldMetal);
}
