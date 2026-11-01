#import "BottomButtons.h"
#import <spawn.h>
#import <sys/wait.h>
#import <objc/runtime.h>
#import "LoadingView.h"
#import "DaemonApiManager.h"
@interface SBSRelaunchAction : NSObject
+ (id)actionWithReason:(id)arg1 options:(unsigned)arg2 targetURL:(id)arg3;
@end

@interface FBSSystemService : NSObject
+ (id)sharedService;
- (void)sendActions:(id)arg1 withResult:(/*^block*/id)arg2;
@end

@interface BottomButtons ()
@end

@implementation BottomButtons

+ (instancetype)sharedInstance {
    static BottomButtons *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {

    return self;
}

#pragma mark - App Termination

- (void)killAppViaExecutableName:(NSString *)bundleID {
    
    // Generate haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
    
    LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
    NSString *executableName = appProxy.bundleExecutable;
    
    if (executableName) {
        pid_t pid;
        int status;
        
        // Check for different killall paths based on jailbreak type
        NSArray *killallPaths = @[
            @"/var/jb/usr/bin/killall",  // Dopamine path
            @"/usr/bin/killall",         // Traditional/Palera1n path
            @"/var/jb/bin/killall"       // Alternative Dopamine path
        ];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *killallPath = nil;
        
        // Find the first available killall binary
        for (NSString *path in killallPaths) {
            if ([fileManager fileExistsAtPath:path]) {
                killallPath = path;
                break;
            }
        }
        
        if (!killallPath) {
            NSLog(@"[BottomButtons] Error: Could not find a valid killall binary path");
            return;
        }
        
        const char *killallPathStr = [killallPath UTF8String];
        const char *executableStr = [executableName UTF8String];
        char *const argv[] = {(char *)"killall", (char *)"-9", (char *)executableStr, NULL};
        
        if (posix_spawn(&pid, killallPathStr, NULL, NULL, argv, NULL) == 0) {
            waitpid(pid, &status, WEXITED);
            if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
                NSLog(@"[BottomButtons] Successfully killed app %@ via executable name: %@ using %@", 
                      bundleID, executableName, killallPath);
            } else {
                NSLog(@"[BottomButtons] Process exited with status %d for app %@", 
                      WEXITSTATUS(status), bundleID);
            }
        } else {
            NSLog(@"[BottomButtons] Failed to spawn killall for app %@ via executable name: %@", 
                  bundleID, executableName);
        }
    } else {
        NSLog(@"[BottomButtons] Could not find executable name for app: %@", bundleID);
    }
}

- (void)terminateApplicationWithBundleID:(NSString *)bundleID {
    if (!bundleID) {
        NSLog(@"[BottomButtons] Error: Invalid bundle ID");
        return;
    }

    // Method 1: Using FBSSystemService (Primary method)
    @try {
        SBSRelaunchAction *action = [SBSRelaunchAction actionWithReason:@"terminate" options:4 targetURL:nil];
        [[FBSSystemService sharedService] sendActions:[NSSet setWithObject:action] withResult:nil];
        NSLog(@"[BottomButtons] Successfully terminated app using FBSSystemService: %@", bundleID);
        return;
    } @catch (NSException *exception) {
        NSLog(@"[BottomButtons] FBSSystemService failed: %@", exception);
    }
    
    // Method 2: Using BKSProcessAssertion (Fallback for rootless)
    @try {
        pid_t pid;
        int status;
        
        // Check for different pidof paths based on jailbreak type
        NSArray *pidofPaths = @[
            @"/var/jb/usr/bin/pidof",    // Dopamine path
            @"/usr/bin/pidof",           // Traditional/Palera1n path
            @"/var/jb/bin/pidof"         // Alternative Dopamine path
        ];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *pidofPath = nil;
        
        // Find the first available pidof binary
        for (NSString *path in pidofPaths) {
            if ([fileManager fileExistsAtPath:path]) {
                pidofPath = path;
                break;
            }
        }
        
        if (!pidofPath) {
            NSLog(@"[BottomButtons] Error: Could not find a valid pidof binary path");
        } else {
            const char *argv[] = {"pidof", [bundleID UTF8String], NULL};
            if (posix_spawn(&pid, [pidofPath UTF8String], NULL, NULL, (char* const*)argv, NULL) == 0) {
                waitpid(pid, &status, WEXITED);
                
                if (WIFEXITED(status)) {
                    int appPID = WEXITSTATUS(status);
                    if (appPID > 0) {
                        __block BKSProcessAssertion *assertion = [[BKSProcessAssertion alloc] initWithPID:appPID 
                                                                                            flags:0
                                                                                        reason:1
                                                                                            name:@"Terminate"
                                                                                    withHandler:^(BOOL success) {
                            if (success) {
                                NSLog(@"[BottomButtons] Successfully terminated app with PID: %d", appPID);
                            } else {
                                NSLog(@"[BottomButtons] Failed to terminate app with PID: %d", appPID);
                            }
                        }];
                        
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            assertion = nil;
                        });
                        return;
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[BottomButtons] BKSProcessAssertion failed: %@", exception);
    }
    
    // Method 3: Using direct killall as a last resort
    @try {
        LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
        NSString *executableName = appProxy.bundleExecutable;
        
        if (executableName) {
            [self killAppViaExecutableName:bundleID];
            return;
        }
    } @catch (NSException *exception) {
        NSLog(@"[BottomButtons] killAppViaExecutableName failed: %@", exception);
    }
    
    // Method 4: Final fallback to FBSSystemService
    @try {
        SBSRelaunchAction *action = [SBSRelaunchAction actionWithReason:@"terminate" options:4 targetURL:nil];
        [[FBSSystemService sharedService] sendActions:[NSSet setWithObject:action] withResult:nil];
        NSLog(@"[BottomButtons] Final attempt at termination using FBSSystemService: %@", bundleID);
    } @catch (NSException *exception) {
        NSLog(@"[BottomButtons] Final FBSSystemService attempt failed: %@", exception);
    }
}

#pragma mark - UI Components

- (UIView *)createBottomButtonsView {
    UIView *containerView = [[UIView alloc] init];
    containerView.backgroundColor = [UIColor systemBackgroundColor];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add shadow and separator
    containerView.layer.shadowColor = [UIColor blackColor].CGColor;
    containerView.layer.shadowOffset = CGSizeMake(0, -2);
    containerView.layer.shadowOpacity = 0.1;
    containerView.layer.shadowRadius = 4;
    
    UIView *separator = [[UIView alloc] init];
    separator.backgroundColor = [UIColor separatorColor];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:separator];
    
    // Create horizontal stack view
    UIStackView *buttonStackView = [[UIStackView alloc] init];
    buttonStackView.axis = UILayoutConstraintAxisHorizontal;
    buttonStackView.distribution = UIStackViewDistributionFillEqually;
    buttonStackView.spacing = 8;
    buttonStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:buttonStackView];
    
    // Create kill button with soft minimalistic style
    UIButton *newPhoneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *newPhoneBtnConfig = [UIButtonConfiguration plainButtonConfiguration];
    newPhoneBtnConfig.title = @"一键新机";
    newPhoneBtnConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    newPhoneBtnConfig.background.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.15];
    newPhoneBtnConfig.baseForegroundColor = [UIColor systemGreenColor];
    newPhoneBtnConfig.contentInsets = NSDirectionalEdgeInsetsMake(6, 8, 6, 8);
    newPhoneButton.configuration = newPhoneBtnConfig;
    [newPhoneButton addTarget:self action:@selector(newPhoneTap) forControlEvents:UIControlEventTouchUpInside];
    newPhoneButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    newPhoneButton.layer.cornerRadius = 10;
    newPhoneButton.clipsToBounds = YES;
    
    // Create respring button with soft minimalistic style
    UIButton *applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *applyConfig = [UIButtonConfiguration plainButtonConfiguration];
    applyConfig.title = @"注销";
    applyConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    applyConfig.background.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.15];
    applyConfig.baseForegroundColor = [UIColor systemBlueColor];
    applyConfig.contentInsets = NSDirectionalEdgeInsetsMake(6, 8, 6, 8);
    applyButton.configuration = applyConfig;
    [applyButton addTarget:self action:@selector(applyChangesAndRespring) forControlEvents:UIControlEventTouchUpInside];
    applyButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    applyButton.layer.cornerRadius = 10;
    applyButton.clipsToBounds = YES;
    
    // Add buttons to stack view
    [buttonStackView addArrangedSubview:newPhoneButton];
    [buttonStackView addArrangedSubview:applyButton];
    
    // Setup constraints
    [NSLayoutConstraint activateConstraints:@[
        [separator.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:0.5],
        
        [buttonStackView.topAnchor constraintEqualToAnchor:separator.bottomAnchor constant:12],
        [buttonStackView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:16],
        [buttonStackView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-16],
        [buttonStackView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-12]
    ]];
    
    return containerView;
}

#pragma mark - Actions

- (void)applyChangesAndRespring {
    UIViewController *topController = [self topViewController];
    
    // Show confirmation alert
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring Required"
                                                                 message:@"A respring is required to apply changes. Would you like to respring now?"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        // Execute respring command
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // Generate haptic feedback before respringing
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [generator prepare];
            [generator impactOccurred];
            
            [self performRespring];
        });
    }]];
    
    [topController presentViewController:alert animated:YES completion:nil];
}
- (void)newPhoneTap {
    // 显示在窗口上
    [[LoadingView sharedInstance] showWithMessage:@"正在处理..."];
    
    // 延时关闭
     [[DaemonApiManager sharedManager] newPhone:^(id response, NSError *error) {
        // 回到主线程关闭加载框
        dispatch_async(dispatch_get_main_queue(), ^{
            [[LoadingView sharedInstance] hide];
            
            if (error) {
                UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"新机失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [[self topViewController] presentViewController:alert animated:YES completion:nil];
            } else {
                [[NSNotificationCenter defaultCenter] postNotificationName:@"ProjectXCommandFinished" object:nil];
            }
        });
    }];
}
- (void)performRespring {
    NSLog(@"[BottomButtons] 🔄 Attempting to respring device");
    
    // Define all possible methods to try for respringing
    NSMutableArray *respringMethods = [NSMutableArray array];
    [respringMethods addObject:^{
        [self respringUsingKillall];
    }];
    [respringMethods addObject:^{
        [self respringUsingSbreload];
    }];
    [respringMethods addObject:^{
        [self respringUsingFBSystemService];
    }];
    [respringMethods addObject:^{
        [self respringUsingLdrestart];
    }];
    
    // Try each method in sequence
    for (void (^respringMethod)(void) in respringMethods) {
        @try {
            respringMethod();
            return;
        } @catch (NSException *exception) {
            NSLog(@"[BottomButtons] Respring method failed: %@", exception);
            // Continue to next method
        }
    }
    
    NSLog(@"[BottomButtons] ⚠️ All respring methods failed");
}

- (void)respringUsingKillall {
    NSLog(@"[BottomButtons] 🔄 Attempting respring using killall");
    
    // Check for different killall paths based on jailbreak type
    NSArray *killallPaths = @[
        @"/var/jb/usr/bin/killall",   // Dopamine path
        @"/usr/bin/killall",          // Traditional/Palera1n path
        @"/var/jb/bin/killall",       // Alternative Dopamine path
        @"/private/preboot/jb/usr/bin/killall"  // Additional Palera1n path
    ];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *killallPath = nil;
    
    // Find the first available killall binary
    for (NSString *path in killallPaths) {
        if ([fileManager fileExistsAtPath:path]) {
            killallPath = path;
            break;
        }
    }
    
    if (killallPath) {
        pid_t pid;
        const char *killallPathStr = [killallPath UTF8String];
        // Try both "SpringBoard" and "backboardd" for different jailbreak setups
        NSArray *targetProcesses = @[@"SpringBoard", @"backboardd"];
        
        for (NSString *process in targetProcesses) {
            const char *processStr = [process UTF8String];
            char *const argv[] = {(char *)"killall", (char *)processStr, NULL};
            
            NSLog(@"[BottomButtons] 🔄 Trying to kill %@ using %@", process, killallPath);
            if (posix_spawn(&pid, killallPathStr, NULL, NULL, argv, NULL) == 0) {
                int status;
                waitpid(pid, &status, WEXITED);
                NSLog(@"[BottomButtons] ✅ Successfully killed %@ with status %d", process, WEXITSTATUS(status));
                return;
            }
        }
    } else {
        NSLog(@"[BottomButtons] ⚠️ Could not find a valid killall binary path");
        @throw [NSException exceptionWithName:@"RespringFailure" reason:@"No killall binary found" userInfo:nil];
    }
}

- (void)respringUsingSbreload {
    NSLog(@"[BottomButtons] 🔄 Attempting respring using sbreload");
    
    // Check for different sbreload paths based on jailbreak type
    NSArray *sbreloadPaths = @[
        @"/var/jb/usr/bin/sbreload",   // Dopamine path
        @"/usr/bin/sbreload",          // Traditional/Palera1n path
        @"/var/jb/bin/sbreload",       // Alternative path
        @"/private/preboot/jb/usr/bin/sbreload"  // Additional Palera1n path
    ];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *sbreloadPath = nil;
    
    // Find the first available sbreload binary
    for (NSString *path in sbreloadPaths) {
        if ([fileManager fileExistsAtPath:path]) {
            sbreloadPath = path;
            break;
        }
    }
    
    if (sbreloadPath) {
        pid_t pid;
        const char *sbreloadPathStr = [sbreloadPath UTF8String];
        char *const argv[] = {(char *)"sbreload", NULL};
        
        NSLog(@"[BottomButtons] 🔄 Using sbreload: %@", sbreloadPath);
        if (posix_spawn(&pid, sbreloadPathStr, NULL, NULL, argv, NULL) == 0) {
            int status;
            waitpid(pid, &status, WEXITED);
            NSLog(@"[BottomButtons] ✅ Successfully ran sbreload with status %d", WEXITSTATUS(status));
            return;
        }
    } else {
        NSLog(@"[BottomButtons] ⚠️ Could not find a valid sbreload binary path");
        @throw [NSException exceptionWithName:@"RespringFailure" reason:@"No sbreload binary found" userInfo:nil];
    }
}

- (void)respringUsingFBSystemService {
    NSLog(@"[BottomButtons] 🔄 Attempting respring using FBSystemService");
    
    @try {
        SBSRelaunchAction *action = [SBSRelaunchAction actionWithReason:@"respring" options:1 targetURL:nil];
        [[FBSSystemService sharedService] sendActions:[NSSet setWithObject:action] withResult:nil];
        NSLog(@"[BottomButtons] ✅ Successfully sent respring action via FBSystemService");
    } @catch (NSException *exception) {
        NSLog(@"[BottomButtons] ⚠️ FBSystemService respring failed: %@", exception);
        @throw;
    }
}

- (void)respringUsingLdrestart {
    NSLog(@"[BottomButtons] 🔄 Attempting respring using ldrestart");
    
    // Check for different ldrestart paths based on jailbreak type
    NSArray *ldrestartPaths = @[
        @"/var/jb/usr/bin/ldrestart",   // Dopamine path
        @"/usr/bin/ldrestart",          // Traditional/Palera1n path
        @"/var/jb/bin/ldrestart",       // Alternative path
        @"/private/preboot/jb/usr/bin/ldrestart"  // Additional Palera1n path
    ];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *ldrestartPath = nil;
    
    // Find the first available ldrestart binary
    for (NSString *path in ldrestartPaths) {
        if ([fileManager fileExistsAtPath:path]) {
            ldrestartPath = path;
            break;
        }
    }
    
    if (ldrestartPath) {
        pid_t pid;
        const char *ldrestartPathStr = [ldrestartPath UTF8String];
        char *const argv[] = {(char *)"ldrestart", NULL};
        
        NSLog(@"[BottomButtons] 🔄 Using ldrestart: %@", ldrestartPath);
        if (posix_spawn(&pid, ldrestartPathStr, NULL, NULL, argv, NULL) == 0) {
            int status;
            waitpid(pid, &status, WEXITED);
            NSLog(@"[BottomButtons] ✅ Successfully ran ldrestart with status %d", WEXITSTATUS(status));
            return;
        }
    } else {
        NSLog(@"[BottomButtons] ⚠️ Could not find a valid ldrestart binary path");
        @throw [NSException exceptionWithName:@"RespringFailure" reason:@"No ldrestart binary found" userInfo:nil];
    }
}

// Replace the deprecated keyWindow usage with proper scene-aware window handling
- (UIViewController *)topViewController {
    UIWindow *window = nil;
    
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *connectedScenes = UIApplication.sharedApplication.connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
                if (!window) {
                    // Fallback to first window if no key window found
                    window = windowScene.windows.firstObject;
                }
                break;
            }
        }
    } else {
        // Fallback for iOS 12 and below
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        window = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    
    UIViewController *topController = window.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    return topController;
}


@end