#import "PXHookSupport.h"
#import "PXSDKCompatibility.h"
#import "PXSDKEarlyLoad.h"
#if __has_include(<substrate.h>)
#import <substrate.h>
#else
// The host regression executable supplies these two backend symbols.
extern void MSHookFunction(void *,void *,void **);
extern void *MSFindSymbol(void *,const char *);
#endif
#import <mach-o/dyld.h>
#import <stdatomic.h>

static atomic_bool pending;
static _Thread_local BOOL scanning;
static void InstallNow(void) {
    if (scanning) return;
    scanning=YES;
    @try { PXSDKInstallTargets(); } @finally { scanning=NO; }
}
static void ImageAdded(const struct mach_header *header,intptr_t slide) {
    // objc_addLoadImageFunc runs under the non-recursive runtime lock: even
    // ordinary ObjC messages/class lookups can abort there. Retry outside the
    // loader callback. Historical automatic +load calls cannot be undone.
    if (atomic_exchange(&pending,true)) return;
    dispatch_async(dispatch_get_main_queue(),^{ atomic_store(&pending,false); InstallNow(); });
}
static bool InstallFunction(void *target,void *replacement,void **original) {
    MSHookFunction(target,replacement,original); return *original!=NULL;
}
static void *FindFunction(const char *name) { return MSFindSymbol(NULL,name); }
__attribute__((constructor)) static void InitSDKCompatibility(void) {
    PXSDKConfigure(^PhoneInfo *{ return PXScopedPhone(); },
        ^IMP(Class cls,SEL sel,IMP hook,const char *type,unsigned count) {
            return PXInstallMethod(cls,sel,hook,type,count)?PXOriginalForClass(cls,sel):NULL;
        });
    BOOL early=PXSDKStartEarlyLoad(InstallFunction,FindFunction);
    NSLog(@"[ProjectX SDK] early +load dispatcher: %@",early?@"installed":@"unavailable; retaining deferred discovery");
    InstallNow();
    _dyld_register_func_for_add_image(ImageAdded);
}
