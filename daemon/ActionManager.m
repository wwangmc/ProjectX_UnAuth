#import "ActionManager.h"
#import "PXCommandService.h"

@implementation ActionManager
+ (instancetype)sharedManager {
    static ActionManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager=[self new]; });
    return manager;
}
- (void)newPhone {
    NSError *error=nil;
    [[PXCommandService sharedService] perform:@"newPhone" parameters:@{} error:&error];
    if (error) NSLog(@"[ProjectX] newPhone failed: %@",error.localizedDescription);
}
- (void)switchBackup:(NSString *)identifier {
    NSError *error=nil;
    [[PXCommandService sharedService] perform:@"switchProfile" parameters:@{@"id":identifier ?: @""} error:&error];
    if (error) NSLog(@"[ProjectX] switch failed: %@",error.localizedDescription);
}
- (void)removeBackup:(NSString *)identifier {
    NSError *error=nil;
    [[PXCommandService sharedService] perform:@"deleteProfiles" parameters:@{@"ids":@[identifier ?: @""]} error:&error];
    if (error) NSLog(@"[ProjectX] delete failed: %@",error.localizedDescription);
}
@end
