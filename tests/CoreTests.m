#import <Foundation/Foundation.h>
#import "HttpRequest.h"
#import "ProfileManager.h"
#import "RequestValidation.h"

static NSUInteger checks;
#define CHECK(condition) do { checks++; if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); exit(1); \
} } while (0)

@interface FailingProfileManager : ProfileManager
@property (nonatomic) BOOL failWrites;
@end
@implementation FailingProfileManager
- (BOOL)saveData { return !self.failWrites && [super saveData]; }
@end

static NSData *JSONData(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; }

static NSDictionary *Request(NSString *method, NSString *url, id parameters) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block id body;
    __block NSError *failure;
    RequestCompletionHandler completion = ^(id response, NSError *error) {
        body = response;
        failure = error;
        dispatch_semaphore_signal(done);
    };
    if ([method isEqualToString:@"GET"]) sendGETRequest(url, completion);
    else if ([method isEqualToString:@"PUT"]) sendPUTRequest(url, parameters, nil, completion);
    else if ([method isEqualToString:@"PATCH"]) sendPATCHRequest(url, parameters, nil, completion);
    else if ([method isEqualToString:@"DELETE"]) sendDELETERequest(url, parameters, nil, completion);
    else sendPOSTRequest(url, parameters, nil, completion);
    CHECK(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    return @{@"body": body ?: [NSNull null], @"error": failure ?: [NSNull null]};
}

static void TestHTTP(NSString *base) {
    NSDictionary *result = Request(@"GET", [base stringByAppendingString:@"/json"], nil);
    CHECK([result[@"body"][@"ok"] boolValue]);
    CHECK(result[@"error"] == [NSNull null]);
    result = Request(@"GET", [base stringByAppendingString:@"/empty"], nil);
    CHECK([result[@"body"][@"code"] integerValue] == 204);
    for (NSString *endpoint in @[@"/failure", @"/empty-failure"]) {
        result = Request(@"GET", [base stringByAppendingString:endpoint], nil);
        CHECK(result[@"body"] == [NSNull null]);
        CHECK([result[@"error"] isKindOfClass:[NSError class]]);
        CHECK([result[@"error"] code] == ([endpoint isEqualToString:@"/failure"] ? 500 : 403));
    }
    result = Request(@"GET", [base stringByAppendingString:@"/text"], nil);
    CHECK([result[@"body"] isEqual:@"plain response"]);
    result = Request(@"GET", @"relative/path", nil);
    CHECK([result[@"error"] isKindOfClass:[NSError class]]);
    result = Request(@"GET", @"file:///tmp/file", nil);
    CHECK([result[@"error"] isKindOfClass:[NSError class]]);
    for (NSString *method in @[@"POST", @"PUT", @"PATCH", @"DELETE"]) {
        result = Request(method, [base stringByAppendingString:@"/echo"],
                         @{@"apps": [NSSet setWithObjects:@"a", @"b", nil]});
        CHECK([NSSet setWithArray:result[@"body"][@"apps"]].count == 2);
        CHECK(result[@"error"] == [NSNull null]);
    }
    result = Request(@"POST", [base stringByAppendingString:@"/echo"], @"a&b=c+d 中文");
    CHECK([result[@"body"][@"data"] isEqual:@[@"a&b=c+d 中文"]]);
    // Repeated requests exercise reuse after both successful and failed tasks.
    for (NSUInteger i = 0; i < 20; i++) {
        result = Request(@"GET", [base stringByAppendingString:@"/json"], nil);
        CHECK([result[@"body"][@"ok"] boolValue]);
    }
    result = Request(@"GET", @"http://127.0.0.1:1/unreachable", nil);
    CHECK([result[@"error"] isKindOfClass:[NSError class]]);
}

static void TestRequestValidation(void) {
    NSError *error = nil;
    CHECK(PXDictionaryFromJSONData(JSONData(@"{}"), &error) != nil && !error);
    for (NSString *invalid in @[@"", @"[1]", @"null", @"{"]) {
        CHECK(PXDictionaryFromJSONData(JSONData(invalid), &error) == nil && error != nil);
    }
    CHECK(PXStringSetFromJSONData(JSONData(@"[]"), &error).count == 0 && !error);
    CHECK(PXStringSetFromJSONData(JSONData(@"[\"a\",\"a\",\"b\"]"), &error).count == 2 && !error);
    for (NSString *invalid in @[@"{}", @"[null]", @"[1]", @"[\"\"]", @"["]) {
        CHECK(PXStringSetFromJSONData(JSONData(invalid), &error) == nil && error != nil);
    }
    CHECK(PXDictionaryFromJSONData(nil, NULL) == nil);
}

static void TestProfiles(NSString *directory) {
    NSFileManager *files = [NSFileManager defaultManager];
    ProfileManager *manager = [[ProfileManager alloc] initWithDataDirectory:directory];
    CHECK([manager genBackupDirectory] != nil);
    NSString *firstId = manager.currentId;
    CHECK([manager genBackupDirectory] != nil);
    CHECK(![firstId isEqualToString:manager.currentId]);
    ProfileManager *reloaded = [[ProfileManager alloc] initWithDataDirectory:directory];
    CHECK(reloaded.mutableProfiles.count == 2);
    CHECK([reloaded.currentId isEqualToString:manager.currentId]);
    CHECK(![reloaded removeProfileById:reloaded.currentId]);
    CHECK([reloaded removeProfileById:firstId]);
    NSString *path = [directory stringByAppendingPathComponent:@"profiles.json"];
    for (NSString *bad in @[@"[]", @"{", @"{\"mutableProfiles\":[null]}",
                            @"{\"mutableProfiles\":[{\"id\":\"../escape\"}]}"]) {
        CHECK([JSONData(bad) writeToFile:path atomically:YES]);
        CHECK(![reloaded loadData]);
        CHECK(reloaded.mutableProfiles.count == 1);
    }
    CHECK([reloaded saveData]);
    CHECK([reloaded clearData]);
    CHECK(![files fileExistsAtPath:path]);
    CHECK(reloaded.mutableProfiles.count == 0 && reloaded.currentId == nil);
    CHECK([reloaded clearData]);

    FailingProfileManager *failure = [[FailingProfileManager alloc]
        initWithDataDirectory:[directory stringByAppendingPathComponent:@"rollback"]];
    CHECK([failure genBackupDirectory] != nil);
    Profile *old = failure.mutableProfiles.firstObject;
    CHECK([failure genBackupDirectory] != nil);
    NSString *current = failure.currentId;
    failure.failWrites = YES;
    CHECK([failure genBackupDirectory] == nil);
    CHECK(failure.mutableProfiles.count == 2 && [failure.currentId isEqualToString:current]);
    CHECK(![failure removeProfileById:old.id] && failure.mutableProfiles.count == 2);
    NSString *oldName = old.name;
    CHECK(![failure renameProfile:old.id to:@"changed"]);
    CHECK([old.name isEqualToString:oldName]);
    CHECK(![failure switchToProfile:old]);
    CHECK([failure.currentId isEqualToString:current]);
    NSMutableSet *ids = [NSMutableSet set];
    for (NSUInteger i = 0; i < 1000; i++) [ids addObject:[manager generateProfileID]];
    CHECK(ids.count == 1000);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        CHECK(argc == 3);
        TestRequestValidation();
        TestProfiles([NSString stringWithUTF8String:argv[2]]);
        TestHTTP([NSString stringWithUTF8String:argv[1]]);
        printf("PASS: %lu checks\n", (unsigned long)checks);
    }
    return 0;
}
