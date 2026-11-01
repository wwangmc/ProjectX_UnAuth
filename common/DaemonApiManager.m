#import "DaemonApiManager.h"
#import "HttpRequest.h"
#import "DaemonApi.h"

@implementation DaemonApiManager
- (void)executeCommand:(NSString *)command parameters:(NSDictionary *)parameters completion:(void(^)(id,NSError *))completion {
    daemonCommandPOST(EXECUTE_COMMAND,@{@"command":command,@"parameters":parameters ?: @{}},^(id response,NSError *error) {
        id details=error.userInfo[@"responseData"];
        if (error && [details isKindOfClass:NSDictionary.class] && [details[@"message"] isKindOfClass:NSString.class]) {
            NSMutableDictionary *info=[error.userInfo mutableCopy]; info[NSLocalizedDescriptionKey]=details[@"message"];
            error=[NSError errorWithDomain:error.domain code:error.code userInfo:info];
        }
        if (!error && (![response isKindOfClass:NSDictionary.class] || ![response[@"status"] isEqual:@"success"]))
            error=[NSError errorWithDomain:@"ProjectX" code:400 userInfo:@{NSLocalizedDescriptionKey:@"后台操作失败"}];
        if (completion) completion(error?nil:response[@"data"],error);
    });
}
+ (instancetype)sharedManager {
    static DaemonApiManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (NSMutableSet *)getScopeApps {
    // 创建一个 NSMutableSet，用于存储返回的数据
    __block NSMutableSet *scopeApps = [NSMutableSet set];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0); // 创建信号量
    daemonGET(GET_SCOPE_APPS,^(id jsonResponse, NSError *error) {
        if ([jsonResponse isKindOfClass:[NSDictionary class]]) {
            NSString *status = jsonResponse[@"status"];
            if ([status isEqualToString:@"success"]) {
                // 获取 data 字段并确保它是一个数组
                id data = jsonResponse[@"data"];
                if ([data isKindOfClass:[NSArray class]]) {
                    NSArray *dataArray = (NSArray *)data;
                    
                    // 将数组中的元素添加到 NSMutableSet
                    for (id app in dataArray) {
                        if (app) {
                            [scopeApps addObject:app];
                        }
                    }
                } 
            } else {
                NSLog(@"[ProjectXDaemon]success：%@", status);
            }
        }
        dispatch_semaphore_signal(semaphore); 
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return scopeApps;
}

- (void) saveScopeApps:(NSMutableSet *)apps{
    daemonPOST(SAVE_SCOPE_APPS, [apps allObjects], ^(id response, NSError *error) {
        // 处理响应
    });
}

- (PhoneInfo *) requestPhoneInfo{
    __block PhoneInfo *phoneInfo;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0); // 创建信号量
    daemonGET(GET_PHONE_INFO,^(id jsonResponse, NSError *error) {
        if ([jsonResponse isKindOfClass:[NSDictionary class]]) {
            phoneInfo = [PhoneInfo fromDictionary:jsonResponse];
        }
        dispatch_semaphore_signal(semaphore); 
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return phoneInfo;
}
- (BOOL) savePhoneInfo:(PhoneInfo *)phoneInfo{
    daemonPOST(SAVE_PHONE_INFO, [phoneInfo toDictionary], ^(id response, NSError *error) {
        // 处理响应
    });
    return YES;
}

- (void) newPhone:(void(^)(id response, NSError *error))completion{
    [self executeCommand:@"newPhone" parameters:@{} completion:^(id response, NSError *error) {
        // 如果有回调，执行回调
        if (completion) {
            completion(response, error);
        }
    }];
}

- (void) removeBackup:(Profile *)profile comp:(void(^)(id response, NSError *error))completion{
    [self executeCommand:@"deleteProfiles" parameters:@{@"ids":@[profile.id]} completion:^(id response, NSError *error) {
        // 如果有回调，执行回调
        if (completion) {
            completion(response, error);
        }
    }];
}

- (void) renameBackup:(Profile *)profile comp:(void(^)(id response, NSError *error))completion{
    [self executeCommand:@"renameProfile" parameters:[profile toDictionary] completion:^(id response, NSError *error) {
        // 如果有回调，执行回调
        if (completion) {
            completion(response, error);
        }
    }];
}

- (void) switchBackup:(Profile *)profile comp:(void(^)(id response, NSError *error))completion{
    [self executeCommand:@"switchProfile" parameters:[profile toDictionary] completion:^(id response, NSError *error) {
        // 如果有回调，执行回调
        if (completion) {
            completion(response, error);
        }
    }];
}
- (NSArray *) getAllCarrier{
    __block NSArray *dataArray = @[];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0); // 创建信号量
    daemonGET(GET_ALL_CARRIER,^(id jsonResponse, NSError *error) {
        if ([jsonResponse isKindOfClass:[NSDictionary class]]) {
            NSString *status = jsonResponse[@"status"];
            if ([status isEqualToString:@"success"]) {
                // 获取 data 字段并确保它是一个数组
                id data = jsonResponse[@"data"];
                if ([data isKindOfClass:[NSArray class]]) {
                    dataArray = (NSArray *)data;
                } 
            } else {
                NSLog(@"[ProjectXDaemon]success：%@", status);
            }
        }
        dispatch_semaphore_signal(semaphore); 
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return dataArray;
}
- (NSArray *) getAllVersions{
    __block NSArray *dataArray = @[];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0); // 创建信号量
    daemonGET(GET_ALL_VERSIONS,^(id jsonResponse, NSError *error) {
        if ([jsonResponse isKindOfClass:[NSDictionary class]]) {
            NSString *status = jsonResponse[@"status"];
            if ([status isEqualToString:@"success"]) {
                // 获取 data 字段并确保它是一个数组
                id data = jsonResponse[@"data"];
                if ([data isKindOfClass:[NSArray class]]) {
                    dataArray = (NSArray *)data;
                } 
            } else {
                NSLog(@"[ProjectXDaemon]success：%@", status);
            }
        }
        dispatch_semaphore_signal(semaphore); 
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return dataArray;
}
@end
