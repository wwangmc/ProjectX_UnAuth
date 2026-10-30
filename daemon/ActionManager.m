#import "ActionManager.h"
#import "AppScopeManager.h"
#import "PhoneInfo.h"
#import "ProfileManager.h"
#import "DataGenManager.h"
#import "SysExecutor.h"
#import <sqlite3.h>

@interface ActionManager()
    @property(nonatomic, strong) ProfileManager *profileManager;
@end
@implementation ActionManager

+ (instancetype)sharedManager {
    static ActionManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}
- (instancetype) init{
    self = [super init];
    _profileManager = [ProfileManager sharedManager];
    return self;
}
- (void) newPhone{
    // // 加载所有被选中应用
    NSMutableSet * loadApps = [[AppScopeManager sharedManager] loadPreferences];
    // 获取当前生效备份
    NSString * activeBackupPath = [_profileManager getActiveDataPath];
    if(!activeBackupPath){
        // 首次新机
        activeBackupPath = [_profileManager genBackupDirectory];
        if (!activeBackupPath) return;
        
    }
    // 创建备份存放目录
    NSString * backupPath = [_profileManager genBackupDirectory];
    if(!backupPath){
        NSLog(@"create Backup directory error");
        return;
    }
    for (NSString * bundleId in loadApps){
        // 强制关停应用
        [self killApp:bundleId];
         // 判断应用中是否存在 safari 额外清理 /var/mobile/Library/Safari 
        if([bundleId isEqualToString:@"com.apple.mobilesafari"]){
            [self delFile:@"/var/mobile/Library/Safari"];
        }
        // 清理 prefernce /private/var/mobile/Library/Preferences   
        [self delFile:[NSString stringWithFormat:@"/private/var/mobile/Library/Preferences/%@.plist",bundleId]];
       
        // 清理or备份沙盒数据到activeBackUp中
        [self backupFileToPath:bundleId toPath:activeBackupPath];
    }
    // 清理keychain内容
    [self clearKeyChain];
    // 保存旧参数
    PhoneInfo * phoneInfo = [PhoneInfo loadFromPrefs];
    [PhoneInfo saveDictionaryToFile:[phoneInfo toDictionary] toFile:[activeBackupPath stringByAppendingPathComponent:@"phoneInfo.json"]];
    // 生成新参数
    PhoneInfo * newPhoneInfo = [[DataGenManager sharedManager] generatePhoneInfo];
    [PhoneInfo saveDictionaryToFile:[newPhoneInfo toDictionary] toFile:[backupPath stringByAppendingPathComponent:@"phoneInfo.json"]];
    [newPhoneInfo saveToPrefs];
    // 通知页面刷新显示
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, CFSTR("projectx.newPhoneFinish"), NULL, NULL, YES);

}

-(void) switchBackup:(NSString *) id{
    Profile *profile = [_profileManager getProfileById:id];
    // 不存在该备份直接返回
    if(!profile || [[ProfileManager sharedManager]isCurrent:profile]) return;
    // 加载所有被选中应用
    NSMutableSet * loadApps = [[AppScopeManager sharedManager] loadPreferences];
    // 获取当前生效备份
    NSString * activeBackupPath = [_profileManager getActiveDataPath];
    if (![_profileManager switchToProfile:profile]) return;
    NSString * waitActiveBackupPath = [_profileManager getActiveDataPath];

    for (NSString * bundleId in loadApps){
        // 强制关停应用
        [self killApp:bundleId];
       
        // 清理or备份沙盒数据到activeBackUp中
        [self backupFileToPath:bundleId toPath:activeBackupPath];

        [self restoreBackupFromPath:waitActiveBackupPath toBundle:bundleId];
    }
    
    [self clearKeyChain];

    // 加载备份下PhoneInfo
    NSDictionary * phoneInfo = [PhoneInfo loadDictionaryFromFile:[waitActiveBackupPath stringByAppendingPathComponent:@"phoneInfo.json"]];
    [PhoneInfo saveDictionaryToPrefs:phoneInfo];
    // Also post a Darwin notification for the floating indicator
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, 
                                            CFSTR("com.hydra.projectx.profileChanged"), 
                                            NULL, 
                                            NULL, 
                                            YES);
                
}

- (void) clearKeyChain{
	sqlite3 *database;
	int openResult = sqlite3_open("/private/var/Keychains/keychain-2.db", &database);
	if (openResult == SQLITE_OK)
	{
		sqlite3_exec(database, "DELETE FROM genp WHERE agrp <> 'apple';", NULL, NULL, NULL);

		sqlite3_exec(database, "DELETE FROM cert WHERE agrp <> 'lockdown-identities';", NULL, NULL, NULL);

		sqlite3_exec(database, "DELETE FROM keys WHERE agrp <> 'lockdown-identities';", NULL, NULL, NULL);

		sqlite3_exec(database, "DELETE FROM inet;", NULL, NULL, NULL);

		sqlite3_exec(database, "DELETE FROM sqlite_sequence;", NULL, NULL, NULL);
		
        sqlite3_exec(database, "VACUUM;", NULL, NULL, NULL);
		
        sqlite3_close(database);
	}
}
- (void) killApp:(NSString *) bundleId{
    LSApplicationProxy* appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleId];
    
    runCommand([NSString stringWithFormat:@"killall -9 %@",appProxy.bundleExecutable]);
}
-(NSString *) getAppDataPath:(NSString *) bundleId{
    LSApplicationProxy* appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleId];
    return [appProxy valueForKeyPath:@"dataContainerURL.path"] ?: @"";
}
- (void)backupFileToPath:(NSString *)bundleId toPath:(NSString *)path {
    NSString *appDataPath = [self getAppDataPath:bundleId];
    NSString *savePath = [path stringByAppendingPathComponent:bundleId];

    NSFileManager *fm = [NSFileManager defaultManager];
    if(![fm fileExistsAtPath:savePath]){
        NSDictionary *attributes = @{
            NSFilePosixPermissions: @0755,
            NSFileOwnerAccountName: @"mobile",
            NSFileGroupOwnerAccountName: @"mobile"
        };
        
        [fm createDirectoryAtPath:savePath
               withIntermediateDirectories:YES
                                attributes:attributes
                                     error:nil];
    }
    NSArray *folders = @[@"Documents", @"tmp", @"Library", @"SystemData"];

    //
    // 1️⃣ 先把整个目录直接移动到备份目录
    //
    for (NSString *folder in folders) {
        NSString *src = [appDataPath stringByAppendingPathComponent:folder];
        NSString *dst = [savePath stringByAppendingPathComponent:folder];

        if (![fm fileExistsAtPath:src]) continue;
        [self delFile:dst];

        NSError *moveErr = nil;
        if (![fm moveItemAtPath:src toPath:dst error:&moveErr]) {
            NSLog(@"[ERROR] move %@ -> %@ failed: %@", src, dst, moveErr);
        }
    }

    //
    // 2️⃣ 重新创建必须存在的目录
    //
    NSArray *recreate = @[
        @"Documents",
        @"tmp",
        @"Library",
        @"SystemData",
        @"Library/Caches",
        @"Library/Preferences"
    ];

    for (NSString *folder in recreate) {
        NSString *dst = [appDataPath stringByAppendingPathComponent:folder];

        [fm createDirectoryAtPath:dst
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

        // 设置权限 + 属主
        [self applyMobile755Recursive:dst];
    }
}
- (void)restoreBackupFromPath:(NSString *)backupPath toBundle:(NSString *)bundleId {
    NSString *appDataPath = [self getAppDataPath:bundleId];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *savePath = [backupPath stringByAppendingPathComponent:bundleId];

    NSArray *folders = @[@"Documents", @"tmp", @"Library", @"SystemData"];

    //
    // 1️⃣ 逐个把备份目录拷贝回去（整个目录）
    //
    for (NSString *folder in folders) {
        NSString *src = [savePath stringByAppendingPathComponent:folder];
        NSString *dst = [appDataPath stringByAppendingPathComponent:folder];

        BOOL isDir = NO;
        if (![fm fileExistsAtPath:src isDirectory:&isDir] || !isDir) {
            continue;   // 备份中没有该目录就跳过
        }

        // 目标存在，先删除
        [self delFile:dst];

        NSError *copyErr = nil;
        if (![fm copyItemAtPath:src toPath:dst error:&copyErr]) {
            NSLog(@"[ERROR] copy %@ -> %@ failed: %@", src, dst, copyErr);
        } else {
            NSLog(@"[DEBUG] Restored %@ -> %@", src, dst);
        }

        // 统一权限（递归）
        [self applyMobile755Recursive:dst];
    }

    //
    // 2️⃣ 确保关键目录存在（有些应用启动必须要有）
    //
    NSArray *mustExist = @[
        @"Documents",
        @"tmp",
        @"Library",
        @"SystemData",
        @"Library/Caches",
        @"Library/Preferences"
    ];

    for (NSString *folder in mustExist) {
        NSString *dst = [appDataPath stringByAppendingPathComponent:folder];

        if (![fm fileExistsAtPath:dst]) {
            [fm createDirectoryAtPath:dst
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
        }

        [self applyMobile755Recursive:dst];
    }
}

- (void)applyMobile755Recursive:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSDictionary *attrs = @{
        NSFilePosixPermissions: @(0755),
        NSFileOwnerAccountName: @"mobile",
        NSFileGroupOwnerAccountName: @"mobile"
    };

    [fm setAttributes:attrs ofItemAtPath:path error:nil];

    NSArray *contents = [fm subpathsAtPath:path];
    for (NSString *sub in contents) {
        NSString *full = [path stringByAppendingPathComponent:sub];
        [fm setAttributes:attrs ofItemAtPath:full error:nil];
    }
}


-(void) delFile:(NSString *) path{
    NSFileManager *fm = [NSFileManager defaultManager];
    // 判断文件是否存在 存在就删除
    if([fm fileExistsAtPath:path]){
        NSString *res = runCommand([NSString stringWithFormat:@"rm -rf %@",path]);
        NSLog(@"delFile res:%@",res);
    }
}

-(void) removeBackup:(NSString *)id{
    if([_profileManager removeProfileById:id]){
        NSString * removePath = [NSString stringWithFormat:@"/private/var/mobile/Media/ProjectX/%@", id];
        [self delFile:removePath];
    }
}

@end
