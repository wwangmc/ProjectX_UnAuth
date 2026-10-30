#import "HttpRequest.h"

static NSString *const PXDaemonURL = @"http://127.0.0.1:8888";

static NSURLSession *PXHTTPSession(void) {
    static NSURLSession *session;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.connectionProxyDictionary = @{};
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        config.timeoutIntervalForRequest = 10;
        config.timeoutIntervalForResource = 15;
        session = [NSURLSession sessionWithConfiguration:config];
    });
    return session;
}

static NSError *PXNetworkError(NSInteger code, NSString *message, NSDictionary *details) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
    info[NSLocalizedDescriptionKey] = message;
    return [NSError errorWithDomain:@"NetworkError" code:code userInfo:info];
}

// JSON does not support sets. Normalize nested containers before serialization.
static id PXJSONValue(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (id key in value) result[[key description]] = PXJSONValue(value[key]);
        return result;
    }
    if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSSet class]]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id item in value) [result addObject:PXJSONValue(item)];
        return result;
    }
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSNull class]]) return value;
    return [value description] ?: @"";
}

static NSString *PXFormComponent(id value) {
    static NSCharacterSet *allowed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    });
    return [[value description] stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

static NSData *PXFormBody(NSDictionary *parameters) {
    NSMutableArray *parts = [NSMutableArray array];
    for (id key in parameters) {
        id value = parameters[key];
        if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSSet class]]) {
            for (id item in value) {
                NSString *arrayKey = [[key description] stringByAppendingString:@"[]"];
                [parts addObject:[NSString stringWithFormat:@"%@=%@", PXFormComponent(arrayKey), PXFormComponent(item)]];
            }
        } else {
            [parts addObject:[NSString stringWithFormat:@"%@=%@", PXFormComponent(key), PXFormComponent(value)]];
        }
    }
    return [[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
}

static void PXSendRequest(NSString *urlString, NSString *method, id parameters,
                          NSDictionary *headers, RequestCompletionHandler completion) {
    NSURL *url = [urlString isKindOfClass:[NSString class]] ? [NSURL URLWithString:urlString] : nil;
    NSString *scheme = url.scheme.lowercaseString;
    if (!url.host.length || (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])) {
        if (completion) completion(nil, PXNetworkError(-1, @"Invalid HTTP URL", nil));
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    request.timeoutInterval = 10;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [headers enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [request setValue:[value description] forHTTPHeaderField:[key description]];
    }];
    if (parameters && ![method isEqualToString:@"GET"]) {
        id normalized = PXJSONValue(parameters);
        if ([NSJSONSerialization isValidJSONObject:normalized]) {
            NSError *error = nil;
            request.HTTPBody = [NSJSONSerialization dataWithJSONObject:normalized options:0 error:&error];
            if (!request.HTTPBody) {
                if (completion) completion(nil, error ?: PXNetworkError(-3, @"Invalid JSON parameters", nil));
                return;
            }
            [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        } else {
            NSDictionary *form = [parameters isKindOfClass:[NSDictionary class]] ? parameters : @{@"data": parameters};
            request.HTTPBody = PXFormBody(form);
            [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        }
    }
    [[PXHTTPSession() dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        id body = nil;
        if (data.length) {
            body = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:NULL];
            if (!body) body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: data;
        }
        if (status < 200 || status >= 300) {
            NSMutableDictionary *details = [NSMutableDictionary dictionaryWithObject:@(status) forKey:@"statusCode"];
            if (body) details[@"responseData"] = body;
            if (completion) completion(nil, PXNetworkError(status, [NSString stringWithFormat:@"HTTP %ld", (long)status], details));
            return;
        }
        if (completion) completion(body ?: @{@"status": @"success", @"code": @(status)}, nil);
    }] resume];
}

void daemonGET(NSString *path, RequestCompletionHandler completion) {
    sendGETRequest([PXDaemonURL stringByAppendingString:path], completion);
}
void sendGETRequest(NSString *url, RequestCompletionHandler completion) {
    PXSendRequest(url, @"GET", nil, nil, completion);
}
void daemonPOST(NSString *path, id parameters, RequestCompletionHandler completion) {
    sendPOSTRequest([PXDaemonURL stringByAppendingString:path], parameters, nil, completion);
}
void sendPOSTRequest(NSString *url, id parameters, NSDictionary *headers, RequestCompletionHandler completion) {
    PXSendRequest(url, @"POST", parameters, headers, completion);
}
void sendPUTRequest(NSString *url, id parameters, NSDictionary *headers, RequestCompletionHandler completion) {
    PXSendRequest(url, @"PUT", parameters, headers, completion);
}
void sendDELETERequest(NSString *url, id parameters, NSDictionary *headers, RequestCompletionHandler completion) {
    PXSendRequest(url, @"DELETE", parameters, headers, completion);
}
void sendPATCHRequest(NSString *url, id parameters, NSDictionary *headers, RequestCompletionHandler completion) {
    PXSendRequest(url, @"PATCH", parameters, headers, completion);
}
