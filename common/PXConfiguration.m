#import "PXConfiguration.h"
#import "PhoneInfo.h"
#import <math.h>
unsigned long long PXDeviceMemoryBytes(DeviceModel *model) {
    if (model.physicalMemoryBytes.unsignedLongLongValue) return model.physicalMemoryBytes.unsignedLongLongValue;
    double nominal=model.deviceMemory.doubleValue;
    return isfinite(nominal) && nominal>0 && nominal<=1024?(unsigned long long)(nominal*1024.0*1024*1024):0;
}

NSError *PXError(NSString *message) {
    return [NSError errorWithDomain:@"ProjectX" code:400
                          userInfo:@{NSLocalizedDescriptionKey: message ?: @"操作失败"}];
}
static BOOL Fail(NSError **error, NSString *message) {
    if (error) *error = PXError(message);
    return NO;
}
static BOOL Number(id n, double low, double high) {
    return [n isKindOfClass:NSNumber.class] && isfinite([n doubleValue]) &&
           [n doubleValue] >= low && [n doubleValue] <= high;
}
BOOL PXValidBundleIdentifier(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > 255) return NO;
    return [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"] invertedSet]].location == NSNotFound &&
           ![value hasPrefix:@"."] && ![value hasSuffix:@"."] && ![value containsString:@".."];
}
BOOL PXHexTokenIsValid(id value) {
    return [value isKindOfClass:NSString.class] && [value length] >= 2 && [value length] <= 1024 &&
           [value length] % 2 == 0 && [value rangeOfCharacterFromSet:
           [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location == NSNotFound;
}
NSArray<NSString *> *PXValidatedRelativePaths(id value, NSError **error) {
    if (error) *error = nil;
    if (![value isKindOfClass:NSArray.class]) { Fail(error,@"保留规则必须是路径数组"); return nil; }
    NSMutableOrderedSet *paths = [NSMutableOrderedSet orderedSet];
    for (id path in value) {
        if (![path isKindOfClass:NSString.class] || ![path length] || [path isAbsolutePath] ||
            [path containsString:@"\\"] || [path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
            [[path pathComponents] containsObject:@".."] || [[path pathComponents] containsObject:@"."]) {
            Fail(error,@"保留规则只接受沙盒内的相对路径"); return nil;
        }
        NSString *normalized = [path stringByStandardizingPath];
        if (![@[@"Documents",@"Library",@"tmp",@"SystemData"] containsObject:[normalized pathComponents].firstObject]) {
            Fail(error,@"保留路径必须位于 Documents、Library、tmp 或 SystemData"); return nil;
        }
        [paths addObject:normalized];
    }
    return paths.array;
}
NSDictionary *PXValidateRuntime(id value, NSError **error) {
    if (error) *error = nil;
    if (![value isKindOfClass:NSDictionary.class]) { Fail(error,@"runtime 必须是对象"); return nil; }
    NSDictionary *d = value;
    if (d[@"appVersions"]) {
        if (![d[@"appVersions"] isKindOfClass:NSDictionary.class]) { Fail(error,@"appVersions 必须是对象"); return nil; }
        for (id bundle in d[@"appVersions"]) {
            NSDictionary *versions=d[@"appVersions"][bundle];
            if (!PXValidBundleIdentifier(bundle) || ![versions isKindOfClass:NSDictionary.class]) { Fail(error,@"应用版本配置无效"); return nil; }
            for (NSString *key in @[@"version",@"build"]) if (versions[key] && (![versions[key] isKindOfClass:NSString.class] || ![versions[key] length] || [versions[key] length]>128)) { Fail(error,key); return nil; }
        }
    }
    NSSet *flags = [NSSet setWithArray:@[@"maskEnvironment",@"maskProxy",@"sdkCompatibility",
        @"trackingOverride",@"hideSimulatedLocation",@"deviceCheckOverride",
        @"sdkSuppressCollectors",@"sdkSuppressInitialization",@"sdkBlockRealmWrites",
        @"sdkSuppressAttribution",@"sdkRewriteMetadata"]];
    for (NSString *key in flags) if (d[key] && (!Number(d[key],0,1) || [d[key] doubleValue]!=[d[key] integerValue])) { Fail(error,key); return nil; }
    NSDictionary *ranges = @{@"outputVolume":@[@0,@1],@"trackingStatus":@[@0,@3],
        @"interfaceOrientation":@[@0,@6],@"timeSinceLastLaunch":@[@(-1),@1e9],
        @"screenTopInset":@[@0,@200],@"screenBottomInset":@[@0,@200],
        @"gpuWorkingSetSize":@[@0,@(1ULL<<40)],@"gpuRaytracing":@[@0,@1]};
    for (NSString *key in ranges) if (d[key] && !Number(d[key],[ranges[key][0] doubleValue],[ranges[key][1] doubleValue])) {
        Fail(error,[key stringByAppendingString:@" 超出允许范围"]); return nil;
    }
    if (d[@"trackingStatus"] && [d[@"trackingStatus"] doubleValue] != [d[@"trackingStatus"] integerValue]) {
        Fail(error,@"trackingStatus 必须是 0–3 的整数"); return nil;
    }
    if (d[@"interfaceOrientation"] && [d[@"interfaceOrientation"] doubleValue] != [d[@"interfaceOrientation"] integerValue]) {
        Fail(error,@"interfaceOrientation 必须是整数"); return nil;
    }
    for (NSString *key in @[@"timeZoneName",@"openUDID",@"pushTokenHex"]) {
        if (d[key] && (![d[key] isKindOfClass:NSString.class] || [d[key] length] > 1024)) { Fail(error,key); return nil; }
    }
    if ([d[@"timeZoneName"] length] && ![NSTimeZone timeZoneWithName:d[@"timeZoneName"]]) { Fail(error,@"时区名称无效"); return nil; }
    if ([d[@"pushTokenHex"] length] && !PXHexTokenIsValid(d[@"pushTokenHex"])) { Fail(error,@"推送 token 必须是偶数长度十六进制"); return nil; }
    if (d[@"location"]) {
        NSDictionary *l = d[@"location"];
        if (![l isKindOfClass:NSDictionary.class] || !Number(l[@"latitude"],-90,90) || !Number(l[@"longitude"],-180,180)) {
            Fail(error,@"经纬度无效"); return nil;
        }
        NSDictionary *limits=@{@"altitude":@[@(-12000),@100000],@"horizontalAccuracy":@[@0,@100000],
            @"verticalAccuracy":@[@0,@100000],@"speed":@[@(-1),@10000],@"course":@[@(-1),@360]};
        for (NSString *key in limits) if (l[key] && !Number(l[key],[limits[key][0] doubleValue],[limits[key][1] doubleValue])) {
            Fail(error,key); return nil;
        }
        for (NSString *key in @[@"name",@"country",@"ISOcountryCode",@"locality",@"subLocality",@"thoroughfare",@"subThoroughfare",@"postalCode",@"administrativeArea"]) {
            if (l[key] && (![l[key] isKindOfClass:NSString.class] || [l[key] length]>512)) { Fail(error,key); return nil; }
        }
    }
    if (![NSJSONSerialization isValidJSONObject:d]) { Fail(error,@"参数不能序列化"); return nil; }
    return [d copy];
}
NSDictionary *PXValidateOptions(id value, NSError **error) {
    if (error) *error=nil;
    if (![value isKindOfClass:NSDictionary.class]) { Fail(error,@"options 必须是对象"); return nil; }
    NSDictionary *d=value;
    for (NSString *key in @[@"models",@"versions",@"carriers"]) {
        if (!d[key]) continue;
        if (![d[key] isKindOfClass:NSArray.class]) { Fail(error,key); return nil; }
        for (id s in d[key]) if (![s isKindOfClass:NSString.class] || ![s length] || [s length]>255) { Fail(error,key); return nil; }
    }
    for (NSString *key in @[@"wifiPercent",@"fiveGPercent"]) if (d[key] && !Number(d[key],0,100)) { Fail(error,key); return nil; }
    for (NSString *key in @[@"useLocalModelOS",@"requireRealRAM",@"clearPasteboardOnNewPhone",@"clearPasteboardOnSwitch",@"stopAtLastProfile",@"clearRelatedContainers",@"fallbackRandomIDFA",@"backupKeychain"]) {
        if (d[key] && !Number(d[key],0,1)) { Fail(error,key); return nil; }
    }
    if (d[@"versionWeights"]) {
        if (![d[@"versionWeights"] isKindOfClass:NSDictionary.class]) { Fail(error,@"版本权重必须是对象"); return nil; }
        double total=0;
        for (id k in d[@"versionWeights"]) {
            if (![k isKindOfClass:NSString.class] || !Number(d[@"versionWeights"][k],0,1000000)) { Fail(error,@"版本权重无效"); return nil; }
            total += [d[@"versionWeights"][k] doubleValue];
        }
        if (total<=0) { Fail(error,@"版本权重合计必须大于 0"); return nil; }
    }
    if (d[@"preservedPaths"] && !PXValidatedRelativePaths(d[@"preservedPaths"],error)) return nil;
    if (d[@"runtimeTemplate"] && !PXValidateRuntime(d[@"runtimeTemplate"],error)) return nil;
    if (d[@"idfaEndpoint"]) {
        if (![d[@"idfaEndpoint"] isKindOfClass:NSString.class]) { Fail(error,@"IDFA 地址无效"); return nil; }
        NSURL *url=[NSURL URLWithString:d[@"idfaEndpoint"]];
        if ([d[@"idfaEndpoint"] length] && (![url.scheme.lowercaseString isEqual:@"https"] || !url.host.length || url.user || url.password)) {
            Fail(error,@"IDFA 服务地址必须是 HTTPS"); return nil;
        }
    }
    return [d copy];
}
NSDictionary *PXValidatePhoneDictionary(id value, NSError **error) {
    if (error) *error=nil;
    if (![value isKindOfClass:NSDictionary.class] || ![value count] || ![NSJSONSerialization isValidJSONObject:value]) {
        Fail(error,@"设备参数必须是非空 JSON 对象"); return nil;
    }
    NSDictionary *d=value;
    for (NSString *k in @[@"idfa",@"idfv"]) if (![d[k] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:d[k]]) { Fail(error,k); return nil; }
    for (NSString *k in @[@"deviceName",@"serialNumber",@"IMEI",@"MEID",@"systemBootUUID",@"dyldCacheUUID",@"pasteboardUUID",@"keychainUUID",@"userDefaultsUUID",@"appGroupUUID",@"coreDataUUID",@"appInstallUUID",@"appContainerUUID"]) {
        if (d[k] && ![d[k] isKindOfClass:NSString.class]) { Fail(error,k); return nil; }
    }
    for (NSString *k in @[@"iosVersion",@"storageInfo",@"batteryInfo",@"wifiInfo",@"deviceModel",@"upTimeInfo",@"networkInfo"]) {
        if (d[k] && ![d[k] isKindOfClass:NSDictionary.class]) { Fail(error,k); return nil; }
    }
    NSDictionary *strings=@{
        @"iosVersion":@[@"version",@"build",@"kernelVersion",@"darwin"],
        @"storageInfo":@[@"totalStorage",@"freeStorage",@"filesystemType"],
        @"batteryInfo":@[@"batteryLevel"],
        @"wifiInfo":@[@"ssid",@"bssid",@"networkType",@"wifiStandard",@"lastConnectionTime"],
        @"deviceModel":@[@"modelName",@"name",@"resolution",@"viewportResolution",@"cpuArchitecture",@"hwModel",@"gpuFamily"],
        @"upTimeInfo":@[@"bootTime"],
        @"networkInfo":@[@"carrierName",@"mcc",@"mnc",@"localIPv6Address",@"localIPAddress",@"countryCode",@"radioAccessTechnology"]};
    for (NSString *section in strings) for (NSString *key in strings[section]) {
        id item=d[section][key];
        if (item && ![item isKindOfClass:NSString.class]) { Fail(error,[NSString stringWithFormat:@"%@.%@ 必须是文本",section,key]); return nil; }
    }
    NSDictionary *numbers=@{@"batteryInfo":@[@"batteryPercentage"],@"wifiInfo":@[@"autoJoin"],
        @"deviceModel":@[@"devicePixelRatio",@"screenDensity",@"deviceMemory",@"physicalMemoryBytes",@"cpuCoreCount"],
        @"upTimeInfo":@[@"upTime",@"bootTimeEpoch"],@"networkInfo":@[@"connectionType"]};
    for (NSString *section in numbers) for (NSString *key in numbers[section]) {
        id item=d[section][key];
        if (item && !Number(item,0,1e15)) { Fail(error,[NSString stringWithFormat:@"%@.%@ 必须是有限非负数",section,key]); return nil; }
    }
    NSDictionary *bounded=@{@"deviceModel":@{@"devicePixelRatio":@8,@"screenDensity":@2000,@"deviceMemory":@1024,
        @"physicalMemoryBytes":@(1ULL<<40),@"cpuCoreCount":@256},@"networkInfo":@{@"connectionType":@3},
        @"wifiInfo":@{@"autoJoin":@1},@"batteryInfo":@{@"batteryPercentage":@100}};
    for (NSString *section in bounded) for (NSString *key in bounded[section]) {
        id item=d[section][key];
        if (item && [item doubleValue]>[bounded[section][key] doubleValue]) { Fail(error,[NSString stringWithFormat:@"%@.%@ 超出范围",section,key]); return nil; }
    }
    for (NSArray *path in @[@[@"deviceModel",@"cpuCoreCount"],@[@"networkInfo",@"connectionType"],@[@"wifiInfo",@"autoJoin"]]) {
        id item=d[path[0]][path[1]];
        if (item && [item doubleValue]!=[item longLongValue]) { Fail(error,@"核心数量、网络类型和开关必须是整数"); return nil; }
    }
    id web=d[@"deviceModel"][@"webGLInfo"];
    if (web) {
        if (![web isKindOfClass:NSDictionary.class]) { Fail(error,@"webGLInfo 必须是对象"); return nil; }
        for (NSString *key in @[@"unmaskedVendor",@"unmaskedRenderer",@"webglVendor",@"webglRenderer",@"webglVersion"]) if (web[key] && ![web[key] isKindOfClass:NSString.class]) { Fail(error,key); return nil; }
        for (NSString *key in @[@"maxTextureSize",@"maxRenderBufferSize"]) if (web[key] && !Number(web[key],0,1e9)) { Fail(error,key); return nil; }
    }
    if (d[@"runtime"] && !PXValidateRuntime(d[@"runtime"],error)) return nil;
    return [d copy];
}
