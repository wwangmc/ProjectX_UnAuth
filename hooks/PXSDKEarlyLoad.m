#import "PXSDKEarlyLoad.h"
#import <objc/runtime.h>
#import <mach-o/loader.h>
#import <mach/vm_prot.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <string.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

// This is called only while +load runs, after libobjc releases runtimeLock.
extern BOOL PXSDKShouldSuppressInitialization(void);
typedef void (*LoadIMP)(id,SEL);
typedef struct {
    const char *name;
    atomic_uint state; // 0 absent, 1 preparing, 2 installed, 3 incompatible signature
    Class cls;
    const struct mach_header *image;
    LoadIMP original;
    atomic_uint automaticCalls, suppressedCalls, forwardedCalls;
} LoadSlot;
static LoadSlot Slots[]={
    {.name="YjAxOGE4YTAwODQ5MjMxZTY2_EC"}, {.name="MWFmMDM5OTk2ZTdkMWY4ZmUy_EC"},
    {.name="NGMzNzhjNmI0NDQyMzdiNTc0_EC"}, {.name="NzY1YjdiMzkwYzc2N2U5YWMz_EC"}, {.name="PDXC"}
};
static void (*OriginalLegacy)(const char *,const struct mach_header *);
static void (*OriginalInfo)(const void *);
static atomic_uint DispatcherABI;
static _Thread_local const struct mach_header *LoadingImage;
static _Thread_local bool ReadingPolicy;

static void Invoke(unsigned index,id self,SEL cmd) {
    LoadSlot *slot=&Slots[index];
    if (LoadingImage && slot->image==LoadingImage) atomic_fetch_add(&slot->automaticCalls,1);
    bool suppress=false;
    if (!ReadingPolicy) {
        ReadingPolicy=true;
        @try { suppress=PXSDKShouldSuppressInitialization(); } @finally { ReadingPolicy=false; }
    }
    if (suppress) { atomic_fetch_add(&slot->suppressedCalls,1); return; }
    atomic_fetch_add(&slot->forwardedCalls,1);
    if (slot->original) slot->original(self,cmd);
}
#define TRAMPOLINE(n) static void Load##n(id self,SEL cmd) { Invoke(n,self,cmd); }
TRAMPOLINE(0) TRAMPOLINE(1) TRAMPOLINE(2) TRAMPOLINE(3) TRAMPOLINE(4)
static LoadIMP const Replacements[]={Load0,Load1,Load2,Load3,Load4};

static void Prepare(const struct mach_header *image) {
    // The dispatcher is entered BEFORE prepare_load_methods captures +load IMPs.
    // Runtime APIs are safe here: map_images has finished and released its lock.
    for (unsigned i=0;i<sizeof(Slots)/sizeof(Slots[0]);i++) {
        LoadSlot *slot=&Slots[i]; if (atomic_load_explicit(&slot->state,memory_order_acquire)) continue;
        Class cls=objc_lookUpClass(slot->name); if (!cls) continue;
        Dl_info owner={0};
        if (!dladdr((__bridge const void *)cls,&owner) || (image && owner.dli_fbase!=image)) continue;
        unsigned expected=0;
        if (!atomic_compare_exchange_strong(&slot->state,&expected,1)) continue;
        Method method=class_getInstanceMethod(object_getClass(cls),sel_registerName("load"));
        char result[32]={0}; if (method) method_getReturnType(method,result,sizeof(result));
        if (!method || strcmp(result,"v") || method_getNumberOfArguments(method)!=2) {
            atomic_store_explicit(&slot->state,3,memory_order_release); continue;
        }
        slot->cls=cls; slot->image=owner.dli_fbase;
        slot->original=(LoadIMP)method_getImplementation(method);
        IMP old=method_setImplementation(method,(IMP)Replacements[i]);
        if (old) slot->original=(LoadIMP)old;
        atomic_store_explicit(&slot->state,2,memory_order_release);
    }
}
static void Legacy(const char *path,const struct mach_header *image) {
    Prepare(image); const struct mach_header *previous=LoadingImage; LoadingImage=image;
    @try { OriginalLegacy(path,image); } @finally { LoadingImage=previous; }
}
static void Info(const void *info) {
    // Apple's v2+ info ABI starts with the image header. All remaining fields
    // stay opaque and are forwarded unchanged to libobjc.
    const struct mach_header *image=info?*(const struct mach_header * const *)info:NULL;
    Prepare(image); const struct mach_header *previous=LoadingImage; LoadingImage=image;
    @try { OriginalInfo(info); } @finally { LoadingImage=previous; }
}
static bool InstructionReturn(uint32_t w) {
    return w==0xd65f03c0 || w==0xd65f0bff || w==0xd65f0fff; // ret, retaa, retab
}
static uintptr_t BranchTarget(uintptr_t pc,uint32_t instruction) {
    int64_t displacement=(int64_t)(int32_t)((instruction&0x03ffffff)<<6)>>4;
    return (uintptr_t)((intptr_t)pc+displacement);
}
bool PXSDKDecodeLoadBridge(const uint32_t *words,size_t count,uintptr_t address,
                          uintptr_t *target,PXSDKLoadABI *abi) {
    if (!words || !target || !abi || count>32) return false;
    *target=0; *abi=PXSDKLoadUnknown;
    int stored=-1,zeroed=-1,argument=-1,frame=-1; bool called=false,restored=false; uintptr_t destination=0;
    for (size_t i=0;i<count;i++) {
        uint32_t w=words[i];
        if (w==0xd503201f || w==0xd503245f || w==0xd503233f || w==0xd503237f || w==0xd50323bf || w==0xd50323ff) continue;
        if ((w&0xfc000000)==0x14000000) {
            // Legacy bridge: no argument changes or stack frame, only a tail call.
            if (called || stored!=-1 || zeroed!=-1 || argument!=-1 || frame!=-1) return false;
            *target=BranchTarget(address+4*i,w); *abi=PXSDKLoadLegacy; return *target!=address;
        }
        if ((w&0xffc003ff)==0xd10003ff) {
            if (frame!=-1 || called) return false; frame=(w>>10)&0xfff; continue;
        }
        if ((w&0xffc07fff)==0xa90003e1) { // stp x1,x0,[sp,#off]: mh,path
            if (stored!=-1 || called) return false;
            int off=(int)((w>>15)&127); stored=(off&64?off-128:off)*8; continue;
        }
        if ((w&0xffc07fff)==0xa9007fff) { // stp xzr,xzr,[sp,#off]: metadata,flags
            if (zeroed!=-1 || called) return false;
            int off=(int)((w>>15)&127); zeroed=(off&64?off-128:off)*8; continue;
        }
        if ((w&0xffc003ff)==0x910003e0) {
            if (argument!=-1 || called) return false; argument=(w>>10)&0xfff; continue;
        }
        if ((w&0xfc000000)==0x94000000) {
            if (called || stored<0 || argument!=stored || zeroed!=stored+16 || frame<stored+32 || frame%16) return false;
            called=true; destination=BranchTarget(address+4*i,w); continue;
        }
        // Ordinary x29/x30 frame save/restore, frame-pointer setup and stack teardown.
        if ((w&0xffc07fff)==0xa9007bfd || (w&0xffc07fff)==0xa9407bfd || (w&0xffc003ff)==0x910003fd) continue;
        if ((w&0xffc003ff)==0x910003ff) {
            if (!called || restored || ((w>>10)&0xfff)!=(unsigned)frame) return false; restored=true; continue;
        }
        if (InstructionReturn(w)) {
            if (!called || !restored || !destination) return false;
            *target=destination; *abi=PXSDKLoadInfo; return true;
        }
        return false;
    }
    return false;
}
static const void *CodeAddress(const void *p) {
#if __has_feature(ptrauth_calls)
    return ptrauth_strip(p,ptrauth_key_function_pointer);
#else
    return p;
#endif
}
static bool ExecutableRange(const struct mach_header_64 *header,uintptr_t address,size_t bytes) {
    if (!header || header->magic!=MH_MAGIC_64 || header->ncmds>4096 || header->sizeofcmds>(1<<20)) return false;
    const uint8_t *p=(const uint8_t *)(header+1),*end=p+header->sizeofcmds;
    intptr_t slide=0; bool foundSlide=false;
    for (unsigned pass=0;pass<2;pass++) {
        const uint8_t *cursor=p;
        for (unsigned i=0;i<header->ncmds;i++) {
            if (cursor+sizeof(struct load_command)>end) return false;
            const struct load_command *load=(const void *)cursor;
            if (load->cmdsize<sizeof(*load) || load->cmdsize>(size_t)(end-cursor)) return false;
            if (load->cmd==LC_SEGMENT_64 && load->cmdsize>=sizeof(struct segment_command_64)) {
                const struct segment_command_64 *seg=(const void *)cursor;
                // Images in the dyld shared cache use cache-relative file offsets,
                // so their header segment's fileoff need not be zero.
                if (pass==0 && !strncmp(seg->segname,"__TEXT",16) && seg->filesize>=sizeof(*header)+header->sizeofcmds) {
                    slide=(intptr_t)header-(intptr_t)seg->vmaddr; foundSlide=true;
                }
                if (pass==1 && (seg->initprot&VM_PROT_EXECUTE)) {
                    uintptr_t start=seg->vmaddr+slide;
                    if (address>=start && bytes<=seg->vmsize && address-start<=seg->vmsize-bytes) return true;
                }
            }
            cursor+=load->cmdsize;
        }
        if (!foundSlide) return false;
    }
    return false;
}
bool PXSDKStartEarlyLoad(PXSDKFunctionInstaller installer,PXSDKSymbolFinder finder) {
    if (atomic_load(&DispatcherABI)) return true;
    if (!installer) return false;
    void *bridge=dlsym(RTLD_DEFAULT,"_objc_load_image"); Dl_info library={0};
    if (!bridge || !dladdr(CodeAddress(bridge),&library) || !library.dli_fname || !strstr(library.dli_fname,"libobjc")) return false;
    void *target=NULL; PXSDKLoadABI abi=PXSDKLoadUnknown;
    const char *symbols[]={"__Z11load_imagesPK29_dyld_objc_notify_mapped_info","__Z11load_imagesPKcPK11mach_header"};
    if (finder) for (unsigned i=0;i<2;i++) {
        void *candidate=finder(symbols[i]); Dl_info owner={0};
        if (candidate && dladdr(CodeAddress(candidate),&owner) && owner.dli_fbase==library.dli_fbase) {
            target=(void *)CodeAddress(candidate); abi=i?PXSDKLoadLegacy:PXSDKLoadInfo; break;
        }
    }
#if defined(__arm64__) || defined(__aarch64__)
    if (!target && ExecutableRange(library.dli_fbase,(uintptr_t)CodeAddress(bridge),128)) {
        uintptr_t decoded=0;
        if (PXSDKDecodeLoadBridge(CodeAddress(bridge),32,(uintptr_t)CodeAddress(bridge),&decoded,&abi) &&
            ExecutableRange(library.dli_fbase,decoded,4) && decoded!=(uintptr_t)CodeAddress(bridge)) target=(void *)decoded;
    }
#endif
    if (!target) return false;
    void **original=abi==PXSDKLoadLegacy?(void **)&OriginalLegacy:(void **)&OriginalInfo;
    if (!installer(target,abi==PXSDKLoadLegacy?(void *)Legacy:(void *)Info,original) || !*original) return false;
    atomic_store_explicit(&DispatcherABI,abi,memory_order_release);
    Prepare(NULL); return true;
}
PXSDKLoadABI PXSDKEarlyLoadDispatcherABI(void) { return atomic_load_explicit(&DispatcherABI,memory_order_acquire); }
PXSDKEarlyLoadStatus PXSDKGetEarlyLoadStatus(const char *name) {
    PXSDKEarlyLoadStatus result={0}; if (!name) return result;
    for (unsigned i=0;i<sizeof(Slots)/sizeof(Slots[0]);i++) if (!strcmp(name,Slots[i].name)) {
        result.installed=atomic_load_explicit(&Slots[i].state,memory_order_acquire)==2;
        result.automaticCalls=atomic_load(&Slots[i].automaticCalls);
        result.suppressedCalls=atomic_load(&Slots[i].suppressedCalls);
        result.forwardedCalls=atomic_load(&Slots[i].forwardedCalls); break;
    }
    return result;
}
