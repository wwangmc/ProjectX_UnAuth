#import "PXHookSupport.h"
#import <Security/Security.h>
#import <dlfcn.h>
#import <sys/stat.h>

// Runs inside each selected app, using that app's own keychain entitlements.
// Only local password items are transferred; Secure Enclave keys and iCloud items
// are deliberately never deleted through a database-wide SQL operation.
static NSString *AgentFile(NSString *name) {
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"] stringByAppendingPathComponent:[@"ProjectXKeychain" stringByAppendingString:name]];
}
static NSArray *AccessGroups(void) {
    CFTypeRef (*create)(CFAllocatorRef)=dlsym(RTLD_DEFAULT,"SecTaskCreateFromSelf");
    CFTypeRef (*copyValue)(CFTypeRef,CFStringRef,CFErrorRef *)=dlsym(RTLD_DEFAULT,"SecTaskCopyValueForEntitlement");
    if (!create || !copyValue) return nil;
    CFTypeRef task=create(kCFAllocatorDefault); if (!task) return nil;
    CFTypeRef value=copyValue(task,CFSTR("keychain-access-groups"),NULL); CFRelease(task);
    id groups=CFBridgingRelease(value); NSMutableArray *result=[NSMutableArray array];
    if ([groups isKindOfClass:NSArray.class]) for (id group in groups) {
        if ([group isKindOfClass:NSString.class] && [group length] && ![group containsString:@"*"] &&
            ![group hasPrefix:@"com.apple."] && ![group isEqual:@"apple"] && ![group containsString:@"/"]) [result addObject:group];
    }
    return result;
}
static NSDictionary *Query(NSString *group,CFTypeRef itemClass) {
    return @{(__bridge id)kSecClass:(__bridge id)itemClass,(__bridge id)kSecAttrAccessGroup:group,
             (__bridge id)kSecAttrSynchronizable:@NO};
}
static NSArray *Snapshot(NSError **error) {
    NSArray *groups=AccessGroups(); if (!groups.count) { if (error) *error=[NSError errorWithDomain:@"ProjectX.Keychain" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"无法读取目标应用的钥匙串访问组"}]; return nil; }
    NSMutableArray *items=[NSMutableArray array];
    NSArray *classes=@[(__bridge id)kSecClassGenericPassword,(__bridge id)kSecClassInternetPassword];
    NSArray *attributes=@[(__bridge id)kSecAttrAccessGroup,(__bridge id)kSecAttrAccount,(__bridge id)kSecAttrService,
        (__bridge id)kSecAttrServer,(__bridge id)kSecAttrSecurityDomain,(__bridge id)kSecAttrProtocol,
        (__bridge id)kSecAttrAuthenticationType,(__bridge id)kSecAttrPort,(__bridge id)kSecAttrPath,
        (__bridge id)kSecAttrLabel,(__bridge id)kSecAttrDescription,(__bridge id)kSecAttrComment,
        (__bridge id)kSecAttrGeneric,(__bridge id)kSecAttrAccessible,(__bridge id)kSecValueData];
    for (NSString *group in groups) for (id itemClass in classes) {
        NSMutableDictionary *query=[Query(group,(__bridge CFTypeRef)itemClass) mutableCopy];
        query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitAll;
        query[(__bridge id)kSecReturnAttributes]=@YES; query[(__bridge id)kSecReturnData]=@YES;
        query[(__bridge id)kSecUseAuthenticationUI]=(__bridge id)kSecUseAuthenticationUIFail;
        CFTypeRef result=NULL; OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&result);
        id rows=CFBridgingRelease(result);
        if (status==errSecItemNotFound) continue;
        if (status!=errSecSuccess) { if (error) *error=[NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]; return nil; }
        if ([rows isKindOfClass:NSDictionary.class]) rows=@[rows];
        if (![rows isKindOfClass:NSArray.class]) return nil;
        for (NSDictionary *row in rows) {
            if (![row[(__bridge id)kSecValueData] isKindOfClass:NSData.class]) { if (error) *error=[NSError errorWithDomain:@"ProjectX.Keychain" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"受保护的钥匙串项目不能导出"}]; return nil; }
            NSMutableDictionary *item=[NSMutableDictionary dictionary];
            for (id key in attributes) if (row[key]) item[key]=row[key];
            item[(__bridge id)kSecClass]=itemClass; item[(__bridge id)kSecAttrAccessGroup]=group;
            item[(__bridge id)kSecAttrSynchronizable]=@NO;
            [items addObject:item];
        }
    }
    return items;
}
static BOOL Apply(NSArray *items,NSError **error) {
    NSArray *groups=AccessGroups(); NSArray *classes=@[(__bridge id)kSecClassGenericPassword,(__bridge id)kSecClassInternetPassword];
    if (!groups.count || ![items isKindOfClass:NSArray.class]) return NO;
    NSSet *allowed=[NSSet setWithArray:@[(__bridge id)kSecClass,(__bridge id)kSecAttrAccessGroup,(__bridge id)kSecAttrAccount,(__bridge id)kSecAttrService,
        (__bridge id)kSecAttrServer,(__bridge id)kSecAttrSecurityDomain,(__bridge id)kSecAttrProtocol,(__bridge id)kSecAttrAuthenticationType,
        (__bridge id)kSecAttrPort,(__bridge id)kSecAttrPath,(__bridge id)kSecAttrLabel,(__bridge id)kSecAttrDescription,
        (__bridge id)kSecAttrComment,(__bridge id)kSecAttrGeneric,(__bridge id)kSecAttrAccessible,(__bridge id)kSecValueData,(__bridge id)kSecAttrSynchronizable]];
    for (id item in items) {
        if (![item isKindOfClass:NSDictionary.class] || ![groups containsObject:item[(__bridge id)kSecAttrAccessGroup]] ||
            ![classes containsObject:item[(__bridge id)kSecClass]] || ![item[(__bridge id)kSecValueData] isKindOfClass:NSData.class] ||
            [item[(__bridge id)kSecAttrSynchronizable] boolValue]) return NO;
        for (id key in item) if (![allowed containsObject:key]) return NO;
    }
    for (NSString *group in groups) for (id itemClass in classes) {
        OSStatus status=SecItemDelete((__bridge CFDictionaryRef)Query(group,(__bridge CFTypeRef)itemClass));
        if (status!=errSecSuccess && status!=errSecItemNotFound) { if (error) *error=[NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]; return NO; }
    }
    for (NSDictionary *item in items) {
        OSStatus status=SecItemAdd((__bridge CFDictionaryRef)item,NULL);
        if (status!=errSecSuccess) { if (error) *error=[NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]; return NO; }
    }
    return YES;
}
static void AgentWrite(NSDictionary *value,NSString *suffix) {
    NSString *path=AgentFile(suffix); [value writeToFile:path atomically:YES]; chmod(path.fileSystemRepresentation,0600);
}
static void RestorePending(void) {
    NSDictionary *pending=[NSDictionary dictionaryWithContentsOfFile:AgentFile(@"Pending.plist")];
    if (![pending[@"format"] isEqual:@"ProjectX-local-passwords"] || [pending[@"version"] integerValue]!=1) return;
    NSError *error=nil; NSArray *previous=Snapshot(&error);
    BOOL ok=previous && Apply(pending[@"items"],&error);
    if (!ok && previous) { NSError *rollback=nil; if (!Apply(previous,&rollback)) error=rollback ?: error; }
    AgentWrite(@{@"ok":@(ok),@"message":error.localizedDescription ?: @"",@"id":pending[@"id"] ?: @""},@"Status.plist");
    if (ok) [NSFileManager.defaultManager removeItemAtPath:AgentFile(@"Pending.plist") error:NULL];
}
static void AgentRequest(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef userInfo) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("com.projectx.keychain",DISPATCH_QUEUE_SERIAL);});
    dispatch_async(queue,^{
        NSDictionary *request=[NSDictionary dictionaryWithContentsOfFile:AgentFile(@"Request.plist")];
        if (![request[@"operation"] isEqual:@"snapshot"] || ![request[@"id"] isKindOfClass:NSString.class]) return;
        NSError *error=nil; NSArray *items=Snapshot(&error);
        AgentWrite(@{@"id":request[@"id"],@"ok":@(items!=nil),@"items":items ?: @[],@"message":error.localizedDescription ?: @"无法导出钥匙串"},@"Reply.plist");
    });
}
__attribute__((constructor)) static void InstallKeychainAgent(void) {
    if (!PXScopedPhone()) return;
    RestorePending();
    NSString *notification=[@"com.projectx.keychain.request." stringByAppendingString:NSBundle.mainBundle.bundleIdentifier];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,AgentRequest,
        (__bridge CFStringRef)notification,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
}
