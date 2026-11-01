#import <Foundation/Foundation.h>

// Shared by the app, daemon and tweak. No device APIs or preference writes here.
NSDictionary *PXValidateRuntime(id value, NSError **error);
NSDictionary *PXValidateOptions(id value, NSError **error);
NSDictionary *PXValidatePhoneDictionary(id value, NSError **error);
NSArray<NSString *> *PXValidatedRelativePaths(id value, NSError **error);
BOOL PXHexTokenIsValid(id value);
BOOL PXValidBundleIdentifier(id value);
NSError *PXError(NSString *message);
@class DeviceModel;
unsigned long long PXDeviceMemoryBytes(DeviceModel *model);
