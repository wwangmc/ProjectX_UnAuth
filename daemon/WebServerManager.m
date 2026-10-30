#import "WebServerManager.h"
#import <GCDWebServers/GCDWebsocketServer.h>
#import <GCDWebServers/GCDWebServerDataResponse.h>
#import <GCDWebServers/GCDWebServerDataRequest.h>
#import <GCDWebServers/GCDWebServerErrorResponse.h>
#import "AppScopeManager.h"
#import "PhoneInfo.h"
#import "DaemonApi.h"
#import "DataGenManager.h"
#import "ActionManager.h"
#import "ProfileManager.h"
#import "DBManager.h"
#import "RequestValidation.h"

GCDWebServerDataResponse* dataResponse(NSDictionary *jsonData)
{
    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:jsonData];
    [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
    [response setValue:@"Content-Type" forAdditionalHeader:@"Access-Control-Allow-Headers"];
    return response;
}
GCDWebServerDataResponse* staticSuccessResponse()
{
    NSDictionary *jsonData = @{
        @"status": @"success"
    };
    return dataResponse(jsonData);
}
GCDWebServerErrorResponse* missingParamResponse()
{
    GCDWebServerErrorResponse *response = [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest
                                                        message:@"Missing parameter"];
    [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
    [response setValue:@"Content-Type" forAdditionalHeader:@"Access-Control-Allow-Headers"];
    return response;
}
GCDWebServerErrorResponse* jsonFormatErrorResponse()
{
    GCDWebServerErrorResponse* response = [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest
                                                            message:@"Invalid JSON"];
    [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
    [response setValue:@"Content-Type" forAdditionalHeader:@"Access-Control-Allow-Headers"];
    return response;
}
@implementation WebServerManager

+(void) startWebServer{
    static GCDWebServer *webServer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        webServer = [[GCDWebServer alloc] init];
        [WebServerManager initHandle:webServer];
        [WebServerManager initDebugHandle:webServer];
        [webServer startWithPort:8888 bonjourName:nil];
    });
}
+(void) initDebugHandle:(GCDWebsocketServer *)webServer
{
    // [webServer addHandlerForMethod:@"GET"
    //                           path:@"/randomInfo"
    //                   requestClass:[GCDWebServerDataRequest class] // 必须是 DataRequest 才能读取 Body
    //                   processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {

    //     IosVersion * iosVersion = [[DataGenManager sharedManager] generateIOSVersion];
    //     return dataResponse([iosVersion toDictionary]);
    // }];
}
+(void) initHandle:(GCDWebsocketServer *)webServer
{
    [webServer addHandlerForMethod:@"GET"
                              path:NEW_PHONE
                      requestClass:[GCDWebServerDataRequest class] // 必须是 DataRequest 才能读取 Body
                      processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {

        [[ActionManager sharedManager] newPhone];
        NSMutableSet *scopeSet = [[AppScopeManager sharedManager] loadPreferences];
        return dataResponse(@{
            @"status": @"success",
            @"data": [scopeSet allObjects]
        });
    }];

    // 保存选中应用
    [webServer addHandlerForMethod:@"POST"
                              path:SAVE_SCOPE_APPS
                      requestClass:[GCDWebServerDataRequest class] // 必须是 DataRequest 才能读取 Body
                      processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {

        NSError *error = nil;
        NSMutableSet *scopeSet = PXStringSetFromJSONData(request.data, &error);
        if (!scopeSet) {
            return jsonFormatErrorResponse();
        }
        [[AppScopeManager sharedManager] savePreferences:scopeSet];
        return staticSuccessResponse();
    }];

    [webServer addHandlerForMethod:@"GET"
                              path:GET_SCOPE_APPS
                      requestClass:[GCDWebServerRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSMutableSet *scopeSet = [[AppScopeManager sharedManager] loadPreferences];

        return dataResponse(@{
            @"status": @"success",
            @"data": [scopeSet allObjects]
        });
    }];

    [webServer addHandlerForMethod:@"GET"
                              path:GET_PHONE_INFO
                      requestClass:[GCDWebServerRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        PhoneInfo * phoneInfo = [PhoneInfo loadFromPrefs];
        return dataResponse([phoneInfo toDictionary]);
    }];

    [webServer addHandlerForMethod:@"POST"
                              path:SAVE_PHONE_INFO
                   requestClass:[GCDWebServerDataRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request){

        NSError *error = nil;
        NSDictionary *dict = PXDictionaryFromJSONData(request.data, &error);
        if (!dict) {
            return jsonFormatErrorResponse();
        }

        BOOL success = [PhoneInfo saveDictionaryToPrefs:dict];
        if(success){
            return staticSuccessResponse();
        }else{
            return dataResponse(@{
                @"status": @"error"
            });
        }
    }];

    [webServer addHandlerForMethod:@"POST"
                              path:REMOVE_BACKUP
                        requestClass:[GCDWebServerDataRequest class]
                        processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request){
        NSError *error = nil;
        NSDictionary *dict = PXDictionaryFromJSONData(request.data, &error);
        if (!dict) {
            return jsonFormatErrorResponse();
        }
        if (![dict[@"id"] isKindOfClass:[NSString class]] || ![dict[@"id"] length]) return missingParamResponse();
        [[ActionManager sharedManager] removeBackup:dict[@"id"]];
        return staticSuccessResponse();
    }];
    [webServer addHandlerForMethod:@"POST"
                              path:RENAME_BACKUP
                        requestClass:[GCDWebServerDataRequest class]
                        processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request){
        NSError *error = nil;
        NSDictionary *dict = PXDictionaryFromJSONData(request.data, &error);
        if (!dict) {
            return jsonFormatErrorResponse();
        }
        if (![dict[@"id"] isKindOfClass:[NSString class]] || ![dict[@"id"] length]) return missingParamResponse();
        if (![dict[@"name"] isKindOfClass:[NSString class]] || ![dict[@"name"] length]) return missingParamResponse();
        if (![[ProfileManager sharedManager] renameProfile:dict[@"id"] to:dict[@"name"]]) {
            return [GCDWebServerErrorResponse responseWithClientError:409 message:@"Profile could not be saved"];
        }
        return staticSuccessResponse();
    }];

    [webServer addHandlerForMethod:@"POST"
                              path:SWITCH_BACKUP
                        requestClass:[GCDWebServerDataRequest class]
                        processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request){
        NSError *error = nil;
        NSDictionary *dict = PXDictionaryFromJSONData(request.data, &error);
        if (!dict) {
            return jsonFormatErrorResponse();
        }
        if (![dict[@"id"] isKindOfClass:[NSString class]] || ![dict[@"id"] length]) return missingParamResponse();
        [[ActionManager sharedManager] switchBackup:dict[@"id"]];
        return staticSuccessResponse();
    }];

    [webServer addHandlerForMethod:@"GET"
                              path:GET_ALL_CARRIER
                      requestClass:[GCDWebServerRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSArray<NSDictionary *> * data = [[DBManager sharedManager] query:@"select DISTINCT code from operator"];
         return dataResponse(@{
            @"status": @"success",
            @"data": [data valueForKey:@"code"]
        });
    }];

    [webServer addHandlerForMethod:@"GET"
                              path:GET_ALL_VERSIONS
                      requestClass:[GCDWebServerRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSArray<NSDictionary *> * data = [[DBManager sharedManager] query:@"select version from KMOS"];
        return dataResponse(@{
            @"status": @"success",
            @"data": [data valueForKey:@"version"]
        });
    }];

}
+(void) load{
    // 检查默认PhoneInf是否存在
    PhoneInfo * phoneInfo = [PhoneInfo loadFromPrefs];
    if(!phoneInfo){
        phoneInfo = [[DataGenManager sharedManager] generatePhoneInfo];
        [phoneInfo saveToPrefs];
    }
}
@end
