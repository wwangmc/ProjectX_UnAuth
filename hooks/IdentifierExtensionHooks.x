#import "PXHookSupport.h"
#import <UIKit/UIKit.h>

%hook OpenUDID
+ (NSString *)value { return [PXRuntime()[@"openUDID"] length]?PXRuntime()[@"openUDID"]:%orig; }
%end
%hook ASIdentifierManager
- (BOOL)isAdvertisingTrackingEnabled {
    return PXRuntimeFlag(@"trackingOverride")?[PXRuntime()[@"trackingStatus"] integerValue]==3:%orig;
}
%end
%hook ATTrackingManager
+ (NSUInteger)trackingAuthorizationStatus {
    return PXRuntimeFlag(@"trackingOverride")?[PXRuntime()[@"trackingStatus"] unsignedIntegerValue]:%orig;
}
+ (void)requestTrackingAuthorizationWithCompletionHandler:(void(^)(NSUInteger))completion {
    if (!PXRuntimeFlag(@"trackingOverride")) { %orig; return; }
    NSUInteger status=[PXRuntime()[@"trackingStatus"] unsignedIntegerValue];
    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(status); });
}
%end
%hook LSApplicationProxy
- (NSUUID *)deviceIdentifierForVendor {
    NSUUID *uuid=[[NSUUID alloc] initWithUUIDString:PXScopedPhone().idfv ?: @""];
    return uuid ?: %orig;
}
%end
%hook DCDevice
- (BOOL)isSupported { return PXRuntimeFlag(@"deviceCheckOverride")?NO:%orig; }
%end
static void PXPushToken(id self,SEL cmd,UIApplication *app,NSData *token) {
    NSString *hex=PXRuntime()[@"pushTokenHex"];
    if (hex.length) {
        NSMutableData *data=[NSMutableData dataWithCapacity:hex.length/2];
        for (NSUInteger i=0;i+1<hex.length;i+=2) {
            unsigned value=0; [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i,2)]] scanHexInt:&value];
            uint8_t byte=(uint8_t)value; [data appendBytes:&byte length:1];
        }
        token=data;
    }
    IMP old=PXOriginalMethod(self,cmd);
    if (old) ((void(*)(id,SEL,id,id))old)(self,cmd,app,token);
}
%hook UIApplication
- (void)setDelegate:(id)delegate {
    if (delegate) PXInstallMethod(object_getClass(delegate),
        @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:),(IMP)PXPushToken,"v",4);
    %orig(delegate);
}
%end
%ctor { %init; }
