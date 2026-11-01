#import "PXCommandRouter.h"
#import "PXURLCommand.h"
#import "DaemonApiManager.h"
@implementation PXCommandRouter
+ (BOOL)handleURL:(NSURL *)url {
    NSError *error=nil; NSDictionary *request=PXParseCommandURL(url,&error);
    if (!request) return NO;
    [[DaemonApiManager sharedManager] executeCommand:request[@"command"] parameters:request[@"parameters"] completion:^(id result,NSError *failure) {
        NSDictionary *response=failure?@{@"status":@"error",@"message":failure.localizedDescription ?: @"操作失败"}:@{@"status":@"success",@"data":result ?: NSNull.null};
        NSString *directory=@"/private/var/mobile/Media/ProjectX";
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSData *data=[NSJSONSerialization dataWithJSONObject:response options:NSJSONWritingPrettyPrinted error:NULL];
        [data writeToFile:[directory stringByAppendingPathComponent:@"command-result.json"] options:NSDataWritingAtomic error:NULL];
        dispatch_async(dispatch_get_main_queue(),^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"ProjectXCommandFinished" object:nil userInfo:response]; });
    }];
    return YES;
}
@end
