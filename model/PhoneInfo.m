#import "PhoneInfo.h"
#import "PXConfiguration.h"

@implementation PhoneInfo
#pragma mark - JSON 序列化

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"runtime"] = self.runtime ?: @{};
    
    // 设备标识信息
    dict[@"idfa"] = self.idfa ?: @"";
    dict[@"idfv"] = self.idfv ?: @"";
    dict[@"deviceName"] = self.deviceName ?: @"";
    dict[@"serialNumber"] = self.serialNumber ?: @"";
    dict[@"IMEI"] = self.IMEI ?: @"";
    dict[@"MEID"] = self.MEID ?: @"";
    dict[@"iosVersion"] = [self.iosVersion toDictionary] ?: @{};
    
    // UUID 信息
    dict[@"systemBootUUID"] = self.systemBootUUID ?: @"";
    dict[@"dyldCacheUUID"] = self.dyldCacheUUID ?: @"";
    dict[@"pasteboardUUID"] = self.pasteboardUUID ?: @"";
    dict[@"keychainUUID"] = self.keychainUUID ?: @"";
    dict[@"userDefaultsUUID"] = self.userDefaultsUUID ?: @"";
    dict[@"appGroupUUID"] = self.appGroupUUID ?: @"";
    dict[@"coreDataUUID"] = self.coreDataUUID ?: @"";
    dict[@"appInstallUUID"] = self.appInstallUUID ?: @"";
    dict[@"appContainerUUID"] = self.appContainerUUID ?: @"";
    
    // 其他对象信息
    dict[@"storageInfo"] = [self.storageInfo toDictionary] ?: @{};
    dict[@"batteryInfo"] = [self.batteryInfo toDictionary] ?: @{};
    dict[@"wifiInfo"] = [self.wifiInfo toDictionary] ?: @{};
    dict[@"deviceModel"] = [self.deviceModel toDictionary] ?: @{};
    dict[@"upTimeInfo"] = [self.upTimeInfo toDictionary] ?: @{};
    dict[@"networkInfo"] = [self.networkInfo toDictionary] ?: @{};
    
    return [dict copy];
}

#pragma mark - JSON 反序列化

+ (instancetype)fromDictionary:(NSDictionary *)dict {

    if (![dict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    PhoneInfo *phoneInfo = [[PhoneInfo alloc] init];
    phoneInfo.runtime = PXValidateRuntime(dict[@"runtime"] ?: @{}, NULL) ?: @{};
    
    // 设备标识信息
    phoneInfo.idfa = dict[@"idfa"] ?: @"";
    phoneInfo.idfv = dict[@"idfv"] ?: @"";
    phoneInfo.deviceName = dict[@"deviceName"] ?: @"";
    phoneInfo.serialNumber = dict[@"serialNumber"] ?: @"";
    phoneInfo.IMEI = dict[@"IMEI"] ?: @"";
    phoneInfo.MEID = dict[@"MEID"] ?: @"";
    
    // 反序列化嵌套对象
    NSDictionary *iosVersionDict = dict[@"iosVersion"];
    if ([iosVersionDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.iosVersion = [IosVersion fromDictionary:iosVersionDict];
    }
    
    // UUID 信息
    phoneInfo.systemBootUUID = dict[@"systemBootUUID"] ?: @"";
    phoneInfo.dyldCacheUUID = dict[@"dyldCacheUUID"] ?: @"";
    phoneInfo.pasteboardUUID = dict[@"pasteboardUUID"] ?: @"";
    phoneInfo.keychainUUID = dict[@"keychainUUID"] ?: @"";
    phoneInfo.userDefaultsUUID = dict[@"userDefaultsUUID"] ?: @"";
    phoneInfo.appGroupUUID = dict[@"appGroupUUID"] ?: @"";
    phoneInfo.coreDataUUID = dict[@"coreDataUUID"] ?: @"";
    phoneInfo.appInstallUUID = dict[@"appInstallUUID"] ?: @"";
    phoneInfo.appContainerUUID = dict[@"appContainerUUID"] ?: @"";
    
    // 反序列化其他嵌套对象
    NSDictionary *storageInfoDict = dict[@"storageInfo"];
    if ([storageInfoDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.storageInfo = [StorageInfo fromDictionary:storageInfoDict];
    }
    
    NSDictionary *batteryInfoDict = dict[@"batteryInfo"];
    if ([batteryInfoDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.batteryInfo = [BatteryInfo fromDictionary:batteryInfoDict];
    }
    
    NSDictionary *wifiInfoDict = dict[@"wifiInfo"];
    if ([wifiInfoDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.wifiInfo = [WifiInfo fromDictionary:wifiInfoDict];
    }
    
    NSDictionary *deviceModelDict = dict[@"deviceModel"];
    if ([deviceModelDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.deviceModel = [DeviceModel fromDictionary:deviceModelDict];
    }
    
    NSDictionary *upTimeInfoDict = dict[@"upTimeInfo"];
    if ([upTimeInfoDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.upTimeInfo = [UpTimeInfo fromDictionary:upTimeInfoDict];
    }
    NSDictionary *networkInfoDict = dict[@"networkInfo"];
    if ([networkInfoDict isKindOfClass:[NSDictionary class]]) {
        phoneInfo.networkInfo = [NetworkInfo fromDictionary:networkInfoDict];
    }
    
    return phoneInfo;
}

#pragma mark - 文件存储

- (BOOL)saveToPrefs{
    NSDictionary *dict = [self toDictionary];
    
    // 使用新的静态方法保存
    return [PhoneInfo saveDictionaryToPrefs:dict ];
}

+ (instancetype)loadFromPrefs{
    CFPropertyListRef value =
        CFPreferencesCopyValue(
            CFSTR("PhoneInfo"),
            CFSTR("com.projectx.phoneinfo"),
            kCFPreferencesAnyUser,
            kCFPreferencesCurrentHost
        );

    if (!value || CFGetTypeID(value) != CFDictionaryGetTypeID()) {
        if (value) CFRelease(value);
        return nil;
    }

    NSDictionary *dict = (__bridge NSDictionary *)value;
    PhoneInfo *info = [PhoneInfo fromDictionary:dict];
    CFRelease(value);
    return info;
}

#pragma mark - 直接字典存储和读取

/**
 * 静态方法：将 NSDictionary 直接保存为 JSON 文件
 * @param dict 要保存的字典
 * @param filePath 文件路径
 * @return 保存是否成功
 */
+ (BOOL)saveDictionaryToPrefs:(NSDictionary *)dict {
    NSError *validationError = nil;
    if (!PXValidatePhoneDictionary(dict, &validationError)) return NO;
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) {
        NSLog(@"无效的字典参数");
        return NO;
    }
    
    
    CFPreferencesSetValue(
        CFSTR("PhoneInfo"),
        (__bridge CFPropertyListRef)dict,
        CFSTR("com.projectx.phoneinfo"),
        kCFPreferencesAnyUser,
        kCFPreferencesCurrentHost
    );

    BOOL success = CFPreferencesSynchronize(
        CFSTR("com.projectx.phoneinfo"),
        kCFPreferencesAnyUser,
        kCFPreferencesCurrentHost
    );
    if (success) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.projectx.phoneinfo.changed"), NULL, NULL, YES);
    return success;
}
/**
 * 静态方法：将 NSDictionary 直接保存为 JSON 文件
 * @param dict 要保存的字典
 * @param filePath 文件路径
 * @return 保存是否成功
 */
+ (BOOL)saveDictionaryToFile:(NSDictionary *)dict toFile:(NSString *)filePath {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) {
        NSLog(@"无效的字典参数");
        return NO;
    }
    
    if (!filePath || filePath.length == 0) {
        NSLog(@"无效的文件路径");
        return NO;
    }
    
    // 创建目录（如果不存在）
    NSString *directory = [filePath stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:directory]) {
        NSError *error = nil;
        BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                                  withIntermediateDirectories:YES
                                                                   attributes:nil
                                                                        error:&error];
        if (!success) {
            NSLog(@"创建目录失败: %@, error: %@", directory, error);
            return NO;
        }
    }
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict 
                                                       options:NSJSONWritingPrettyPrinted 
                                                         error:&error];
    
    if (error) {
        NSLog(@"JSON 序列化失败: %@", error);
        return NO;
    }
    
    BOOL success = [jsonData writeToFile:filePath 
                                 options:NSDataWritingAtomic 
                                   error:&error];
    
    if (!success) {
        NSLog(@"写入文件失败: %@, error: %@", filePath, error);
        return NO;
    }
    
    NSLog(@"字典已成功保存到: %@", filePath);
    return YES;
}

/**
 * 静态方法：从 JSON 文件读取并返回 NSDictionary
 * @param filePath 文件路径
 * @return 读取的字典，失败返回 nil
 */
+ (NSDictionary *)loadDictionaryFromFile:(NSString *)filePath {
    if (!filePath || filePath.length == 0) {
        NSLog(@"无效的文件路径");
        return nil;
    }
    
    // 检查文件是否存在
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:filePath];
    if (!fileExists) {
        NSLog(@"文件不存在: %@", filePath);
        return nil;
    }
    
    // 检查文件大小
    NSError *fileError = nil;
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&fileError];
    if (fileError) {
        NSLog(@"获取文件属性失败: %@", fileError);
        return nil;
    }
    
    NSNumber *fileSize = fileAttributes[NSFileSize];
    if (fileSize.unsignedLongLongValue == 0) {
        NSLog(@"文件为空: %@", filePath);
        return nil;
    }
    
    // 读取文件内容
    NSError *readError = nil;
    NSData *jsonData = [NSData dataWithContentsOfFile:filePath 
                                              options:NSDataReadingMappedIfSafe 
                                                error:&readError];
    
    if (readError) {
        NSLog(@"读取文件失败: %@, error: %@", filePath, readError);
        return nil;
    }
    
    if (!jsonData || jsonData.length == 0) {
        NSLog(@"文件内容为空: %@", filePath);
        return nil;
    }
    
    // 解析 JSON
    NSError *jsonError = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData 
                                                    options:kNilOptions 
                                                      error:&jsonError];
    
    if (jsonError) {
        NSLog(@"JSON 解析失败: %@, error: %@", filePath, jsonError);
        return nil;
    }
    
    if (![jsonObject isKindOfClass:[NSDictionary class]]) {
        NSLog(@"JSON 格式错误，期望字典类型，实际类型: %@", [jsonObject class]);
        return nil;
    }
    
    NSDictionary *dict = (NSDictionary *)jsonObject;
    NSLog(@"成功从文件读取字典，键数量: %lu", (unsigned long)dict.count);
    
    return dict;
}
@end


@implementation IosVersion
-(NSString *) versionAndBuild{
    return [NSString stringWithFormat:@"%@ (%@)", _version, _build];
}
- (NSDictionary *)toDictionary {
    return @{
        @"version": self.version ?: @"",
        @"build": self.build ?: @"",
        @"kernelVersion": self.kernelVersion ?: @"",
        @"darwin": self.darwin ?: @""
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    IosVersion *iosVersion = [[IosVersion alloc] init];
    iosVersion.version = dict[@"version"] ?: @"";
    iosVersion.build = dict[@"build"] ?: @"";
    iosVersion.kernelVersion = dict[@"kernelVersion"] ?: @"";
    iosVersion.darwin = dict[@"darwin"] ?: @"";
    return iosVersion;
}

@end

@implementation StorageInfo
-(NSString *) showInfo{
    return [NSString stringWithFormat:@"Total: %@ GB, Free: %@ GB", 
                                    _totalStorage, 
                                    _freeStorage];
}
- (NSDictionary *)toDictionary {
    return @{
        @"totalStorage": self.totalStorage ?: @"",
        @"freeStorage": self.freeStorage ?: @"",
        @"filesystemType": self.filesystemType ?: @""
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    StorageInfo *storageInfo = [[StorageInfo alloc] init];
    storageInfo.totalStorage = dict[@"totalStorage"] ?: @"";
    storageInfo.freeStorage = dict[@"freeStorage"] ?: @"";
    storageInfo.filesystemType = dict[@"filesystemType"] ?: @"";
    return storageInfo;
}
@end

@implementation BatteryInfo
- (NSDictionary *)toDictionary {
    return @{
        @"batteryLevel": self.batteryLevel ?: @"",
        @"batteryPercentage": self.batteryPercentage ?: @0
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    BatteryInfo *batteryInfo = [[BatteryInfo alloc] init];
    batteryInfo.batteryLevel = dict[@"batteryLevel"] ?: @"";
    batteryInfo.batteryPercentage = dict[@"batteryPercentage"] ?: @0;
    return batteryInfo;
}
@end

@implementation WifiInfo
-(NSString *) showInfo{
    return [NSString stringWithFormat:@"%@ (%@)", _ssid, _bssid];
}
- (NSDictionary *)toDictionary {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *lastConnectionTimeStr = @"";
    if (self.lastConnectionTime) {
        lastConnectionTimeStr = [formatter stringFromDate:self.lastConnectionTime];
    }
    
    return @{
        @"ssid": self.ssid ?: @"",
        @"bssid": self.bssid ?: @"",
        @"networkType": self.networkType ?: @"",
        @"wifiStandard": self.wifiStandard ?: @"",
        @"autoJoin": @(self.autoJoin),
        @"lastConnectionTime": lastConnectionTimeStr
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    WifiInfo *wifiInfo = [[WifiInfo alloc] init];
    wifiInfo.ssid = dict[@"ssid"] ?: @"";
    wifiInfo.bssid = dict[@"bssid"] ?: @"";
    wifiInfo.networkType = dict[@"networkType"] ?: @"";
    wifiInfo.wifiStandard = dict[@"wifiStandard"] ?: @"";
    wifiInfo.autoJoin = [dict[@"autoJoin"] boolValue];
    
    NSString *timeStr = dict[@"lastConnectionTime"];
    if (timeStr && [timeStr isKindOfClass:[NSString class]] && timeStr.length > 0) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        wifiInfo.lastConnectionTime = [formatter dateFromString:timeStr];
    }
    
    return wifiInfo;
}
@end

@implementation UpTimeInfo 
-(NSString *)upTimeStr{
    return [NSString stringWithFormat:@"%.2f hours", _upTime / 3600.0];
}
-(NSString *)bootTimeStr{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    return [formatter stringFromDate:_bootTime];
}

- (NSDictionary *)toDictionary {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *bootTimeStr = @"";
    if (self.bootTime) {
        bootTimeStr = [formatter stringFromDate:self.bootTime];
    }
    
    return @{
        @"upTime": @(self.upTime),
        @"bootTimeEpoch": self.bootTime ? @(self.bootTime.timeIntervalSince1970) : @0,
        @"bootTime": bootTimeStr
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    UpTimeInfo *upTimeInfo = [[UpTimeInfo alloc] init];
    upTimeInfo.upTime = [dict[@"upTime"] doubleValue];
    if ([dict[@"bootTimeEpoch"] isKindOfClass:NSNumber.class] && [dict[@"bootTimeEpoch"] doubleValue]>0) {
        upTimeInfo.bootTime=[NSDate dateWithTimeIntervalSince1970:[dict[@"bootTimeEpoch"] doubleValue]];
        return upTimeInfo;
    }
    
    NSString *bootTimeStr = dict[@"bootTime"];
    if (bootTimeStr && [bootTimeStr isKindOfClass:[NSString class]] && bootTimeStr.length > 0) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.timeZone=CFBridgingRelease(CFTimeZoneCopySystem());
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        upTimeInfo.bootTime = [formatter dateFromString:bootTimeStr];
    }
    
    return upTimeInfo;
}

@end

@implementation DeviceModel
- (NSDictionary *)toDictionary {
    return @{
        @"modelName": self.modelName ?: @"",
        @"name": self.name ?: @"",
        @"resolution": self.resolution ?: @"",
        @"viewportResolution": self.viewportResolution ?: @"",
        @"devicePixelRatio": self.devicePixelRatio ?: @1,
        @"screenDensity": self.screenDensity ?: @1,
        @"cpuArchitecture": self.cpuArchitecture ?: @"",
        @"hwModel": self.hwModel ?: @"",
        @"gpuFamily": self.gpuFamily ?: @"",
        @"deviceMemory": self.deviceMemory ?: @0,
        @"physicalMemoryBytes": self.physicalMemoryBytes ?: @0,
        @"cpuCoreCount": self.cpuCoreCount ?: @0,
        @"webGLInfo": [self.webGLInfo toDictionary] ?: @{}
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    DeviceModel *deviceModel = [[DeviceModel alloc] init];
    deviceModel.modelName = dict[@"modelName"] ?: @"";
    deviceModel.name = dict[@"name"] ?: @"";
    deviceModel.resolution = dict[@"resolution"] ?: @"";
    deviceModel.viewportResolution = dict[@"viewportResolution"] ?: @"";
    deviceModel.devicePixelRatio = dict[@"devicePixelRatio"] ?: @1;
    deviceModel.screenDensity = dict[@"screenDensity"] ?: @1;
    deviceModel.cpuArchitecture = dict[@"cpuArchitecture"] ?: @"";
    deviceModel.hwModel = dict[@"hwModel"] ?: @"";
    deviceModel.gpuFamily = dict[@"gpuFamily"] ?: @"";
    deviceModel.deviceMemory = dict[@"deviceMemory"] ?: @0;
    deviceModel.physicalMemoryBytes = [dict[@"physicalMemoryBytes"] isKindOfClass:NSNumber.class] ? dict[@"physicalMemoryBytes"] : @0;
    deviceModel.cpuCoreCount = dict[@"cpuCoreCount"] ?: @0;
    
    NSDictionary *webGLInfoDict = dict[@"webGLInfo"];
    if (webGLInfoDict && [webGLInfoDict isKindOfClass:[NSDictionary class]]) {
        deviceModel.webGLInfo = [WebGLInfo fromDictionary:webGLInfoDict];
    }
    
    return deviceModel;
}
- (NSString *) showInfo{
    return _name;
}
@end

@implementation WebGLInfo
- (NSDictionary *)toDictionary {
    return @{
        @"unmaskedVendor": self.unmaskedVendor ?: @"",
        @"unmaskedRenderer": self.unmaskedRenderer ?: @"",
        @"webglVendor": self.webglVendor ?: @"",
        @"webglRenderer": self.webglRenderer ?: @"",
        @"webglVersion": self.webglVersion ?: @"",
        @"maxTextureSize": self.maxTextureSize ?: @0,
        @"maxRenderBufferSize": self.maxRenderBufferSize ?: @0
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    WebGLInfo *webGLInfo = [[WebGLInfo alloc] init];
    webGLInfo.unmaskedVendor = dict[@"unmaskedVendor"] ?: @"";
    webGLInfo.unmaskedRenderer = dict[@"unmaskedRenderer"] ?: @"";
    webGLInfo.webglVendor = dict[@"webglVendor"] ?: @"";
    webGLInfo.webglRenderer = dict[@"webglRenderer"] ?: @"";
    webGLInfo.webglVersion = dict[@"webglVersion"] ?: @"";
    webGLInfo.maxTextureSize = dict[@"maxTextureSize"] ?: @0;
    webGLInfo.maxRenderBufferSize = dict[@"maxRenderBufferSize"] ?: @0;
    return webGLInfo;
}


@end


@implementation NetworkInfo : NSObject

- (NSDictionary *)toDictionary{
      return @{
        @"radioAccessTechnology": self.radioAccessTechnology ?: @"CTRadioAccessTechnologyLTE",
        @"carrierName": self.carrierName ?: @"",
        @"mcc": self.mcc ?: @"",
        @"mnc": self.mnc ?: @"",
        @"localIPv6Address": self.localIPv6Address ?: @"",
        @"localIPAddress": self.localIPAddress ?: @"",
        @"connectionType": @(self.connectionType),
        @"countryCode": self.countryCode ?: @""
    };
}
+ (instancetype)fromDictionary:(NSDictionary *)dict{
    NetworkInfo *networkInfo = [[NetworkInfo alloc] init];
    networkInfo.radioAccessTechnology = [dict[@"radioAccessTechnology"] isKindOfClass:NSString.class] ? dict[@"radioAccessTechnology"] : @"CTRadioAccessTechnologyLTE";
    networkInfo.carrierName = dict[@"carrierName"] ?: @"";
    networkInfo.mcc = dict[@"mcc"] ?: @"";
    networkInfo.mnc = dict[@"mnc"] ?: @"";
    networkInfo.localIPv6Address = dict[@"localIPv6Address"] ?: @"";
    networkInfo.localIPAddress = dict[@"localIPAddress"] ?: @"";
    networkInfo.countryCode = dict[@"countryCode"] ?: @"";
    id connectionTypeObj = dict[@"connectionType"];
    if ([connectionTypeObj isKindOfClass:[NSNumber class]]) {
        networkInfo.connectionType = [connectionTypeObj integerValue];
    } else if ([connectionTypeObj isKindOfClass:[NSString class]]) {
        // 兼容：如果存储的是字符串，尝试转换
        networkInfo.connectionType = [connectionTypeObj integerValue];
    } else {
        // 默认值
        networkInfo.connectionType = NetworkConnectionTypeAuto;
    }
    return networkInfo;
}
@end
