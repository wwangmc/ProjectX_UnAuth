#import <Foundation/Foundation.h>
#import "PXConfiguration.h"
#import "PXArchive.h"
#import "PXContainerFiles.h"
#import "PXURLCommand.h"
#import "ProfileManager.h"
#import "PhoneInfo.h"
#import <unistd.h>

static NSUInteger featureChecks;
@interface PXFailingFeatureManager : ProfileManager
@property(nonatomic,assign) BOOL failWrites;
@end
@implementation PXFailingFeatureManager
- (BOOL)saveData { return self.failWrites?NO:[super saveData]; }
@end
#define EXPECT(x) do { featureChecks++; if (!(x)) { fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x); abort(); } } while(0)
static void Put(NSString *path,NSString *value) {
    EXPECT([NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]);
    EXPECT([value writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
}
static NSDictionary *Phone(void) { return @{@"idfa":@"CD0278A1-7DF9-4CE9-B2D3-459C5B919FE9",@"idfv":@"B283221C-5B03-4781-9F12-DA580DA0B331",@"runtime":@{@"location":@{@"latitude":@31.2,@"longitude":@121.5},@"timeZoneName":@"Asia/Shanghai",@"outputVolume":@0.5}}; }
void PXRunFeatureTests(NSString *directory) {
    NSFileManager *fm=NSFileManager.defaultManager; NSError *error=nil;
    EXPECT(PXValidatePhoneDictionary(Phone(),&error)!=nil);
    EXPECT(PXValidateRuntime(@{@"location":@{@"latitude":@91,@"longitude":@0}},&error)==nil && error);
    EXPECT(PXValidateRuntime(@{@"outputVolume":@2},&error)==nil);
    EXPECT(PXValidateRuntime(@{@"timeZoneName":@"not/a/timezone"},&error)==nil);
    EXPECT(PXValidateRuntime(@{@"pushTokenHex":@"abc"},&error)==nil);
    EXPECT(PXValidateRuntime(@{@"pushTokenHex":@"abcd00"},&error)!=nil && !error);
    EXPECT(PXValidateOptions(@{@"idfaEndpoint":@"http://example.test"},&error)==nil);
    EXPECT(PXValidateOptions(@{@"versionWeights":@{@"18.5":@0}},&error)==nil);
    EXPECT(PXValidateOptions(@{@"versionWeights":@{@"18.5":@100},@"wifiPercent":@70,@"fiveGPercent":@30},&error)!=nil);
    EXPECT(PXValidatedRelativePaths(@[@"../outside"],&error)==nil);
    EXPECT(PXValidatedRelativePaths(@[@"/Documents"],&error)==nil);
    EXPECT(PXValidatedRelativePaths(@[@"Library/Preferences/token"],&error)!=nil);
    NSMutableDictionary *bad=[Phone() mutableCopy]; bad[@"deviceModel"]=@{@"cpuCoreCount":@[]};
    EXPECT(PXValidatePhoneDictionary(bad,&error)==nil);
    bad[@"deviceModel"]=@{@"cpuCoreCount":@4.5}; EXPECT(PXValidatePhoneDictionary(bad,&error)==nil);
    bad=[Phone() mutableCopy]; bad[@"networkInfo"]=@{@"connectionType":@4}; EXPECT(PXValidatePhoneDictionary(bad,&error)==nil);
    EXPECT(PXValidatePhoneDictionary(@{@"runtime":@{}},&error)==nil);
    PhoneInfo *phone=[PhoneInfo fromDictionary:Phone()];
    EXPECT([phone.toDictionary[@"runtime"] isEqual:Phone()[@"runtime"]]);
    DeviceModel *memory=[DeviceModel new]; memory.deviceMemory=@4;
    EXPECT(PXDeviceMemoryBytes(memory)==4294967296ULL);
    memory.physicalMemoryBytes=@4040785920ULL;
    EXPECT(PXDeviceMemoryBytes(memory)==4040785920ULL);
    EXPECT([DeviceModel fromDictionary:memory.toDictionary].physicalMemoryBytes.unsignedLongLongValue==4040785920ULL);
    UpTimeInfo *uptime=[UpTimeInfo new]; uptime.bootTime=[NSDate dateWithTimeIntervalSince1970:1700000000]; uptime.upTime=1234;
    EXPECT([UpTimeInfo fromDictionary:uptime.toDictionary].bootTime.timeIntervalSince1970==1700000000);
    NSDictionary *parsed=PXParseCommandURL([NSURL URLWithString:@"projectx://cmd/activeBackupDataByName?name=a%26b"],&error);
    EXPECT([parsed[@"command"] isEqual:@"switchProfile"] && [parsed[@"parameters"][@"name"] isEqual:@"a&b"]);
    EXPECT([PXParseCommandURL([NSURL URLWithString:@"weaponx://cmd/nextBackupData"],&error)[@"parameters"][@"operation"] isEqual:@"next"]);
    EXPECT(PXParseCommandURL([NSURL URLWithString:@"projectx://cmd/newPhone?x=1&x=2"],&error)==nil);
    EXPECT(PXParseCommandURL([NSURL URLWithString:@"projectx://cmd/setDisableTime?name=a&time=oops"],&error)==nil);
    EXPECT(PXParseCommandURL([NSURL URLWithString:@"https://cmd/newPhone"],&error)==nil);
    EXPECT([PXParseCommandURL([NSURL URLWithString:@"projectx://cmd/newPhone?version=18.5&model=iPhone14%2C7"],&error)[@"parameters"][@"model"] isEqual:@"iPhone14,7"]);
    EXPECT([PXParseCommandURL([NSURL URLWithString:@"projectx://cmd/updatepara?OSVersion=18.5"],&error)[@"command"] isEqual:@"updateParameters"]);
    NSString *root=[directory stringByAppendingPathComponent:@"features"];
    NSString *live=[root stringByAppendingPathComponent:@"live"],*snapshot=[root stringByAppendingPathComponent:@"snapshot"];
    Put([live stringByAppendingPathComponent:@"Library/Preferences/token"],@"keep");
    Put([live stringByAppendingPathComponent:@"Documents/old.txt"],@"old");
    EXPECT(PXCopyContainer(live,snapshot,@[@"Library/Preferences/token"],&error));
    EXPECT(![fm fileExistsAtPath:[snapshot stringByAppendingPathComponent:@"Library/Preferences/token"]]);
    EXPECT(PXClearContainer(live,@[@"Library/Preferences/token"],&error));
    EXPECT([fm fileExistsAtPath:[live stringByAppendingPathComponent:@"Library/Preferences/token"]]);
    EXPECT(![fm fileExistsAtPath:[live stringByAppendingPathComponent:@"Documents/old.txt"]]);
    EXPECT(PXCopyContainer(snapshot,live,@[@"Library/Preferences/token"],&error));
    EXPECT([fm fileExistsAtPath:[live stringByAppendingPathComponent:@"Documents/old.txt"]]);
    NSString *outside=[root stringByAppendingPathComponent:@"outside.txt"]; Put(outside,@"outside");
    NSString *symlinkPath=[live stringByAppendingPathComponent:@"Documents/link"];
    EXPECT(symlink(outside.fileSystemRepresentation,symlinkPath.fileSystemRepresentation)==0);
    EXPECT(!PXValidateDirectoryTree(live,&error));
    EXPECT(!PXCopyContainer(live,[root stringByAppendingPathComponent:@"reject"],@[],&error));
    EXPECT(PXClearContainer(live,@[],&error));
    EXPECT(PXValidateDirectoryTree(live,&error));
    EXPECT([fm fileExistsAtPath:outside]);
    NSString *archive=[root stringByAppendingPathComponent:@"backup.zip"],*expanded=[root stringByAppendingPathComponent:@"expanded"];
    Put([snapshot stringByAppendingPathComponent:@"unicode/参数.txt"],@"内容");
    EXPECT(PXCreateArchive(snapshot,archive,&error));
    EXPECT(PXExtractArchive(archive,expanded,&error));
    EXPECT([[NSString stringWithContentsOfFile:[expanded stringByAppendingPathComponent:@"unicode/参数.txt"] encoding:NSUTF8StringEncoding error:NULL] isEqual:@"内容"]);
    for (NSString *name in @[@"traversal.zip",@"absolute.zip",@"symlink.zip",@"duplicate.zip",@"corrupt.zip"]) {
        NSString *destination=[root stringByAppendingPathComponent:name];
        EXPECT(!PXExtractArchive([directory stringByAppendingPathComponent:name],destination,&error));
        EXPECT(![fm fileExistsAtPath:destination]);
    }
    ProfileManager *manager=[[ProfileManager alloc] initWithDataDirectory:[root stringByAppendingPathComponent:@"profiles"]];
    EXPECT([manager genBackupDirectory]!=nil); Profile *first=manager.mutableProfiles.firstObject;
    EXPECT([manager genBackupDirectory]!=nil); Profile *second=manager.mutableProfiles.lastObject;
    EXPECT([manager setDisabledUntil:[NSDate dateWithTimeIntervalSinceNow:3600] forProfile:first.id]);
    EXPECT(![manager switchToProfile:first]);
    EXPECT([manager navigationTarget:@"previous" wrap:NO]==nil);
    EXPECT(![manager setDisabledUntil:[NSDate dateWithTimeIntervalSinceNow:3600] forProfile:second.id]);
    EXPECT([manager setDisabledUntil:nil forProfile:first.id]);
    EXPECT([manager navigationTarget:@"previous" wrap:NO]==first);
    EXPECT([manager moveProfile:second.id toIndex:0]);
    EXPECT([manager navigationTarget:@"next" wrap:NO]==first);
    ProfileManager *reload=[[ProfileManager alloc] initWithDataDirectory:manager.dataDirectory];
    EXPECT([reload.mutableProfiles.firstObject.id isEqual:second.id]);
    NSString *active=manager.currentId;
    EXPECT([manager genInactiveBackupDirectory]!=nil);
    EXPECT([manager.currentId isEqual:active]);
    EXPECT([Profile fromDictionary:@{@"id":@"bad\0id"}]==nil);
    NSData *json=[NSJSONSerialization dataWithJSONObject:Phone() options:0 error:NULL];
    EXPECT([json writeToFile:[expanded stringByAppendingPathComponent:@"phoneInfo.json"] atomically:YES]);
    Profile *imported=[manager importProfileDirectory:expanded name:@"导入" error:&error];
    EXPECT(imported && ![manager isCurrent:imported] && [imported.name isEqual:@"导入"]);
    EXPECT(symlink(outside.fileSystemRepresentation,[expanded stringByAppendingPathComponent:@"badlink"].fileSystemRepresentation)==0);
    EXPECT([manager importProfileDirectory:expanded name:@"bad" error:&error]==nil);
    PXFailingFeatureManager *failing=[[PXFailingFeatureManager alloc] initWithDataDirectory:[root stringByAppendingPathComponent:@"transaction"]];
    EXPECT([failing genBackupDirectory]!=nil); NSString *old=failing.currentId;
    EXPECT([failing genBackupDirectory]!=nil); NSString *current=failing.currentId;
    failing.failWrites=YES;
    EXPECT((![failing removeProfilesWithIDs:@[old,current]]));
    EXPECT(failing.mutableProfiles.count==2 && [failing.currentId isEqual:current]);
    failing.failWrites=NO;
    EXPECT(([failing removeProfilesWithIDs:@[old,current]]));
    EXPECT(failing.mutableProfiles.count==1 && [failing.currentId isEqual:current]);
    printf("PASS: %lu feature checks\n",(unsigned long)featureChecks);
}
