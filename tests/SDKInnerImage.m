#import <Foundation/Foundation.h>
static int calls;
int PXSDKInnerInitializationCount(void) { return calls; }
@interface PXSDKInnerLoad : NSObject @end
@implementation PXSDKInnerLoad
+ (void)load { calls++; }
@end
