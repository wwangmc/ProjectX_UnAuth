#import "PXHookSupport.h"
#import <CoreFoundation/CoreFoundation.h>
#import <substrate.h>
static __thread BOOL ResolvingVersion;

static NSString *VersionValue(NSString *bundle,NSString *key) {
    NSDictionary *versions=PXRuntime()[@"appVersions"][bundle ?: @""];
    if ([key isEqual:@"CFBundleShortVersionString"]) return versions[@"version"];
    if ([key isEqual:@"CFBundleVersion"]) return versions[@"build"];
    return nil;
}
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (ResolvingVersion) return %orig;
    ResolvingVersion=YES;
    NSString *value=VersionValue(self.bundleIdentifier,key);
    ResolvingVersion=NO;
    return value ?: %orig;
}
- (NSDictionary *)infoDictionary {
    if (ResolvingVersion) return %orig;
    ResolvingVersion=YES;
    NSDictionary *original=%orig; NSDictionary *versions=PXRuntime()[@"appVersions"][self.bundleIdentifier ?: @""];
    ResolvingVersion=NO;
    if (!versions || !original) return original;
    NSMutableDictionary *result=[original mutableCopy];
    if (versions[@"version"]) result[@"CFBundleShortVersionString"]=versions[@"version"];
    if (versions[@"build"]) result[@"CFBundleVersion"]=versions[@"build"];
    return result;
}
%end
static CFTypeRef (*OldBundleValue)(CFBundleRef,CFStringRef);
static CFTypeRef BundleValue(CFBundleRef bundle,CFStringRef key) {
    if (bundle && key && !ResolvingVersion) {
        ResolvingVersion=YES;
        NSString *value=VersionValue((__bridge NSString *)CFBundleGetIdentifier(bundle),(__bridge NSString *)key);
        ResolvingVersion=NO;
        if (value) return (__bridge CFTypeRef)value;
    }
    return OldBundleValue(bundle,key);
}
%ctor { %init; MSHookFunction((void *)CFBundleGetValueForInfoDictionaryKey,(void *)BundleValue,(void **)&OldBundleValue); }
