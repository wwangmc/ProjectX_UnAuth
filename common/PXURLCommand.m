#import "PXURLCommand.h"
#import "PXConfiguration.h"
#import <math.h>

BOOL PXIsGPTCommandURL(NSURL *url) {
    return [url.scheme.lowercaseString isEqualToString:@"gpt"] && [url.host.lowercaseString isEqualToString:@"cmd"];
}

static NSDictionary *InvalidCommand(NSError **error, NSString *message) {
    if (error) *error = PXError(message);
    return nil;
}

NSDictionary *PXParseCommandURL(NSURL *url, NSError **error) {
    if (error) *error = nil;
    BOOL gpt = PXIsGPTCommandURL(url);
    if (!gpt && (![@[@"projectx", @"weaponx"] containsObject:url.scheme.lowercaseString] ||
                 ![url.host.lowercaseString isEqualToString:@"cmd"])) {
        return InvalidCommand(error, @"命令 URL 的 scheme 或 host 无效");
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components || (gpt && (components.user || components.password || components.port || components.fragment))) {
        return InvalidCommand(error, @"命令 URL 格式无效");
    }
    NSString *path = components.path;
    NSString *operation = [path hasPrefix:@"/"] ? [path substringFromIndex:1] : (path ?: @"");
    NSDictionary *navigation = @{@"nextBackupData": @"next", @"preBackupData": @"previous",
        @"activeFirstBackupData": @"first", @"activeLastBackupData": @"last"};
    NSDictionary *aliases = @{@"newPhone": @"newPhone", @"activeBackupDataByName": @"switchProfile",
        @"deleteBackupDataByName": @"deleteProfileByName", @"getAllBackupDataNames": @"listProfiles",
        @"cleanAllBackupData": @"deleteInactiveProfiles", @"renameCurrentBackupData": @"renameProfile",
        @"modifyIdfa": @"modifyIdentifier", @"newIDFA": @"randomIDFA", @"setDisableTime": @"disableProfileByName",
        @"exportPara": @"exportParameters", @"importPara": @"importParameters", @"setAppVersion": @"setAppVersion",
        @"updatepara": @"updateParameters"};
    NSDictionary *projectXOnly = @{@"clearPasteboard": @"clearPasteboard", @"clearSafari": @"clearSafari",
        @"listProfiles": @"listProfiles", @"getSettings": @"getSettings"};
    NSString *direction = navigation[operation];
    NSString *command = direction ? @"navigateProfile" : aliases[operation];
    if (!command) command = gpt ? ([operation isEqualToString:@"open"] ? @"open" : nil) : projectXOnly[operation];
    if (!command) return InvalidCommand(error, @"未支持的 URL 命令");

    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        if (!item.name.length || !item.value || parameters[item.name]) {
            return InvalidCommand(error, @"命令参数缺失或重复");
        }
        parameters[item.name] = item.value;
    }
    if (gpt) {
        NSDictionary<NSString *, NSArray<NSString *> *> *queryKeys = @{
            @"newPhone": @[@"version"], @"switchProfile": @[@"name"], @"deleteProfileByName": @[@"name"],
            @"renameProfile": @[@"name"], @"disableProfileByName": @[@"name", @"time"],
            @"modifyIdentifier": @[@"idfa", @"idfv"], @"setAppVersion": @[@"bundleID", @"version", @"build"],
            @"updateParameters": @[@"model", @"OSVersion"]};
        NSArray<NSString *> *allowed = queryKeys[command] ?: @[];
        for (NSString *key in parameters) {
            if (![allowed containsObject:key]) return InvalidCommand(error, @"命令含有未支持的参数");
            NSString *value = parameters[key];
            if ([value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
                return InvalidCommand(error, @"命令参数含有控制字符");
            }
        }
        BOOL modifiesIdentifier = [command isEqualToString:@"modifyIdentifier"];
        if (modifiesIdentifier && (parameters.count != 1 || ![[NSUUID alloc] initWithUUIDString:parameters.allValues.firstObject ?: @""])) {
            return InvalidCommand(error, @"请提供一个有效的 idfa 或 idfv");
        }
        if (!modifiesIdentifier && ![command isEqualToString:@"newPhone"]) {
            for (NSString *key in allowed) {
                if (![parameters[key] length]) return InvalidCommand(error, @"命令缺少必填参数");
            }
        }
        if ([command isEqualToString:@"exportParameters"] || [command isEqualToString:@"importParameters"]) {
            parameters[@"gptTransfer"] = @YES;
        }
        if (modifiesIdentifier || [command isEqualToString:@"randomIDFA"]) parameters[@"returnIdentifiers"] = @YES;
    }

    if (direction) parameters[@"operation"] = direction;
    if ([command isEqualToString:@"disableProfileByName"] && parameters[@"time"]) {
        NSScanner *scanner = [NSScanner scannerWithString:parameters[@"time"]];
        double hours = 0;
        if (![scanner scanDouble:&hours] || !scanner.isAtEnd || !isfinite(hours) || hours < 0 || hours > 876000) {
            return InvalidCommand(error, @"禁用时间无效");
        }
        parameters[@"hours"] = @(hours);
        [parameters removeObjectForKey:@"time"];
    }
    return @{@"command": command, @"parameters": parameters};
}
