#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum { PXSDKLoadUnknown, PXSDKLoadLegacy, PXSDKLoadInfo } PXSDKLoadABI;
typedef bool (*PXSDKFunctionInstaller)(void *target,void *replacement,void **original);
typedef void *(*PXSDKSymbolFinder)(const char *machoName);
typedef struct {
    bool installed;
    unsigned automaticCalls, suppressedCalls, forwardedCalls;
} PXSDKEarlyLoadStatus;

// Installer is Substrate on iOS. Native host integration tests supply Dobby.
bool PXSDKStartEarlyLoad(PXSDKFunctionInstaller installer,PXSDKSymbolFinder finder);
PXSDKLoadABI PXSDKEarlyLoadDispatcherABI(void);
PXSDKEarlyLoadStatus PXSDKGetEarlyLoadStatus(const char *className);
// A conservative semantic decoder for libobjc's exported _objc_load_image bridge.
// It accepts an unchanged-argument tail branch or a checked stack-info wrapper.
bool PXSDKDecodeLoadBridge(const uint32_t *words,size_t count,uintptr_t address,
                          uintptr_t *target,PXSDKLoadABI *abi);
