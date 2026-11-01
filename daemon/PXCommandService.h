#import <Foundation/Foundation.h>
@interface PXCommandService : NSObject
+ (instancetype)sharedService;
- (id)perform:(NSString *)command parameters:(NSDictionary *)parameters error:(NSError **)error;
@end
