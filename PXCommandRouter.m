#import "PXCommandRouter.h"
#import "PXURLCommand.h"
#import "DaemonApiManager.h"

static NSString *const GPTResultPath = @"/var/mobile/gptresult.txt";

static BOOL WriteText(NSString *text, NSString *path, NSError **error) {
    return [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

static void WriteGPTStatus(NSString *status) {
    NSError *error = nil;
    if (!WriteText(status, GPTResultPath, &error)) {
        NSLog(@"[ProjectX] 无法写入 GPT 命令状态：%@", error.localizedDescription);
    }
}

static NSError *WriteGPTOutput(NSString *command, id result) {
    NSError *error = nil;
    if ([command isEqualToString:@"listProfiles"]) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSDictionary *profile in result[@"profiles"]) [names addObject:profile[@"name"]];
        WriteText([names componentsJoinedByString:@"\n"], @"/var/mobile/gptrecords.txt", &error);
    } else if ([command isEqualToString:@"modifyIdentifier"] || [command isEqualToString:@"randomIDFA"]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:&error];
        if (data) [data writeToFile:@"/var/mobile/gptrecordparam.txt" options:NSDataWritingAtomic error:&error];
    }
    return error;
}

static NSDictionary *WriteProjectXResult(id result, NSError *failure) {
    NSDictionary *response = failure ? @{@"status": @"error", @"message": failure.localizedDescription ?: @"操作失败"} :
        @{@"status": @"success", @"data": result ?: NSNull.null};
    NSString *directory = @"/private/var/mobile/Media/ProjectX";
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *data = [NSJSONSerialization dataWithJSONObject:response options:NSJSONWritingPrettyPrinted error:NULL];
    [data writeToFile:[directory stringByAppendingPathComponent:@"command-result.json"] options:NSDataWritingAtomic error:NULL];
    return response;
}

static void NotifyCommandFinished(NSDictionary *response) {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ProjectXCommandFinished" object:nil userInfo:response];
}

// The GPT scripts poll one shared status file, so finish each URL before starting the next.
static void EnqueueGPTCommand(NSDictionary *request, NSError *parseError) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static NSMutableArray<dispatch_block_t> *pending;
        if (!pending) pending = [NSMutableArray array];

        [pending addObject:^{
            NSString *command = request[@"command"];
            void (^finish)(id, NSError *) = ^(id result, NSError *failure) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *error = failure ?: WriteGPTOutput(command, result);
                    NSDictionary *response = WriteProjectXResult(result, error);
                    WriteGPTStatus(error ? @"0" : @"1");
                    NotifyCommandFinished(response);
                    [pending removeObjectAtIndex:0];
                    if (pending.count) dispatch_async(dispatch_get_main_queue(), pending.firstObject);
                });
            };
            if (parseError || [command isEqualToString:@"open"]) {
                finish(@YES, parseError);
                return;
            }
            WriteGPTStatus(@"2");
            [[DaemonApiManager sharedManager] executeCommand:command parameters:request[@"parameters"] completion:finish];
        }];
        if (pending.count == 1) {
            dispatch_block_t start = pending.firstObject;
            start();
        }
    });
}

@implementation PXCommandRouter
+ (BOOL)handleURL:(NSURL *)url {
    NSError *error = nil;
    NSDictionary *request = PXParseCommandURL(url, &error);
    if (PXIsGPTCommandURL(url)) {
        EnqueueGPTCommand(request, error);
        return request != nil;
    }
    if (!request) return NO;
    [[DaemonApiManager sharedManager] executeCommand:request[@"command"] parameters:request[@"parameters"] completion:^(id result, NSError *failure) {
        dispatch_async(dispatch_get_main_queue(), ^{ NotifyCommandFinished(WriteProjectXResult(result, failure)); });
    }];
    return YES;
}
@end
