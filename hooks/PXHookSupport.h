#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "DataManager.h"

static inline PhoneInfo *PXScopedPhone(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
    if (!bundle.length || [bundle isEqual:@"com.hydra.projectx"] ||
        [NSBundle.mainBundle.executablePath hasPrefix:@"/System/"]) return nil;
    return CurrentPhoneInfo();
}
static inline NSDictionary *PXRuntime(void) { return PXScopedPhone().runtime ?: @{}; }
static inline BOOL PXRuntimeFlag(NSString *key) { return [PXRuntime()[key] boolValue]; }
BOOL PXInstallMethod(Class cls, SEL selector, IMP replacement, const char *returnType, unsigned arguments);
IMP PXOriginalMethod(id object, SEL selector);
IMP PXOriginalForClass(Class cls, SEL selector);
