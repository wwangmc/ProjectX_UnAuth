#import "PXURLCommand.h"
#import "PXConfiguration.h"
#import <math.h>
NSDictionary *PXParseCommandURL(NSURL *url,NSError **error) {
    if (error) *error=nil;
    if (![@[@"projectx",@"weaponx"] containsObject:url.scheme.lowercaseString] || ![url.host.lowercaseString isEqual:@"cmd"]) {
        if (error) *error=PXError(@"命令 URL 的 scheme 或 host 无效"); return nil;
    }
    NSURLComponents *components=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary *p=[NSMutableDictionary dictionary];
    for (NSURLQueryItem *q in components.queryItems) {
        if (!q.name.length || !q.value || p[q.name]) { if (error) *error=PXError(@"命令参数缺失或重复"); return nil; }
        p[q.name]=q.value;
    }
    NSString *operation=[components.path hasPrefix:@"/"]?[components.path substringFromIndex:1]:components.path;
    NSDictionary *aliases=@{@"newPhone":@"newPhone",@"nextBackupData":@"navigateProfile",@"preBackupData":@"navigateProfile",
        @"activeFirstBackupData":@"navigateProfile",@"activeLastBackupData":@"navigateProfile",
        @"activeBackupDataByName":@"switchProfile",@"deleteBackupDataByName":@"deleteProfileByName",
        @"getAllBackupDataNames":@"listProfiles",@"cleanAllBackupData":@"deleteInactiveProfiles",
        @"renameCurrentBackupData":@"renameProfile",@"modifyIdfa":@"modifyIdentifier",@"newIDFA":@"randomIDFA",
        @"setDisableTime":@"disableProfileByName",@"exportPara":@"exportParameters",@"importPara":@"importParameters",
        @"setAppVersion":@"setAppVersion",@"clearPasteboard":@"clearPasteboard",@"clearSafari":@"clearSafari",@"updatepara":@"updateParameters",
        @"listProfiles":@"listProfiles",@"getSettings":@"getSettings"};
    NSString *command=aliases[operation];
    if (!command) { if (error) *error=PXError(@"未支持的 URL 命令"); return nil; }
    NSDictionary *navigation=@{@"nextBackupData":@"next",@"preBackupData":@"previous",@"activeFirstBackupData":@"first",@"activeLastBackupData":@"last"};
    if (navigation[operation]) p[@"operation"]=navigation[operation];
    if (p[@"time"] && [command isEqual:@"disableProfileByName"]) {
        NSScanner *scanner=[NSScanner scannerWithString:p[@"time"]]; double hours=0;
        if (![scanner scanDouble:&hours] || !scanner.isAtEnd || !isfinite(hours) || hours<0 || hours>876000) { if (error) *error=PXError(@"禁用时间无效"); return nil; }
        p[@"hours"]=@(hours); [p removeObjectForKey:@"time"];
    }
    return @{@"command":command,@"parameters":p};
}
