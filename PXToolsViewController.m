#import "PXToolsViewController.h"
#import "DaemonApiManager.h"
#import "HttpRequest.h"
#import "DaemonApi.h"
#import "PXConfiguration.h"
#import <Photos/Photos.h>

@interface PXJSONEditor : UIViewController
@property(nonatomic,strong) UITextView *editor;
@property(nonatomic,strong) NSDictionary *value;
@property(nonatomic,copy) void(^save)(NSDictionary *,void(^)(NSError *));
@end
@implementation PXJSONEditor
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.editor=[UITextView new]; self.editor.translatesAutoresizingMaskIntoConstraints=NO;
    self.editor.font=[UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    self.editor.autocorrectionType=UITextAutocorrectionTypeNo; self.editor.smartQuotesType=UITextSmartQuotesTypeNo;
    self.editor.text=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:self.value ?: @{} options:NSJSONWritingPrettyPrinted error:NULL] encoding:NSUTF8StringEncoding];
    [self.view addSubview:self.editor];
    [NSLayoutConstraint activateConstraints:@[[self.editor.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.editor.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.editor.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.editor.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12]]];
    if (self.save) self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(saveJSON)];
    else self.editor.editable=NO;
}
- (void)saveJSON {
    NSError *error=nil; id value=[NSJSONSerialization JSONObjectWithData:[self.editor.text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
    if (![value isKindOfClass:NSDictionary.class]) error=error ?: PXError(@"请输入 JSON 对象");
    if (error) { [self showError:error]; return; }
    self.navigationItem.rightBarButtonItem.enabled=NO;
    self.save(value,^(NSError *failure) { dispatch_async(dispatch_get_main_queue(),^{
        self.navigationItem.rightBarButtonItem.enabled=YES;
        if (failure) [self showError:failure]; else [self.navigationController popViewControllerAnimated:YES];
    }); });
}
- (void)showError:(NSError *)error {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"保存失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}
@end

@interface PXChoiceController : UITableViewController
@property(nonatomic,strong) NSArray<NSDictionary *> *choices;
@property(nonatomic,strong) NSMutableSet<NSString *> *selected;
@property(nonatomic,copy) void(^done)(NSArray *);
@end
@implementation PXChoiceController
- (void)viewDidLoad { [super viewDidLoad]; self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"确定" style:UIBarButtonItemStyleDone target:self action:@selector(complete)]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.choices.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; NSDictionary *row=self.choices[indexPath.row];
    cell.textLabel.text=row[@"title"] ?: row[@"id"]; cell.detailTextLabel.text=row[@"id"];
    cell.accessoryType=[self.selected containsObject:row[@"id"]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *key=self.choices[indexPath.row][@"id"];
    if ([self.selected containsObject:key]) [self.selected removeObject:key]; else [self.selected addObject:key];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)complete {
    NSMutableArray *keys=[NSMutableArray array]; for (NSDictionary *row in self.choices) if ([self.selected containsObject:row[@"id"]]) [keys addObject:row[@"id"]];
    [self.navigationController popViewControllerAnimated:YES]; self.done(keys);
}
@end

@interface PXToolsViewController () <UIDocumentPickerDelegate>
@property(nonatomic,strong) NSArray *sections;
@property(nonatomic,copy) NSString *importCommand;
@end
@implementation PXToolsViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"参数与工具";
    self.sections=@[
        @[@"定位",@"时区",@"输出音量",@"OpenUDID",@"推送 token",@"屏幕安全区",@"GPU 能力",@"应用版本",@"环境兼容",@"代理兼容",@"SDK 兼容",@"SDK 采集抑制",@"SDK 初始化抑制",@"Realm 写入抑制",@"广告归因 token 抑制",@"SDK 元数据改写",@"隐藏模拟定位标志",@"跟踪状态",@"高级设备参数"],
        @[@"选择机型",@"选择系统版本",@"选择运营商",@"版本权重",@"随机策略与清理选项"],
        @[@"上一条档案",@"下一条档案",@"第一条档案",@"最后一条档案",@"档案禁用时间",@"调整档案顺序",@"批量删除档案",@"导出备份",@"导入备份",@"导出设备参数",@"导入设备参数"],
        @[@"清理剪贴板",@"清理 Safari",@"清理选中应用的系统缓存",@"清理可访问的相册",@"钥匙串恢复状态"]];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"设备参数",@"随机策略",@"档案",@"清理"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section==0) return @"参数作用于选中的应用。高级参数可分别开启环境、代理和 SDK 兼容选项。推送 token 与跟踪状态修改仅改变应用读到的值。";
    if (section==1) return @"留空多选列表表示不限制；版本范围仍使用设置页的最低与最高版本。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text=self.sections[indexPath.section][indexPath.row]; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)message:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"ProjectX" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)command:(NSString *)command parameters:(NSDictionary *)parameters done:(void(^)(id))done {
    self.navigationItem.prompt=@"处理中…"; self.tableView.userInteractionEnabled=NO;
    [[DaemonApiManager sharedManager] executeCommand:command parameters:parameters completion:^(id result,NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{
            self.navigationItem.prompt=nil; self.tableView.userInteractionEnabled=YES;
            if (error) [self message:error.localizedDescription]; else if (done) done(result); else [self message:@"完成"];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ProjectXCommandFinished" object:nil];
        });
    }];
}
- (void)runtime:(void(^)(NSMutableDictionary *phone,NSMutableDictionary *runtime))block {
    daemonGET(GET_PHONE_INFO,^(id data,NSError *error) { dispatch_async(dispatch_get_main_queue(),^{
        if (error || ![data isKindOfClass:NSDictionary.class]) { [self message:error.localizedDescription ?: @"无法读取参数"]; return; }
        block([data mutableCopy],[data[@"runtime"] mutableCopy] ?: [NSMutableDictionary dictionary]);
    }); });
}
- (void)editRuntime:(NSString *)title fields:(NSArray *)fields {
    [self runtime:^(NSMutableDictionary *phone,NSMutableDictionary *runtime) {
        BOOL location=[title isEqual:@"定位"];
        NSDictionary *values=location?runtime[@"location"]:runtime;
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:@"留空字段恢复原值；经纬度需同时填写。" preferredStyle:UIAlertControllerStyleAlert];
        for (NSArray *field in fields) [alert addTextFieldWithConfigurationHandler:^(UITextField *text) {
            text.placeholder=field[1]; text.text=values[field[0]]?[values[field[0]] description]:@"";
            text.autocorrectionType=UITextAutocorrectionTypeNo; text.autocapitalizationType=UITextAutocapitalizationTypeNone;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSMutableDictionary *updated=[values mutableCopy] ?: [NSMutableDictionary dictionary];
            for (NSUInteger i=0;i<fields.count;i++) {
                NSString *key=fields[i][0],*value=alert.textFields[i].text;
                if (!value.length) { [updated removeObjectForKey:key]; continue; }
                if ([fields[i][2] boolValue]) {
                    NSScanner *scanner=[NSScanner scannerWithString:value]; double number=0;
                    if (![scanner scanDouble:&number] || !scanner.isAtEnd) { [self message:@"请输入有效数字"]; return; }
                    updated[key]=@(number);
                } else updated[key]=value;
            }
            if (location) { if (updated.count) runtime[@"location"]=updated; else [runtime removeObjectForKey:@"location"]; }
            NSDictionary *finalRuntime=location?runtime:updated;
            NSError *error=nil; if (!PXValidateRuntime(finalRuntime,&error)) { [self message:error.localizedDescription]; return; }
            phone[@"runtime"]=finalRuntime; [self command:@"setPhoneInfo" parameters:phone done:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}
- (void)pickProfiles:(NSString *)title multiple:(BOOL)multiple done:(void(^)(NSArray *ids,NSArray *rows))completion {
    [self command:@"listProfiles" parameters:@{} done:^(NSDictionary *result) {
        NSArray *profiles=result[@"profiles"]; NSMutableArray *choices=[NSMutableArray array];
        for (NSDictionary *p in profiles) [choices addObject:@{@"id":p[@"id"],@"title":[NSString stringWithFormat:@"%@%@",p[@"name"],[p[@"id"] isEqual:result[@"currentId"]]?@"（当前）":@""]}];
        PXChoiceController *picker=[PXChoiceController new]; picker.title=title; picker.choices=choices; picker.selected=[NSMutableSet set];
        picker.done=^(NSArray *ids) { if ((!multiple && ids.count!=1) || !ids.count) { [self message:@"请选择档案（单项操作只选一条）"]; return; } completion(ids,profiles); };
        [self.navigationController pushViewController:picker animated:YES];
    }];
}
- (void)sharePath:(NSDictionary *)result {
    NSString *path=result[@"path"]; if (!path.length) { [self message:@"未生成文件"]; return; }
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    share.popoverPresentationController.sourceView=self.view; share.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,80,1,1);
    [self presentViewController:share animated:YES completion:nil];
}
- (void)importFile:(NSString *)command {
    self.importCommand=command;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initWithDocumentTypes:
        [command isEqual:@"importProfiles"]?@[@"public.zip-archive"]:@[@"public.json",@"public.text"] inMode:UIDocumentPickerModeImport];
    picker.delegate=self; [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject; if (!url) return;
    BOOL access=[url startAccessingSecurityScopedResource]; NSError *error=nil;
    NSString *directory=@"/private/var/mobile/Media/ProjectX/Transfer/Imports";
    NSString *filename=[NSUUID.UUID.UUIDString stringByAppendingPathExtension:[self.importCommand isEqual:@"importProfiles"]?@"zip":@"json"];
    BOOL copied=[NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error] &&
        [NSFileManager.defaultManager copyItemAtURL:url toURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:filename]] error:&error];
    if (access) [url stopAccessingSecurityScopedResource];
    if (!copied) { [self message:error.localizedDescription]; return; }
    [self command:self.importCommand parameters:@{@"filename":filename} done:nil];
}
- (void)editJSON:(NSString *)title value:(NSDictionary *)value save:(void(^)(NSDictionary *,void(^)(NSError *)))save {
    PXJSONEditor *editor=[PXJSONEditor new]; editor.title=title; editor.value=value; editor.save=save;
    [self.navigationController pushViewController:editor animated:YES];
}
- (void)clearPhotos {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) { dispatch_async(dispatch_get_main_queue(),^{
        if (status!=PHAuthorizationStatusAuthorized && status!=PHAuthorizationStatusLimited) { [self message:@"未获得相册访问权限"]; return; }
        PHFetchResult *assets=[PHAsset fetchAssetsWithOptions:nil];
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"清理可访问的相册？" message:[NSString stringWithFormat:@"将删除当前允许访问的 %lu 个照片和视频项目。",(unsigned long)assets.count] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{ [PHAssetChangeRequest deleteAssets:assets]; } completionHandler:^(BOOL success,NSError *error) {
                dispatch_async(dispatch_get_main_queue(),^{ [self message:success?@"相册清理完成":error.localizedDescription ?: @"清理失败"]; });
            }];
        }]]; [self presentViewController:alert animated:YES completion:nil];
    }); }];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; NSString *title=self.sections[indexPath.section][indexPath.row];
    if (indexPath.section==0) {
        NSDictionary *flags=@{@"环境兼容":@"maskEnvironment",@"代理兼容":@"maskProxy",@"SDK 兼容":@"sdkCompatibility",@"隐藏模拟定位标志":@"hideSimulatedLocation",
            @"SDK 采集抑制":@"sdkSuppressCollectors",@"SDK 初始化抑制":@"sdkSuppressInitialization",
            @"Realm 写入抑制":@"sdkBlockRealmWrites",@"广告归因 token 抑制":@"sdkSuppressAttribution",@"SDK 元数据改写":@"sdkRewriteMetadata"};
        if (flags[title] || [title isEqual:@"跟踪状态"]) {
            [self runtime:^(NSMutableDictionary *phone,NSMutableDictionary *runtime) {
                NSDictionary *help=@{@"SDK 采集抑制":@"跳过 Talkable、IGLocation 和 HMD 采集入口，可能影响对应功能。需同时开启 SDK 兼容。",
                    @"SDK 初始化抑制":@"跳过适配表中的初始化/注册入口。已执行的 +load 不会撤销，可能影响 SDK 启动。需同时开启 SDK 兼容。",
                    @"Realm 写入抑制":@"跳过 RLMArray insertObject，可能导致目标应用数据无法保存。需同时开启 SDK 兼容。",
                    @"广告归因 token 抑制":@"让 AFSDKiAdClient 返回空 token，可能影响广告归因。需同时开启 SDK 兼容。",
                    @"SDK 元数据改写":@"按当前档案稳定改写 FFM 的 NETS 数字尾段和 RDATES。需同时开启 SDK 兼容。"};
                UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:help[title] ?: @"应用重启后检查效果；系统授权本身不会改变。" preferredStyle:UIAlertControllerStyleActionSheet];
                NSArray *labels=flags[title]?@[@"关闭",@"开启"]:@[@"使用系统状态",@"尚未决定",@"受限",@"拒绝",@"允许"];
                for (NSUInteger i=0;i<labels.count;i++) [alert addAction:[UIAlertAction actionWithTitle:labels[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    if (flags[title]) runtime[flags[title]]=@(i==1);
                    else { runtime[@"trackingOverride"]=@(i>0); if (i>0) runtime[@"trackingStatus"]=@(i-1); }
                    phone[@"runtime"]=runtime; [self command:@"setPhoneInfo" parameters:phone done:nil];
                }]];
                [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                alert.popoverPresentationController.sourceView=self.view; alert.popoverPresentationController.sourceRect=[self.tableView rectForRowAtIndexPath:indexPath];
                [self presentViewController:alert animated:YES completion:nil];
            }]; return;
        }
        NSDictionary *forms=@{
            @"定位":@[@[@"latitude",@"纬度 -90…90",@YES],@[@"longitude",@"经度 -180…180",@YES],@[@"name",@"位置名称",@NO],@[@"locality",@"城市",@NO],@[@"country",@"国家",@NO],@[@"ISOcountryCode",@"国家代码",@NO]],
            @"时区":@[@[@"timeZoneName",@"如 Asia/Shanghai",@NO]],@"输出音量":@[@[@"outputVolume",@"0…1",@YES]],
            @"OpenUDID":@[@[@"openUDID",@"OpenUDID",@NO]],@"推送 token":@[@[@"pushTokenHex",@"十六进制 token",@NO]],
            @"屏幕安全区":@[@[@"screenTopInset",@"顶部高度",@YES],@[@"screenBottomInset",@"底部高度",@YES]],
            @"GPU 能力":@[@[@"gpuWorkingSetSize",@"工作集大小（字节）",@YES],@[@"gpuRaytracing",@"光追 0 或 1",@YES]]};
        if (forms[title]) { [self editRuntime:title fields:forms[title]]; return; }
        if ([title isEqual:@"应用版本"]) {
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:@"作用于选中应用读取到的 version/build。留空版本以恢复。" preferredStyle:UIAlertControllerStyleAlert];
            for (NSString *hint in @[@"应用包名",@"版本号",@"构建号"]) [alert addTextFieldWithConfigurationHandler:^(UITextField *text) { text.placeholder=hint; text.autocapitalizationType=UITextAutocapitalizationTypeNone; }];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                NSMutableDictionary *p=[@{@"bundleID":alert.textFields[0].text ?: @""} mutableCopy];
                if (alert.textFields[1].text.length) p[@"version"]=alert.textFields[1].text;
                if (alert.textFields[2].text.length) p[@"build"]=alert.textFields[2].text;
                if (p.count==1) p[@"restore"]=@YES; [self command:@"setAppVersion" parameters:p done:nil];
            }]]; [self presentViewController:alert animated:YES completion:nil]; return;
        }
        [self runtime:^(NSMutableDictionary *phone,NSMutableDictionary *runtime) {
            [self editJSON:title value:runtime save:^(NSDictionary *value,void(^done)(NSError *)) {
                NSError *failure=nil; if (!PXValidateRuntime(value,&failure)) { done(failure); return; }
                phone[@"runtime"]=value; [[DaemonApiManager sharedManager] executeCommand:@"setPhoneInfo" parameters:phone completion:^(id result,NSError *error) { done(error); }];
            }];
        }]; return;
    }
    if (indexPath.section==1) {
        [self command:@"getSettings" parameters:@{} done:^(NSDictionary *settings) {
            if (indexPath.row==4) {
                [self editJSON:title value:settings save:^(NSDictionary *value,void(^done)(NSError *)) { [[DaemonApiManager sharedManager] executeCommand:@"saveSettings" parameters:value completion:^(id result,NSError *error) { done(error); }]; }]; return;
            }
            if (indexPath.row==3) {
                [self editJSON:@"版本权重（版本号:权重）" value:settings[@"options"][@"versionWeights"] ?: @{} save:^(NSDictionary *value,void(^done)(NSError *)) {
                    NSMutableDictionary *updated=[settings mutableCopy],*options=[settings[@"options"] mutableCopy] ?: [NSMutableDictionary dictionary];
                    if (value.count) options[@"versionWeights"]=value; else [options removeObjectForKey:@"versionWeights"];
                    updated[@"options"]=options;
                    [[DaemonApiManager sharedManager] executeCommand:@"saveSettings" parameters:updated completion:^(id result,NSError *error) { done(error); }];
                }]; return;
            }
            NSString *key=@[@"models",@"versions",@"carriers"][indexPath.row];
            [self command:@"getCatalog" parameters:@{} done:^(NSDictionary *catalog) {
                PXChoiceController *picker=[PXChoiceController new]; picker.title=title; picker.choices=catalog[key];
                picker.selected=[NSMutableSet setWithArray:settings[@"options"][key] ?: @[]];
                picker.done=^(NSArray *values) { NSMutableDictionary *updated=[settings mutableCopy],*options=[settings[@"options"] mutableCopy] ?: [NSMutableDictionary dictionary]; options[key]=values; updated[@"options"]=options; [self command:@"saveSettings" parameters:updated done:nil]; };
                [self.navigationController pushViewController:picker animated:YES];
            }];
        }]; return;
    }
    if (indexPath.section==2) {
        NSInteger row=indexPath.row;
        if (row<4) { [self command:@"navigateProfile" parameters:@{@"operation":@[@"previous",@"next",@"first",@"last"][row]} done:nil]; return; }
        if (row==8 || row==10) { [self importFile:row==8?@"importProfiles":@"importParameters"]; return; }
        if (row==9) { [self command:@"exportParameters" parameters:@{} done:^(id value) { [self sharePath:value]; }]; return; }
        [self pickProfiles:title multiple:row==6||row==7 done:^(NSArray *ids,NSArray *rows) {
            if (row==7) { [self command:@"exportProfiles" parameters:@{@"ids":ids} done:^(id value) { [self sharePath:value]; }]; return; }
            if (row==6) {
                UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"删除所选档案？" message:@"当前档案与档案 0 会保留。" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [self command:@"deleteProfiles" parameters:@{@"ids":ids} done:nil]; }]];
                [self presentViewController:alert animated:YES completion:nil]; return;
            }
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:row==4?@"小时数；0 表示启用":@"目标位置，从 0 开始" preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField *text) { text.keyboardType=UIKeyboardTypeDecimalPad; text.text=@"0"; }];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                NSScanner *scanner=[NSScanner scannerWithString:alert.textFields.firstObject.text]; double value=0;
                if (![scanner scanDouble:&value] || !scanner.isAtEnd) { [self message:@"请输入有效数字"]; return; }
                [self command:row==4?@"disableProfile":@"reorderProfile" parameters:@{@"id":ids.firstObject,(row==4?@"hours":@"index"):@(value)} done:nil];
            }]]; [self presentViewController:alert animated:YES completion:nil];
        }]; return;
    }
    if (indexPath.row==3) { [self clearPhotos]; return; }
    if (indexPath.row==4) {
        [self command:@"keychainStatus" parameters:@{} done:^(id value) {
            [self editJSON:@"钥匙串恢复状态" value:value save:nil];
        }]; return;
    }
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:[title isEqual:@"清理 Safari"]?@"将关闭 Safari 并清理浏览数据。":indexPath.row==0?@"将清空当前剪贴板内容。":@"将关闭选中应用，并清理其系统目录中的缓存、偏好和浏览存储。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清理" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [self command:@[@"clearPasteboard",@"clearSafari",@"clearSystemResidues"][indexPath.row] parameters:@{} done:nil]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
