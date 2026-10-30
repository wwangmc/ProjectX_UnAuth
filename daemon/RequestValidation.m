#import "RequestValidation.h"

static id PXReadJSON(NSData *data, Class expectedClass, NSError **error) {
    if (error) *error = nil;
    if (data.length) {
        id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
        if ([value isKindOfClass:expectedClass]) return value;
        if (error && *error) return nil;
    }
    if (error) *error = [NSError errorWithDomain:@"ProjectXRequest" code:400
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON body type"}];
    return nil;
}

NSDictionary *PXDictionaryFromJSONData(NSData *data, NSError **error) {
    return PXReadJSON(data, [NSDictionary class], error);
}

NSMutableSet<NSString *> *PXStringSetFromJSONData(NSData *data, NSError **error) {
    NSArray *values = PXReadJSON(data, [NSArray class], error);
    if (!values) return nil;
    for (id value in values) {
        if (![value isKindOfClass:[NSString class]] || ![value length]) {
            if (error) *error = [NSError errorWithDomain:@"ProjectXRequest" code:400
                                              userInfo:@{NSLocalizedDescriptionKey: @"Expected non-empty application identifiers"}];
            return nil;
        }
    }
    return [NSMutableSet setWithArray:values];
}
