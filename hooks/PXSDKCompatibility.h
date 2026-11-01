#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "PhoneInfo.h"

typedef NS_ENUM(NSUInteger, PXSDKAction) {
    PXSDKEnvironmentZero, PXSDKEnvironmentOne, PXSDKProxyZero, PXSDKNumberFalse,
    PXSDKIDFV, PXSDKOpenUDID, PXSDKDictionary, PXSDKMobileInfo, PXSDKJailbreakInfo,
    PXSDKFingerprint, PXSDKInjectedImages, PXSDKAttributionToken, PXSDKOrientation,
    PXSDKWiFi, PXSDKLocationObject, PXSDKLocationCoordinates, PXSDKLaunchTime,
    PXSDKSkipAdvanced, PXSDKDisableDebugger, PXSDKCollector, PXSDKInitialization,
    PXSDKRealmWrite, PXSDKRealmCreate, PXSDKPassObject, PXSDKPassVoid, PXSDKCrypto,
    PXSDKAdParameters
};
typedef struct {
    const char *className, *selector;
    BOOL meta;
    PXSDKAction action;
} PXSDKTarget;

// The installer must return the actual original IMP supplied by the hook backend.
// Tests use the same engine with Objective-C runtime fixtures instead of Substrate.
void PXSDKConfigure(PhoneInfo *(^provider)(void),
    IMP (^installer)(Class, SEL, IMP, const char *, unsigned));
void PXSDKInstallTargets(void);
NSDictionary *PXSDKCompatibilityReport(void);
const PXSDKTarget *PXSDKTargetList(NSUInteger *count);
NSString *PXSDKActionName(PXSDKAction action);
id PXSDKTransformValue(id value, PhoneInfo *phone);
BOOL PXSDKShouldSuppressInitialization(void);
