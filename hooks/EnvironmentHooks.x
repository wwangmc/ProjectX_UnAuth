#import "PXHookSupport.h"
#import <UIKit/UIKit.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <CFNetwork/CFNetwork.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <ifaddrs.h>
#import <errno.h>
#import <fcntl.h>
#import <stdarg.h>

static __thread BOOL Inspecting;
static BOOL HiddenPath(const char *raw) {
    if (!raw || Inspecting) return NO;
    Inspecting=YES; BOOL hidden=NO;
    @try {
        if (PXRuntimeFlag(@"maskEnvironment")) {
            NSString *path=[[NSString stringWithUTF8String:raw] stringByStandardizingPath];
            for (NSString *prefix in @[@"/var/jb",@"/private/var/jb",@"/Applications/Cydia.app",@"/Applications/Sileo.app",
                @"/Applications/Zebra.app",@"/Library/MobileSubstrate",@"/usr/lib/TweakInject",@"/Library/TweakInject",
                @"/usr/sbin/sshd",@"/etc/apt",@"/var/lib/apt",@"/private/var/lib/apt",@"/bin/bash",@"/bin/sh"])
                if ([path isEqual:prefix] || [path hasPrefix:[prefix stringByAppendingString:@"/"]]) { hidden=YES; break; }
        }
    } @finally { Inspecting=NO; }
    return hidden;
}
static BOOL HiddenImage(const char *raw) {
    if (!raw || Inspecting) return NO;
    Inspecting=YES; BOOL hidden=NO;
    @try {
        if (PXRuntimeFlag(@"maskEnvironment")) {
            NSString *name=[NSString stringWithUTF8String:raw].lowercaseString;
            for (NSString *word in @[@"mobilesubstrate",@"cydiasubstrate",@"ellekit",@"libhooker",@"frida",@"projectxtweak",@"gpttweak"])
                if ([name containsString:word]) { hidden=YES; break; }
        }
    } @finally { Inspecting=NO; }
    return hidden;
}
%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path { return HiddenPath(path.fileSystemRepresentation)?NO:%orig; }
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (HiddenPath(path.fileSystemRepresentation)) { if (isDirectory) *isDirectory=NO; return NO; } return %orig;
}
- (BOOL)isReadableFileAtPath:(NSString *)path { return HiddenPath(path.fileSystemRepresentation)?NO:%orig; }
- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error {
    if (HiddenPath(path.fileSystemRepresentation)) { if (error) *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil]; return nil; } return %orig;
}
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    if (HiddenPath(path.fileSystemRepresentation)) { if (error) *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil]; return nil; }
    NSArray *values=%orig; NSMutableArray *filtered=[NSMutableArray array];
    for (NSString *value in values) if (!HiddenPath([path stringByAppendingPathComponent:value].fileSystemRepresentation)) [filtered addObject:value];
    return values?filtered:nil;
}
- (NSArray *)subpathsAtPath:(NSString *)path {
    if (HiddenPath(path.fileSystemRepresentation)) return nil;
    NSArray *values=%orig; NSMutableArray *filtered=[NSMutableArray array];
    for (NSString *value in values) if (!HiddenPath([path stringByAppendingPathComponent:value].fileSystemRepresentation)) [filtered addObject:value];
    return values?filtered:nil;
}
%end
%hook UIApplication
- (BOOL)canOpenURL:(NSURL *)url {
    if (PXRuntimeFlag(@"maskEnvironment") && [@[@"cydia",@"sileo",@"zbra",@"filza"] containsObject:url.scheme.lowercaseString]) return NO;
    return %orig;
}
%end

static int (*OldAccess)(const char *,int);
static int Access(const char *p,int mode) { if (HiddenPath(p)) { errno=ENOENT; return -1; } return OldAccess(p,mode); }
static int (*OldStat)(const char *,struct stat *);
static int Stat(const char *p,struct stat *s) { if (HiddenPath(p)) { errno=ENOENT; return -1; } return OldStat(p,s); }
static int (*OldLstat)(const char *,struct stat *);
static int Lstat(const char *p,struct stat *s) { if (HiddenPath(p)) { errno=ENOENT; return -1; } return OldLstat(p,s); }
static FILE *(*OldFopen)(const char *,const char *);
static FILE *Fopen(const char *p,const char *mode) { if (HiddenPath(p)) { errno=ENOENT; return NULL; } return OldFopen(p,mode); }
static int (*OldOpen)(const char *,int,...);
static int Open(const char *p,int flags,...) {
    mode_t mode=0;
    if (flags&O_CREAT) { va_list args; va_start(args,flags); mode=(mode_t)va_arg(args,int); va_end(args); }
    if (HiddenPath(p)) { errno=ENOENT; return -1; } return OldOpen(p,flags,mode);
}
static ssize_t (*OldReadlink)(const char *,char *,size_t);
static ssize_t Readlink(const char *p,char *out,size_t count) { if (HiddenPath(p)) { errno=ENOENT; return -1; } return OldReadlink(p,out,count); }
static char *(*OldGetenv)(const char *);
static char *Getenv(const char *name) {
    if (name && !Inspecting && (!strcmp(name,"DYLD_INSERT_LIBRARIES") || !strcmp(name,"DYLD_LIBRARY_PATH") || !strcmp(name,"DYLD_FRAMEWORK_PATH"))) {
        Inspecting=YES; BOOL enabled=PXRuntimeFlag(@"maskEnvironment"); Inspecting=NO; if (enabled) return NULL;
    }
    return OldGetenv(name);
}
static const char *(*OldImageName)(uint32_t);
static const char *ImageName(uint32_t index) { const char *name=OldImageName(index); return HiddenImage(name)?"/usr/lib/libSystem.B.dylib":name; }
static const char **(*OldImageNames)(unsigned int *);
static const char **ImageNames(unsigned int *count) {
    const char **names=OldImageNames(count); if (!names || !count) return names;
    unsigned int written=0;
    for (unsigned int i=0;i<*count;i++) if (!HiddenImage(names[i])) names[written++]=names[i];
    *count=written; return names;
}
static CFDictionaryRef (*OldProxy)(void);
static CFDictionaryRef Proxy(void) {
    CFDictionaryRef original=OldProxy();
    if (!original || !PXRuntimeFlag(@"maskProxy")) return original;
    NSMutableDictionary *settings=[(__bridge NSDictionary *)original mutableCopy];
    for (NSString *key in @[@"HTTPProxy",@"HTTPPort",@"HTTPSProxy",@"HTTPSPort",@"SOCKSProxy",@"SOCKSPort",@"ProxyAutoConfigURLString",@"__SCOPED__"]) [settings removeObjectForKey:key];
    for (NSString *key in @[@"HTTPEnable",@"HTTPSEnable",@"SOCKSEnable",@"ProxyAutoConfigEnable",@"ProxyAutoDiscoveryEnable"]) settings[key]=@0;
    CFRelease(original); return (__bridge_retained CFDictionaryRef)settings;
}

// Clone only list nodes; the original allocation owns names/addresses until freeifaddrs.
static NSMutableDictionary *OriginalLists;
static int (*OldGetifaddrs)(struct ifaddrs **);
static void (*OldFreeifaddrs)(struct ifaddrs *);
static int Getifaddrs(struct ifaddrs **result) {
    int status=OldGetifaddrs(result);
    if (status || !result || !*result || !PXRuntimeFlag(@"maskProxy")) return status;
    struct ifaddrs *original=*result,*head=NULL,**tail=&head;
    for (struct ifaddrs *i=original;i;i=i->ifa_next) {
        const char *name=i->ifa_name ?: "";
        if (!strncmp(name,"utun",4) || !strncmp(name,"tun",3) || !strncmp(name,"tap",3) || !strncmp(name,"ppp",3) || !strncmp(name,"ipsec",5)) continue;
        struct ifaddrs *node=malloc(sizeof(*node));
        if (!node) { while (head) { struct ifaddrs *next=head->ifa_next; free(head); head=next; } return status; }
        *node=*i; node->ifa_next=NULL; *tail=node; tail=&node->ifa_next;
    }
    if (!head) { OldFreeifaddrs(original); *result=NULL; return status; }
    @synchronized (NSObject.class) {
        if (!OriginalLists) OriginalLists=[NSMutableDictionary dictionary];
        OriginalLists[[NSValue valueWithPointer:head]]=[NSValue valueWithPointer:original];
    }
    *result=head; return status;
}
static void Freeifaddrs(struct ifaddrs *list) {
    struct ifaddrs *original=NULL;
    @synchronized (NSObject.class) {
        NSValue *key=[NSValue valueWithPointer:list]; original=[OriginalLists[key] pointerValue]; [OriginalLists removeObjectForKey:key];
    }
    if (!original) { OldFreeifaddrs(list); return; }
    while (list) { struct ifaddrs *next=list->ifa_next; free(list); list=next; }
    OldFreeifaddrs(original);
}
%ctor {
    %init;
    MSHookFunction((void *)access,(void *)Access,(void **)&OldAccess);
    MSHookFunction((void *)stat,(void *)Stat,(void **)&OldStat);
    MSHookFunction((void *)lstat,(void *)Lstat,(void **)&OldLstat);
    MSHookFunction((void *)fopen,(void *)Fopen,(void **)&OldFopen);
    MSHookFunction((void *)open,(void *)Open,(void **)&OldOpen);
    MSHookFunction((void *)readlink,(void *)Readlink,(void **)&OldReadlink);
    MSHookFunction((void *)getenv,(void *)Getenv,(void **)&OldGetenv);
    MSHookFunction((void *)_dyld_get_image_name,(void *)ImageName,(void **)&OldImageName);
    MSHookFunction((void *)objc_copyImageNames,(void *)ImageNames,(void **)&OldImageNames);
    MSHookFunction((void *)CFNetworkCopySystemProxySettings,(void *)Proxy,(void **)&OldProxy);
    MSHookFunction((void *)getifaddrs,(void *)Getifaddrs,(void **)&OldGetifaddrs);
    MSHookFunction((void *)freeifaddrs,(void *)Freeifaddrs,(void **)&OldFreeifaddrs);
}
