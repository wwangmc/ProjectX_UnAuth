#import "PXCommandService.h"
#import "PXConfiguration.h"
#import "PXArchive.h"
#import "PXContainerFiles.h"
#import "PhoneInfo.h"
#import "ProfileManager.h"
#import "SettingManager.h"
#import "DataGenManager.h"
#import "AppScopeManager.h"
#import "ActionManager.h"
#import "DBManager.h"
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <math.h>
#import <unistd.h>
#import <fcntl.h>

extern char **environ;
static BOOL WriteJSON(id value,NSString *path,NSError **error) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:error];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:error];
}
static id ReadJSON(NSString *path,NSError **error) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation,&st) || !S_ISREG(st.st_mode) || st.st_size>4*1024*1024) {
        if (error) *error=PXError(@"参数/清单文件不存在、过大或不是普通文件"); return nil;
    }
    NSData *data=[NSData dataWithContentsOfFile:path options:0 error:error];
    return data?[NSJSONSerialization JSONObjectWithData:data options:0 error:error]:nil;
}
static void StopApp(NSString *bundle) {
    LSApplicationProxy *proxy=[LSApplicationProxy applicationProxyForIdentifier:bundle];
    NSString *name=[proxy valueForKey:@"bundleExecutable"];
    if (!name.length) return;
    NSString *tool=[NSFileManager.defaultManager isExecutableFileAtPath:@"/var/jb/usr/bin/killall"]?@"/var/jb/usr/bin/killall":@"/usr/bin/killall";
    char *args[]={(char *)tool.fileSystemRepresentation,"-9",(char *)name.UTF8String,NULL};
    pid_t pid=0;
    if (posix_spawn(&pid,tool.fileSystemRepresentation,NULL,NULL,args,environ)==0) { int status=0; waitpid(pid,&status,0); }
}
static NSString *Container(NSString *bundle,NSError **error) {
    if (!PXValidBundleIdentifier(bundle)) { if (error) *error=PXError(@"包名无效"); return nil; }
    LSApplicationProxy *proxy=[LSApplicationProxy applicationProxyForIdentifier:bundle];
    NSString *path=[[proxy valueForKey:@"dataContainerURL"] path];
    NSString *resolved=path.stringByResolvingSymlinksInPath;
    BOOL allowed=NO;
    for (NSString *prefix in @[@"/private/var/mobile/Containers/Data/Application/",@"/var/mobile/Containers/Data/Application/",@"/private/var/containers/Data/Application/",@"/var/containers/Data/Application/"])
        if ([resolved hasPrefix:prefix] && [resolved.pathComponents count]==[prefix.pathComponents count]+1) allowed=YES;
    if (!allowed) { if (error) *error=PXError(@"无法确定应用沙盒路径"); return nil; }
    return resolved;
}
static NSDictionary *RelatedContainers(NSString *bundle) {
    LSApplicationProxy *proxy=[LSApplicationProxy applicationProxyForIdentifier:bundle];
    NSMutableDictionary *paths=[NSMutableDictionary dictionary];
    NSDictionary *groups=nil; NSArray *plugins=nil;
    @try {
        if ([proxy respondsToSelector:NSSelectorFromString(@"groupContainerURLs")]) groups=[proxy valueForKey:@"groupContainerURLs"];
        if ([proxy respondsToSelector:NSSelectorFromString(@"plugInKitPlugins")]) plugins=[proxy valueForKey:@"plugInKitPlugins"];
    } @catch (NSException *exception) { return paths; }
    void (^add)(NSString *,NSURL *,NSString *)=^(NSString *key,NSURL *url,NSString *kind) {
        if (!PXValidBundleIdentifier(key) || ![url isKindOfClass:NSURL.class]) return;
        NSString *path=url.path.stringByResolvingSymlinksInPath;
        NSString *suffix=[NSString stringWithFormat:@"/Containers/%@/",kind];
        NSRange range=[path rangeOfString:suffix];
        if (range.location==NSNotFound || !([path hasPrefix:@"/private/var/mobile/"] || [path hasPrefix:@"/var/mobile/"])) return;
        NSString *tail=[path substringFromIndex:NSMaxRange(range)];
        if (!tail.length || [tail containsString:@"/"]) return;
        paths[[NSString stringWithFormat:@"%@-%@",[kind hasPrefix:@"Shared"]?@"group":@"extension",key]]=path;
    };
    if ([groups isKindOfClass:NSDictionary.class]) for (NSString *key in groups) add(key,groups[key],@"Shared/AppGroup");
    if ([plugins isKindOfClass:NSArray.class]) for (id plugin in plugins) {
        @try { add([plugin valueForKey:@"bundleIdentifier"],[plugin valueForKey:@"dataContainerURL"],@"Data/PluginKitPlugin"); } @catch (NSException *exception) {}
    }
    return paths;
}
static void MobilePermissions(NSString *directory) {
    NSFileManager *fm=NSFileManager.defaultManager;
    for (NSString *p in [@[@""] arrayByAddingObjectsFromArray:[fm subpathsAtPath:directory] ?: @[]]) {
        NSString *path=[directory stringByAppendingPathComponent:p]; struct stat st;
        if (!lstat(path.fileSystemRepresentation,&st) && !S_ISLNK(st.st_mode)) {
            [fm setAttributes:@{NSFileOwnerAccountName:@"mobile",NSFileGroupOwnerAccountName:@"mobile",
                NSFilePosixPermissions:S_ISDIR(st.st_mode)?@0755:([path.lastPathComponent isEqual:@"keychain.plist"] || [path.lastPathComponent hasPrefix:@"ProjectXKeychain"])?@0600:@0644} ofItemAtPath:path error:NULL];
        }
    }
}
static NSString *KeychainDirectory(NSString *container,NSError **error) {
    NSString *path=container;
    for (NSString *part in @[@"Library",@"Preferences"]) {
        path=[path stringByAppendingPathComponent:part]; struct stat st;
        if (!lstat(path.fileSystemRepresentation,&st)) {
            if (!S_ISDIR(st.st_mode)) { if (error) *error=PXError(@"钥匙串代理目录不能是链接"); return nil; }
        } else if (errno!=ENOENT || ![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:NO attributes:@{NSFileOwnerAccountName:@"mobile",NSFileGroupOwnerAccountName:@"mobile",NSFilePosixPermissions:@0755} error:error]) return nil;
    }
    return path;
}
static NSDictionary *ReadAgentFile(NSString *container,NSString *filename) {
    int fd=open(container.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if (fd<0) return nil;
    for (NSString *part in @[@"Library",@"Preferences"]) {
        int next=openat(fd,part.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); close(fd); fd=next;
        if (fd<0) return nil;
    }
    int file=openat(fd,filename.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW); close(fd);
    if (file<0) return nil;
    struct stat st;
    if (fstat(file,&st) || !S_ISREG(st.st_mode) || st.st_size<0 || st.st_size>16*1024*1024) { close(file); return nil; }
    NSMutableData *data=[NSMutableData data]; uint8_t buffer[65536]; ssize_t size;
    while ((size=read(file,buffer,sizeof(buffer)))>0) {
        if (data.length+(NSUInteger)size>16*1024*1024) { close(file); return nil; }
        [data appendBytes:buffer length:(NSUInteger)size];
    }
    close(file); if (size<0) return nil;
    id value=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    return [value isKindOfClass:NSDictionary.class]?value:nil;
}
static NSDictionary *SnapshotKeychain(NSString *bundle,NSString *container,NSError **error) {
    NSString *directory=KeychainDirectory(container,error); if (!directory) return nil;
    NSString *identifier=NSUUID.UUID.UUIDString;
    NSString *request=[directory stringByAppendingPathComponent:@"ProjectXKeychainRequest.plist"];
    if (![@{@"id":identifier,@"operation":@"snapshot"} writeToFile:request atomically:YES]) { if (error) *error=PXError(@"无法写入钥匙串请求"); return nil; }
    [NSFileManager.defaultManager setAttributes:@{NSFileOwnerAccountName:@"mobile",NSFileGroupOwnerAccountName:@"mobile",NSFilePosixPermissions:@0600} ofItemAtPath:request error:NULL];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),(__bridge CFStringRef)[@"com.projectx.keychain.request." stringByAppendingString:bundle],NULL,NULL,YES);
    NSString *replyPath=[directory stringByAppendingPathComponent:@"ProjectXKeychainReply.plist"];
    for (NSUInteger i=0;i<100;i++) {
        struct stat st;
        if (!lstat(replyPath.fileSystemRepresentation,&st) && S_ISREG(st.st_mode) && st.st_size<16*1024*1024) {
            NSDictionary *reply=ReadAgentFile(container,@"ProjectXKeychainReply.plist");
            if ([reply[@"id"] isEqual:identifier]) {
                [NSFileManager.defaultManager removeItemAtPath:replyPath error:NULL];
                [NSFileManager.defaultManager removeItemAtPath:request error:NULL];
                if (![reply[@"ok"] boolValue] || ![reply[@"items"] isKindOfClass:NSArray.class]) { if (error) *error=PXError(reply[@"message"] ?: @"钥匙串导出失败"); return nil; }
                return @{@"format":@"ProjectX-local-passwords",@"version":@1,@"bundle":bundle,@"items":reply[@"items"]};
            }
        }
        [NSThread sleepForTimeInterval:0.05];
    }
    if (error) *error=PXError([NSString stringWithFormat:@"%@ 未响应钥匙串备份；请先打开该应用并确认插件已加载",bundle]);
    return nil;
}

@interface PXCommandService ()
@property(nonatomic,strong) ProfileManager *profiles;
@property(nonatomic,copy) NSDictionary *commandSettings;
@end
@implementation PXCommandService
+ (instancetype)sharedService { static id s; static dispatch_once_t once; dispatch_once(&once,^{s=[self new];}); return s; }
- (instancetype)init { if ((self=[super init])) _profiles=ProfileManager.sharedManager; return self; }
- (NSString *)transferDirectory:(NSString *)kind error:(NSError **)error {
    NSString *path=[[self.profiles.dataDirectory stringByAppendingPathComponent:@"Transfer"] stringByAppendingPathComponent:kind];
    if (![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755,NSFileOwnerAccountName:@"mobile",NSFileGroupOwnerAccountName:@"mobile"} error:error]) return nil;
    return path;
}
- (NSDictionary *)settings {
    if (self.commandSettings) return self.commandSettings;
    SettingManager *s=SettingManager.sharedManager; [s loadFromPrefs];
    return @{@"carrierCountryCode":s.carrierCountryCode ?: @"US",@"minVersion":s.minVersion ?: @"14.0",@"maxVersion":s.maxVersion ?: @"18.6",@"options":s.options ?: @{}};
}
- (NSArray *)rules { return [self settings][@"options"][@"preservedPaths"] ?: @[]; }
- (BOOL)snapshot:(NSArray *)bundles path:(NSString *)path error:(NSError **)error {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSMutableDictionary *keychains=[NSMutableDictionary dictionary];
    if ([[self settings][@"options"][@"backupKeychain"] boolValue]) {
        for (NSString *bundle in bundles) {
            NSString *container=Container(bundle,error); if (!container) return NO;
            NSDictionary *saved=SnapshotKeychain(bundle,container,error); if (!saved) return NO;
            keychains[bundle]=saved;
        }
    }
    for (NSString *bundle in bundles) StopApp(bundle);
    for (NSString *bundle in bundles) {
        NSString *container=Container(bundle,error); if (!container) return NO;
        StopApp(bundle);
        NSString *stage=[path stringByAppendingFormat:@"/.snapshot-%@",NSUUID.UUID.UUIDString];
        if (!PXCopyContainer(container,stage,[self rules],error)) { [fm removeItemAtPath:stage error:NULL]; return NO; }
        for (NSString *suffix in @[@"Request.plist",@"Reply.plist",@"Pending.plist",@"Status.plist"])
            [fm removeItemAtPath:[[stage stringByAppendingPathComponent:@"Library/Preferences"] stringByAppendingPathComponent:[@"ProjectXKeychain" stringByAppendingString:suffix]] error:NULL];
        if (keychains[bundle] && ![keychains[bundle] writeToFile:[stage stringByAppendingPathComponent:@"keychain.plist"] atomically:YES]) {
            if (error) *error=PXError(@"无法保存钥匙串备份"); [fm removeItemAtPath:stage error:NULL]; return NO;
        }
        if ([[self settings][@"options"][@"clearRelatedContainers"] boolValue]) {
            NSDictionary *related=RelatedContainers(bundle);
            for (NSString *key in related) if (!PXCopyRelatedContainer(related[key],[[stage stringByAppendingPathComponent:@"Related"] stringByAppendingPathComponent:key],error)) {
                [fm removeItemAtPath:stage error:NULL]; return NO;
            }
        }
        NSString *destination=[path stringByAppendingPathComponent:bundle];
        NSString *old=[destination stringByAppendingFormat:@".%@.old",NSUUID.UUID.UUIDString];
        BOOL existed=[fm fileExistsAtPath:destination];
        if (existed && ![fm moveItemAtPath:destination toPath:old error:error]) return NO;
        if (![fm moveItemAtPath:stage toPath:destination error:error]) {
            if (existed) [fm moveItemAtPath:old toPath:destination error:NULL];
            return NO;
        }
        if (existed) [fm removeItemAtPath:old error:NULL];
    }
    PhoneInfo *phone=[PhoneInfo loadFromPrefs];
    if (!phone) { if (error) *error=PXError(@"当前参数不存在"); return NO; }
    return WriteJSON(phone.toDictionary,[path stringByAppendingPathComponent:@"phoneInfo.json"],error);
}
- (BOOL)restore:(NSArray *)bundles path:(NSString *)path error:(NSError **)error {
    for (NSString *bundle in bundles) {
        NSString *container=Container(bundle,error); if (!container) return NO;
        StopApp(bundle);
        if (!PXClearContainer(container,[self rules],error)) return NO;
        NSString *saved=[path stringByAppendingPathComponent:bundle];
        if ([NSFileManager.defaultManager fileExistsAtPath:saved] && !PXCopyContainer(saved,container,[self rules],error)) return NO;
        NSString *agentDirectory=KeychainDirectory(container,error); if (!agentDirectory) return NO;
        for (NSString *suffix in @[@"Request.plist",@"Reply.plist",@"Pending.plist",@"Status.plist"])
            [NSFileManager.defaultManager removeItemAtPath:[agentDirectory stringByAppendingPathComponent:[@"ProjectXKeychain" stringByAppendingString:suffix]] error:NULL];
        if ([[self settings][@"options"][@"backupKeychain"] boolValue]) {
            NSDictionary *keychain=[NSDictionary dictionaryWithContentsOfFile:[saved stringByAppendingPathComponent:@"keychain.plist"]];
            if (keychain && (![keychain[@"format"] isEqual:@"ProjectX-local-passwords"] || ![keychain[@"bundle"] isEqual:bundle] || ![keychain[@"items"] isKindOfClass:NSArray.class])) { if (error) *error=PXError(@"钥匙串备份与目标应用不匹配"); return NO; }
            NSString *directory=KeychainDirectory(container,error); if (!directory) return NO;
            NSDictionary *pending=@{@"format":@"ProjectX-local-passwords",@"version":@1,@"id":NSUUID.UUID.UUIDString,@"items":keychain[@"items"] ?: @[]};
            if (![pending writeToFile:[directory stringByAppendingPathComponent:@"ProjectXKeychainPending.plist"] atomically:YES]) { if (error) *error=PXError(@"无法准备钥匙串恢复"); return NO; }
        }
        if ([[self settings][@"options"][@"clearRelatedContainers"] boolValue]) {
            NSDictionary *related=RelatedContainers(bundle);
            for (NSString *key in related) {
                NSString *backup=[[saved stringByAppendingPathComponent:@"Related"] stringByAppendingPathComponent:key];
                if (!PXClearRelatedContainer(related[key],error)) return NO;
                if ([NSFileManager.defaultManager fileExistsAtPath:backup] && !PXCopyRelatedContainer(backup,related[key],error)) return NO;
                MobilePermissions(related[key]);
            }
        }
        MobilePermissions(container);
    }
    return YES;
}
- (BOOL)activate:(Profile *)profile newPhone:(PhoneInfo *)phone error:(NSError **)error {
    if (!profile || profile.isDisabled) { if (error) *error=PXError(@"档案不存在或处于禁用状态"); return NO; }
    NSString *target=[self.profiles pathForProfile:profile.id];
    NSDictionary *dict=phone.toDictionary ?: ReadJSON([target stringByAppendingPathComponent:@"phoneInfo.json"],error);
    if (!PXValidatePhoneDictionary(dict,error)) return NO;
    NSArray *bundles=[[[AppScopeManager sharedManager] loadPreferences] allObjects] ?: @[];
    if (!bundles.count) { if (error) *error=PXError(@"至少选择一个应用"); return NO; }
    for (NSString *bundle in bundles) {
        NSString *saved=[target stringByAppendingPathComponent:bundle];
        if ([NSFileManager.defaultManager fileExistsAtPath:saved] && !PXValidateDirectoryTree(saved,error)) return NO;
        if ([[self settings][@"options"][@"backupKeychain"] boolValue]) {
            NSString *keychainPath=[saved stringByAppendingPathComponent:@"keychain.plist"]; struct stat st;
            if (!lstat(keychainPath.fileSystemRepresentation,&st)) {
                if (!S_ISREG(st.st_mode) || st.st_size>16*1024*1024) { if (error) *error=PXError(@"钥匙串备份文件无效或过大"); return NO; }
                NSDictionary *keychain=[NSDictionary dictionaryWithContentsOfFile:keychainPath];
                if (![keychain[@"format"] isEqual:@"ProjectX-local-passwords"] || [keychain[@"version"] integerValue]!=1 ||
                    ![keychain[@"bundle"] isEqual:bundle] || ![keychain[@"items"] isKindOfClass:NSArray.class]) {
                    if (error) *error=PXError(@"钥匙串备份与目标应用不匹配"); return NO;
                }
            }
        }
    }
    Profile *old=[self.profiles getProfileById:self.profiles.currentId];
    NSString *oldPath=[self.profiles getActiveDataPath];
    NSDictionary *oldPhone=[PhoneInfo loadFromPrefs].toDictionary;
    if (!PXValidatePhoneDictionary(oldPhone,error)) return NO;
    if (oldPath && ![self snapshot:bundles path:oldPath error:error]) return NO;
    if (![self restore:bundles path:target error:error] || ![PhoneInfo saveDictionaryToPrefs:dict] || ![self.profiles switchToProfile:profile]) {
        NSError *rollbackError=nil;
        BOOL recovered=oldPath?[self restore:bundles path:oldPath error:&rollbackError]:YES;
        if (oldPhone) [PhoneInfo saveDictionaryToPrefs:oldPhone];
        if (old) [self.profiles switchToProfile:old];
        if (error && !*error) *error=PXError(@"无法保存参数或档案索引");
        if (!recovered && error) *error=PXError([NSString stringWithFormat:@"切换失败且回滚失败：%@。原备份保留在 %@",rollbackError.localizedDescription,oldPath]);
        return NO;
    }
    BOOL clear=[self settings][@"options"][phone?@"clearPasteboardOnNewPhone":@"clearPasteboardOnSwitch"]?
        [[self settings][@"options"][phone?@"clearPasteboardOnNewPhone":@"clearPasteboardOnSwitch"] boolValue]:NO;
    if (clear) [self clearPasteboard];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("projectx.newPhoneFinish"),NULL,NULL,YES);
    return YES;
}
- (void)clearPasteboard {
    void (^clear)(void)=^{ [UIPasteboard generalPasteboard].items=@[]; };
    if (NSThread.isMainThread) clear(); else dispatch_sync(dispatch_get_main_queue(),clear);
}
- (id)perform:(NSString *)command parameters:(NSDictionary *)parameters error:(NSError **)error {
    @synchronized (self) {
        if (error) *error=nil;
        if (![command isKindOfClass:NSString.class] || ![parameters isKindOfClass:NSDictionary.class]) { if (error) *error=PXError(@"命令格式无效"); return nil; }
        BOOL ownsSettings=self.commandSettings==nil;
        if (ownsSettings) self.commandSettings=[self settings];
        @try {
        [self.profiles loadData];
        NSFileManager *fm=NSFileManager.defaultManager;
        if ([command isEqual:@"getSettings"]) return [self settings];
        if ([command isEqual:@"keychainStatus"]) {
            NSMutableDictionary *result=[NSMutableDictionary dictionary];
            for (NSString *bundle in [[AppScopeManager sharedManager] loadPreferences]) {
                NSString *container=Container(bundle,NULL); if (!container) continue;
                NSDictionary *status=ReadAgentFile(container,@"ProjectXKeychainStatus.plist") ?: @{};
                NSDictionary *safe=@{@"ok":@([status[@"ok"] isKindOfClass:NSNumber.class] && [status[@"ok"] boolValue]),@"message":[status[@"message"] isKindOfClass:NSString.class]?status[@"message"]:@"",
                    @"id":[status[@"id"] isKindOfClass:NSString.class]?status[@"id"]:@""};
                result[bundle]=@{@"pending":@(ReadAgentFile(container,@"ProjectXKeychainPending.plist")!=nil),@"status":safe};
            }
            return result;
        }
        if ([command isEqual:@"getCatalog"]) {
            NSMutableDictionary *catalog=[NSMutableDictionary dictionary];
            NSDictionary *queries=@{@"models":@"SELECT identifier AS id, generation AS title FROM KMDevices ORDER BY generation, identifier",
                @"versions":@"SELECT version AS id, version AS title FROM KMOS ORDER BY sortVersion",
                @"carriers":@"SELECT DISTINCT name AS id, name AS title FROM operator WHERE name IS NOT NULL ORDER BY name"};
            for (NSString *key in queries) catalog[key]=[[DBManager sharedManager] query:queries[key]] ?: @[];
            return catalog;
        }
        if ([command isEqual:@"saveSettings"]) {
            NSDictionary *options=PXValidateOptions(parameters[@"options"] ?: @{},error); if (!options) return nil;
            SettingManager *s=SettingManager.sharedManager;
            for (NSString *key in @[@"carrierCountryCode",@"minVersion",@"maxVersion"]) if (parameters[key] && ![parameters[key] isKindOfClass:NSString.class]) { if (error) *error=PXError(key); return nil; }
            s.options=options;
            for (NSString *key in @[@"carrierCountryCode",@"minVersion",@"maxVersion"]) if (parameters[key]) [s setValue:parameters[key] forKey:key];
            if (![s saveToPrefs]) { if (error) *error=PXError(@"设置保存失败"); return nil; }
            self.commandSettings=nil; self.commandSettings=[self settings]; return self.commandSettings;
        }
        if ([command isEqual:@"listProfiles"]) {
            NSMutableArray *rows=[NSMutableArray array]; for (Profile *p in self.profiles.mutableProfiles) [rows addObject:p.toDictionary];
            return @{@"profiles":rows,@"currentId":self.profiles.currentId ?: @""};
        }
        if ([command isEqual:@"setPhoneInfo"]) {
            NSDictionary *phone=PXValidatePhoneDictionary(parameters,error); if (!phone) return nil;
            NSDictionary *old=[PhoneInfo loadFromPrefs].toDictionary;
            if (![PhoneInfo saveDictionaryToPrefs:phone]) { if (error) *error=PXError(@"参数保存失败"); return nil; }
            NSString *active=[self.profiles getActiveDataPath];
            if (active && !WriteJSON(phone,[active stringByAppendingPathComponent:@"phoneInfo.json"],error)) { if (old) [PhoneInfo saveDictionaryToPrefs:old]; return nil; }
            return @YES;
        }
        if ([command isEqual:@"modifyIdentifier"] || [command isEqual:@"randomIDFA"]) {
            NSMutableDictionary *phone=[[PhoneInfo loadFromPrefs].toDictionary mutableCopy];
            if (!phone) { if (error) *error=PXError(@"当前参数不存在"); return nil; }
            if ([command isEqual:@"randomIDFA"]) phone[@"idfa"]=NSUUID.UUID.UUIDString;
            else {
                BOOL found=NO;
                for (NSString *key in @[@"idfa",@"idfv"]) if (parameters[key]) { phone[key]=parameters[key]; found=YES; }
                if (!found) { if (error) *error=PXError(@"请提供 idfa 或 idfv"); return nil; }
            }
            return [self perform:@"setPhoneInfo" parameters:phone error:error];
        }
        if ([command isEqual:@"setAppVersion"]) {
            NSString *bundle=parameters[@"bundleID"];
            if (!PXValidBundleIdentifier(bundle) || ![[[AppScopeManager sharedManager] loadPreferences] containsObject:bundle]) { if (error) *error=PXError(@"请选择注入范围内的应用包名"); return nil; }
            NSMutableDictionary *phone=[[PhoneInfo loadFromPrefs].toDictionary mutableCopy];
            if (!phone) { if (error) *error=PXError(@"当前参数不存在"); return nil; }
            NSMutableDictionary *runtime=[phone[@"runtime"] mutableCopy] ?: [NSMutableDictionary dictionary];
            NSMutableDictionary *apps=[runtime[@"appVersions"] mutableCopy] ?: [NSMutableDictionary dictionary];
            if ([parameters[@"restore"] boolValue]) [apps removeObjectForKey:bundle];
            else {
                NSMutableDictionary *version=[apps[bundle] mutableCopy] ?: [NSMutableDictionary dictionary];
                for (NSString *key in @[@"version",@"build"]) if (parameters[key]) version[key]=parameters[key];
                if (!version.count) { if (error) *error=PXError(@"请提供 version 或 build"); return nil; }
                apps[bundle]=version;
            }
            runtime[@"appVersions"]=apps; phone[@"runtime"]=runtime;
            return [self perform:@"setPhoneInfo" parameters:phone error:error];
        }
        if ([command isEqual:@"renameProfile"]) {
            NSString *identifier=parameters[@"id"] ?: self.profiles.currentId;
            if (![identifier isKindOfClass:NSString.class] || ![self.profiles renameProfile:identifier to:parameters[@"name"]]) { if (error) *error=PXError(@"重命名失败"); return nil; }
            return @YES;
        }
        if ([command isEqual:@"deleteInactiveProfiles"]) {
            NSMutableArray *ids=[NSMutableArray array];
            for (Profile *p in self.profiles.mutableProfiles) if (![self.profiles isCurrent:p] && ![p.id isEqual:@"0"]) [ids addObject:p.id];
            return ids.count?[self perform:@"deleteProfiles" parameters:@{@"ids":ids} error:error]:@{@"deleted":@[]};
        }
        if ([command isEqual:@"deleteProfileByName"] || [command isEqual:@"disableProfileByName"]) {
            NSString *name=parameters[@"name"]; Profile *match=nil;
            if ([name isKindOfClass:NSString.class]) for (Profile *p in self.profiles.mutableProfiles) if ([p.name isEqual:name]) {
                if (match) { if (error) *error=PXError(@"同名档案不唯一"); return nil; } match=p;
            }
            if (!match) { if (error) *error=PXError(@"档案不存在"); return nil; }
            return [command isEqual:@"deleteProfileByName"]?[self perform:@"deleteProfiles" parameters:@{@"ids":@[match.id]} error:error]:
                [self perform:@"disableProfile" parameters:@{@"id":match.id,@"hours":parameters[@"hours"] ?: @0} error:error];
        }
        if ([command isEqual:@"newPhone"]) {
            for (NSString *key in @[@"version",@"model"]) if (parameters[key] && (![parameters[key] isKindOfClass:NSString.class] || [parameters[key] length]>128)) { if (error) *error=PXError(key); return nil; }
            PhoneInfo *phone=[[DataGenManager sharedManager] generatePhoneInfoWithVersion:parameters[@"version"] model:parameters[@"model"]];
            if (!phone) { if (error) *error=PXError(@"机型、系统及 RAM 筛选没有匹配数据，请调整设置"); return nil; }
            // Generate and validate everything before touching a running app.
            if (!PXValidatePhoneDictionary(phone.toDictionary,error)) return nil;
            NSString *endpoint=[self settings][@"options"][@"idfaEndpoint"];
            if (endpoint.length) {
                id result=[self perform:@"fetchIDFA" parameters:@{} error:error];
                if (!result && ![[self settings][@"options"][@"fallbackRandomIDFA"] boolValue]) return nil;
                if (result) phone.idfa=result;
                else if (error) *error=nil;
            }
            Profile *previous=[self.profiles getProfileById:self.profiles.currentId];
            if (!previous) { // An initial checkpoint is needed for rollback and the existing app data.
                NSString *checkpoint=[self.profiles genBackupDirectory];
                if (!checkpoint) { if (error) *error=PXError(@"无法创建原始档案"); return nil; }
                previous=[self.profiles getProfileById:self.profiles.currentId];
            }
            NSString *path=[self.profiles genInactiveBackupDirectory]; if (!path) { if (error) *error=PXError(@"无法创建档案"); return nil; }
            Profile *created=[self.profiles getProfileById:path.lastPathComponent];
            BOOL ok=WriteJSON(phone.toDictionary,[path stringByAppendingPathComponent:@"phoneInfo.json"],error) && [self activate:created newPhone:phone error:error];
            if (!ok) {
                if (previous) [self.profiles switchToProfile:previous];
                if ([self.profiles remove:created]) [fm removeItemAtPath:path error:NULL]; return nil;
            }
            MobilePermissions(path); return created.toDictionary;
        }
        if ([command isEqual:@"updateParameters"]) {
            for (NSString *key in @[@"model",@"OSVersion"]) if (parameters[key] && (![parameters[key] isKindOfClass:NSString.class] || [parameters[key] length]>128)) { if (error) *error=PXError(key); return nil; }
            PhoneInfo *current=[PhoneInfo loadFromPrefs];
            if (!current) { if (error) *error=PXError(@"当前参数不存在"); return nil; }
            PhoneInfo *generated=[[DataGenManager sharedManager] generatePhoneInfoWithVersion:[parameters[@"OSVersion"] length]?parameters[@"OSVersion"]:current.iosVersion.version model:[parameters[@"model"] length]?parameters[@"model"]:current.deviceModel.modelName];
            if (!generated) { if (error) *error=PXError(@"机型和系统组合没有匹配数据"); return nil; }
            NSMutableDictionary *updated=[current.toDictionary mutableCopy]; NSDictionary *candidate=generated.toDictionary;
            for (NSString *key in @[@"iosVersion",@"deviceModel",@"storageInfo"]) updated[key]=candidate[key];
            return [self perform:@"setPhoneInfo" parameters:updated error:error];
        }
        if ([command isEqual:@"fetchIDFA"]) {
            NSString *endpoint=[self settings][@"options"][@"idfaEndpoint"];
            if (!endpoint.length) { if (error) *error=PXError(@"请先配置 IDFA HTTPS 服务地址"); return nil; }
            NSURLRequest *request=[NSURLRequest requestWithURL:[NSURL URLWithString:endpoint] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
            dispatch_semaphore_t semaphore=dispatch_semaphore_create(0);
            __block NSString *identifier=nil; __block NSError *failure=nil;
            NSURLSessionDataTask *task=[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *networkError) {
                failure=networkError;
                if (!failure && [(NSHTTPURLResponse *)response statusCode]==200 && data.length<65536) {
                    id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                    id value=[json isKindOfClass:NSDictionary.class]?json[@"idfa"]:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if ([value isKindOfClass:NSString.class]) identifier=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    if (![[NSUUID alloc] initWithUUIDString:identifier ?: @""]) identifier=nil;
                }
                dispatch_semaphore_signal(semaphore);
            }];
            [task resume];
            if (dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC))) {
                [task cancel]; if (error) *error=PXError(@"IDFA 服务超时"); return nil;
            }
            if (!identifier) { if (error) *error=failure ?: PXError(@"IDFA 服务未返回有效 UUID"); return nil; }
            return identifier;
        }
        if ([@[@"switchProfile",@"navigateProfile"] containsObject:command]) {
            Profile *profile=nil;
            if ([command isEqual:@"navigateProfile"]) {
                NSString *operation=parameters[@"operation"];
                if (![operation isKindOfClass:NSString.class]) { if (error) *error=PXError(@"顺序切换命令无效"); return nil; }
                profile=[self.profiles navigationTarget:operation wrap:![[self settings][@"options"][@"stopAtLastProfile"] boolValue]];
            } else if ([parameters[@"id"] isKindOfClass:NSString.class]) profile=[self.profiles getProfileById:parameters[@"id"]];
            else if ([parameters[@"name"] isKindOfClass:NSString.class]) {
                for (Profile *p in self.profiles.mutableProfiles) if ([p.name isEqual:parameters[@"name"]]) {
                    if (profile) { if (error) *error=PXError(@"同名档案不唯一，请使用 ID"); return nil; } profile=p;
                }
            }
            if ([self.profiles isCurrent:profile]) return profile.toDictionary;
            if (![self activate:profile newPhone:nil error:error]) return nil;
            return profile.toDictionary;
        }
        if ([command isEqual:@"disableProfile"]) {
            NSNumber *hours=parameters[@"hours"];
            if (![hours isKindOfClass:NSNumber.class] || !isfinite(hours.doubleValue) || hours.doubleValue<0 || hours.doubleValue>876000 ||
                ![parameters[@"id"] isKindOfClass:NSString.class] ||
                ![self.profiles setDisabledUntil:hours.doubleValue?[NSDate dateWithTimeIntervalSinceNow:hours.doubleValue*3600]:nil forProfile:parameters[@"id"]]) {
                if (error) *error=PXError(@"禁用时间无效或档案不可禁用"); return nil;
            }
            return @YES;
        }
        if ([command isEqual:@"reorderProfile"]) {
            NSNumber *index=parameters[@"index"];
            if (![index isKindOfClass:NSNumber.class] || index.doubleValue!=index.integerValue || index.integerValue<0 ||
                ![parameters[@"id"] isKindOfClass:NSString.class] || ![self.profiles moveProfile:parameters[@"id"] toIndex:index.unsignedIntegerValue]) {
                if (error) *error=PXError(@"排序失败"); return nil;
            } return @YES;
        }
        if ([command isEqual:@"deleteProfiles"]) {
            NSArray *ids=parameters[@"ids"];
            if (![ids isKindOfClass:NSArray.class] || !ids.count) { if (error) *error=PXError(@"请选择档案"); return nil; }
            NSMutableArray *deleted=[NSMutableArray array];
            NSMutableDictionary *moved=[NSMutableDictionary dictionary];
            NSString *trash=[self.profiles.dataDirectory stringByAppendingFormat:@"/.trash-%@",NSUUID.UUID.UUIDString];
            for (id identifier in ids) {
                if (![identifier isKindOfClass:NSString.class]) { if (error) *error=PXError(@"档案 ID 无效"); return nil; }
                Profile *p=[self.profiles getProfileById:identifier];
                if (!p || [self.profiles isCurrent:p] || [p.id isEqual:@"0"]) continue;
                if (![deleted containsObject:identifier]) [deleted addObject:identifier];
            }
            if (![fm createDirectoryAtPath:trash withIntermediateDirectories:NO attributes:nil error:error]) return nil;
            BOOL ok=YES;
            for (NSString *identifier in deleted) {
                NSString *path=[self.profiles pathForProfile:identifier];
                NSString *destination=[trash stringByAppendingPathComponent:identifier];
                if ([fm fileExistsAtPath:path]) {
                    if (![fm moveItemAtPath:path toPath:destination error:error]) { ok=NO; break; }
                    moved[path]=destination;
                }
            }
            if (ok) ok=[self.profiles removeProfilesWithIDs:deleted];
            if (!ok) {
                BOOL restored=YES;
                for (NSString *path in moved) if (![fm moveItemAtPath:moved[path] toPath:path error:NULL]) restored=NO;
                if (restored) [fm removeItemAtPath:trash error:NULL];
                if (!restored && error) *error=PXError([NSString stringWithFormat:@"删除失败，部分目录未能回滚；原数据保留在 %@",trash]);
                else if (error && !*error) *error=PXError(@"删除失败，已回滚档案索引与目录"); return nil;
            }
            BOOL cleaned=[fm removeItemAtPath:trash error:NULL];
            return @{ @"deleted":deleted,@"cleanupPending":@(!cleaned) };
        }
        if ([command isEqual:@"clearPasteboard"]) { [self clearPasteboard]; return @YES; }
        if ([command isEqual:@"clearSystemResidues"]) {
            NSMutableArray *removed=[NSMutableArray array];
            for (NSString *bundle in [[AppScopeManager sharedManager] loadPreferences]) {
                if (!PXValidBundleIdentifier(bundle) || [bundle hasPrefix:@"com.apple."]) continue;
                StopApp(bundle);
                for (NSString *template in @[@"/var/mobile/Library/Preferences/%@.plist",@"/var/mobile/Library/Caches/%@",@"/var/mobile/Library/Cookies/%@.binarycookies",@"/var/mobile/Library/HTTPStorages/%@",@"/var/mobile/Library/WebKit/%@"]) {
                    NSString *path=[NSString stringWithFormat:template,bundle];
                    struct stat st;
                    if (!lstat(path.fileSystemRepresentation,&st)) {
                        if (![fm removeItemAtPath:path error:error]) return nil;
                        [removed addObject:path];
                    }
                }
            }
            return @{ @"removed":removed };
        }
        if ([command isEqual:@"clearSafari"]) {
            NSString *path=Container(@"com.apple.mobilesafari",error); if (!path) return nil;
            StopApp(@"com.apple.mobilesafari");
            if (!PXClearContainer(path,@[],error)) return nil;
            NSString *extra=@"/var/mobile/Library/Safari";
            if ([fm fileExistsAtPath:extra] && ![fm removeItemAtPath:extra error:error]) return nil;
            MobilePermissions(path); return @YES;
        }
        if ([command isEqual:@"exportParameters"]) {
            NSString *folder=[self transferDirectory:@"Exports" error:error]; if (!folder) return nil;
            NSString *path=[folder stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"json"]];
            NSDictionary *phone=[PhoneInfo loadFromPrefs].toDictionary;
            if (!PXValidatePhoneDictionary(phone,error) || !WriteJSON(phone,path,error)) return nil;
            MobilePermissions(folder); return @{ @"path":path };
        }
        if ([@[@"importParameters",@"importProfiles"] containsObject:command]) {
            NSString *filename=parameters[@"filename"];
            if (![filename isKindOfClass:NSString.class] || !filename.length || ![filename isEqual:filename.lastPathComponent] || [filename containsString:@".."] || [filename containsString:@"\\"]) {
                if (error) *error=PXError(@"导入文件名无效"); return nil;
            }
            NSString *folder=[self transferDirectory:@"Imports" error:error]; if (!folder) return nil;
            NSString *path=[folder stringByAppendingPathComponent:filename]; struct stat st;
            if (lstat(path.fileSystemRepresentation,&st) || !S_ISREG(st.st_mode)) { if (error) *error=PXError(@"导入文件不存在或为链接"); return nil; }
            if ([command isEqual:@"importParameters"]) {
                NSDictionary *phone=PXValidatePhoneDictionary(ReadJSON(path,error),error); if (!phone) return nil;
                NSString *active=[self.profiles getActiveDataPath];
                if (!active) { if (error) *error=PXError(@"请先创建档案"); return nil; }
                NSDictionary *old=[PhoneInfo loadFromPrefs].toDictionary;
                if (![PhoneInfo saveDictionaryToPrefs:phone]) { if (error) *error=PXError(@"参数保存失败"); return nil; }
                if (!WriteJSON(phone,[active stringByAppendingPathComponent:@"phoneInfo.json"],error)) { if (old) [PhoneInfo saveDictionaryToPrefs:old]; return nil; }
                return @YES;
            }
            NSString *stage=[folder stringByAppendingFormat:@"/.stage-%@",NSUUID.UUID.UUIDString];
            if (!PXExtractArchive(path,stage,error)) return nil;
            NSDictionary *manifest=ReadJSON([stage stringByAppendingPathComponent:@"manifest.json"],error);
            NSMutableArray *imported=[NSMutableArray array]; BOOL ok=YES;
            if (![manifest isKindOfClass:NSDictionary.class] || ![manifest[@"format"] isEqual:@"ProjectX-backup"] ||
                [manifest[@"version"] integerValue]!=1 || ![manifest[@"profiles"] isKindOfClass:NSArray.class] || ![manifest[@"profiles"] count]) {
                if (error) *error=PXError(@"备份清单无效或版本不支持"); ok=NO;
            }
            if (ok) for (id row in manifest[@"profiles"]) {
                Profile *original=[Profile fromDictionary:row];
                if (!original) { if (error) *error=PXError(@"备份档案信息无效"); ok=NO; break; }
                Profile *p=[self.profiles importProfileDirectory:[[stage stringByAppendingPathComponent:@"profiles"] stringByAppendingPathComponent:original.id] name:original.name error:error];
                if (!p) { ok=NO; break; }
                [imported addObject:p];
            }
            if (!ok) for (Profile *p in imported) { NSString *saved=[self.profiles pathForProfile:p.id]; if ([self.profiles remove:p]) [fm removeItemAtPath:saved error:NULL]; }
            [fm removeItemAtPath:stage error:NULL];
            if (!ok) return nil;
            MobilePermissions(self.profiles.dataDirectory);
            NSMutableArray *rows=[NSMutableArray array]; for (Profile *p in imported) [rows addObject:p.toDictionary]; return rows;
        }
        if ([command isEqual:@"exportProfiles"]) {
            NSArray *ids=parameters[@"ids"];
            if (![ids isKindOfClass:NSArray.class] || !ids.count) { if (error) *error=PXError(@"请选择档案"); return nil; }
            NSString *folder=[self transferDirectory:@"Exports" error:error]; if (!folder) return nil;
            NSString *stage=[folder stringByAppendingFormat:@"/.stage-%@",NSUUID.UUID.UUIDString];
            NSString *profileRoot=[stage stringByAppendingPathComponent:@"profiles"];
            if (![fm createDirectoryAtPath:profileRoot withIntermediateDirectories:YES attributes:nil error:error]) return nil;
            NSMutableArray *rows=[NSMutableArray array]; BOOL ok=YES;
            for (id identifier in ids) {
                Profile *p=[identifier isKindOfClass:NSString.class]?[self.profiles getProfileById:identifier]:nil;
                if (!p) { if (error) *error=PXError(@"档案不存在"); ok=NO; break; }
                NSString *saved=[self.profiles pathForProfile:identifier];
                if ([self.profiles isCurrent:p] && ![self snapshot:[[[AppScopeManager sharedManager] loadPreferences] allObjects] path:saved error:error]) { ok=NO; break; }
                NSDictionary *phone=ReadJSON([saved stringByAppendingPathComponent:@"phoneInfo.json"],error);
                if (!PXValidatePhoneDictionary(phone,error) || ![fm copyItemAtPath:saved toPath:[profileRoot stringByAppendingPathComponent:identifier] error:error]) { ok=NO; break; }
                [rows addObject:p.toDictionary];
            }
            NSString *archive=[folder stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"zip"]];
            ok=ok && WriteJSON(@{@"format":@"ProjectX-backup",@"version":@1,@"profiles":rows},[stage stringByAppendingPathComponent:@"manifest.json"],error) && PXCreateArchive(stage,archive,error);
            [fm removeItemAtPath:stage error:NULL];
            if (!ok) return nil;
            MobilePermissions(folder); return @{ @"path":archive };
        }
        if (error) *error=PXError(@"不支持的命令");
        return nil;
        } @finally { if (ownsSettings) self.commandSettings=nil; }
    }
}
@end
