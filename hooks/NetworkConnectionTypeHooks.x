#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <UIKit/UIKit.h>
#import "ProjectXLogging.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <netinet/in.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#include <dlfcn.h>
#import "DataManager.h"


// Constants for signal strength
static const int kWiFiSignalStrengthExcellent = -45;  // -45 dBm (Excellent)
static const int kWiFiSignalStrengthGood = -60;       // -60 dBm (Good)
static const int kWiFiSignalStrengthFair = -70;       // -70 dBm (Fair)
static const int kWiFiSignalStrengthPoor = -80;       // -80 dBm (Poor)

// Keep track of current signal values for realistic gradual changes
static int currentWiFiSignalStrength = -65;  // Start with a reasonable default
static int currentCellularSignalBars = 4;    // Start with good signal
static NSDate *lastSignalUpdateTime = nil;

// Cellular network type constants (4G/5G)
static NSString *const kCellularNetworkType4G = @"CTRadioAccessTechnologyLTE";
static NSString *const kCellularNetworkType5G = @"CTRadioAccessTechnologyNR";  // iOS 15+ 5G
static NSString *const kCellularNetworkType5GNSA = @"CTRadioAccessTechnologyNRNSA"; // 5G Non-Standalone

// Current cellular network type (changes over time)
static NSString *currentCellularNetworkType = nil;
static NSDate *lastNetworkTypeChangeTime = nil;
static const NSTimeInterval kMinNetworkTypeChangeDuration = 120.0; // Minimum 2 minutes between technology changes

#pragma mark - Helper Functions



// Get the current ISO country code from security settings
static NSString *getCurrentISOCountryCode() {
    return CurrentPhoneInfo().networkInfo.countryCode;
}



// Get the current local IP address from the system
static NSString * __attribute__((unused)) getCurrentLocalIPAddress() {
    NSString *address = @"192.168.1.1"; // Default fallback
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    
    // Retrieve the current interfaces - returns 0 on success
    if (getifaddrs(&interfaces) == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on iOS
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    // Free memory
    freeifaddrs(interfaces);
    
    return address;
}




// Helper to check if we should show as WiFi
static BOOL shouldShowAsWiFi() {
    NetworkConnectionType type = CurrentPhoneInfo().networkInfo.connectionType;
    
    return type == NetworkConnectionTypeWiFi;
}

// Helper to check if we should show as Cellular
static BOOL shouldShowAsCellular() {
    NetworkConnectionType type = CurrentPhoneInfo().networkInfo.connectionType;
    return type == NetworkConnectionTypeCellular;
}



// Get a realistic WiFi signal strength in dBm that changes gradually over time
static int getWiFiSignalStrength() {
    // Check if we need to update the signal (approximately every 30-60 seconds)
    NSTimeInterval timeSinceLastUpdate = lastSignalUpdateTime ? [[NSDate date] timeIntervalSinceDate:lastSignalUpdateTime] : 60.0;
    
    // Update signal strength every 30-60 seconds with small random fluctuations
    if (timeSinceLastUpdate >= 30.0 || !lastSignalUpdateTime) {
        // Determine the base signal strength based on connection type
        NetworkConnectionType connectionType = CurrentPhoneInfo().networkInfo.connectionType;
        int targetSignal;
        
        if (connectionType == NetworkConnectionTypeWiFi) {
            // For WiFi mode, generally have good to excellent signal (realistic for most environments)
            int signalBase = arc4random_uniform(100);
            if (signalBase < 60) {
                // 60% chance of excellent signal
                targetSignal = kWiFiSignalStrengthExcellent + (arc4random_uniform(10) - 5); // -50 to -40 dBm
            } else if (signalBase < 90) {
                // 30% chance of good signal
                targetSignal = kWiFiSignalStrengthGood + (arc4random_uniform(8) - 4);  // -64 to -56 dBm
            } else {
                // 10% chance of fair signal
                targetSignal = kWiFiSignalStrengthFair + (arc4random_uniform(8) - 4);  // -74 to -66 dBm
            }
        } else if (connectionType == NetworkConnectionTypeCellular) {
            // For cellular mode, have slightly weaker WiFi (realistic for mobile scenarios)
            int signalBase = arc4random_uniform(100);
            if (signalBase < 20) {
                // 20% chance of excellent signal
                targetSignal = kWiFiSignalStrengthExcellent + (arc4random_uniform(10) - 5); // -50 to -40 dBm
            } else if (signalBase < 50) {
                // 30% chance of good signal
                targetSignal = kWiFiSignalStrengthGood + (arc4random_uniform(8) - 4);  // -64 to -56 dBm
            } else if (signalBase < 80) {
                // 30% chance of fair signal
                targetSignal = kWiFiSignalStrengthFair + (arc4random_uniform(8) - 4);  // -74 to -66 dBm
            } else {
                // 20% chance of poor signal
                targetSignal = kWiFiSignalStrengthPoor + (arc4random_uniform(8) - 4);  // -84 to -76 dBm
            }
        } else {
            // For None mode or default, have variable signal (less predictable)
            targetSignal = -45 - (arc4random_uniform(45)); // -45 to -90 dBm
        }
        
        // Move gradually toward the target signal (max +/- 3 dBm change per update)
        int signalDiff = targetSignal - currentWiFiSignalStrength;
        int maxChange = 3; // Maximum dBm change per update
        
        // Limit the change to ensure realistic gradual signal fluctuations
        if (signalDiff > maxChange) {
            currentWiFiSignalStrength += maxChange;
        } else if (signalDiff < -maxChange) {
            currentWiFiSignalStrength -= maxChange;
        } else {
            currentWiFiSignalStrength = targetSignal;
        }
        
        // Add small random fluctuation (+/- 1 dBm) for realism
        currentWiFiSignalStrength += (arc4random_uniform(3) - 1);
        
        // Enforce realistic bounds for WiFi signal strength
        if (currentWiFiSignalStrength > -40) currentWiFiSignalStrength = -40;  // Never too perfect
        if (currentWiFiSignalStrength < -90) currentWiFiSignalStrength = -90;  // Never too terrible
        
        // Update last update time
        lastSignalUpdateTime = [NSDate date];
        
        PXLog(@"[NetworkHook] Updated WiFi signal strength to %d dBm", currentWiFiSignalStrength);
    }
    
    return currentWiFiSignalStrength;
}

// Get realistic cellular signal bars (1-5) that change gradually over time
static int getCellularSignalBars() {
    // Check if we need to update the signal (use the same timing as WiFi for consistency)
    NSTimeInterval timeSinceLastUpdate = lastSignalUpdateTime ? [[NSDate date] timeIntervalSinceDate:lastSignalUpdateTime] : 60.0;
    
    // Update signal bars every 30-60 seconds
    if (timeSinceLastUpdate >= 30.0 || !lastSignalUpdateTime) {
        // Determine the base signal bars based on connection type
        NetworkConnectionType connectionType = CurrentPhoneInfo().networkInfo.connectionType;
        int targetBars;
        
        if (connectionType == NetworkConnectionTypeCellular) {
            // For cellular mode, generally have good signal (3-5 bars)
            int signalBase = arc4random_uniform(100);
            if (signalBase < 40) {
                // 40% chance of 5 bars
                targetBars = 5;
            } else if (signalBase < 80) {
                // 40% chance of 4 bars
                targetBars = 4;
            } else {
                // 20% chance of 3 bars
                targetBars = 3;
            }
        } else if (connectionType == NetworkConnectionTypeWiFi) {
            // For WiFi mode, have slightly weaker cellular (1-4 bars, realistic for indoor WiFi scenarios)
            int signalBase = arc4random_uniform(100);
            if (signalBase < 20) {
                // 20% chance of 4 bars
                targetBars = 4;
            } else if (signalBase < 50) {
                // 30% chance of 3 bars
                targetBars = 3;
            } else if (signalBase < 80) {
                // 30% chance of 2 bars
                targetBars = 2;
            } else {
                // 20% chance of 1 bar
                targetBars = 1;
            }
        } else {
            // For None mode or default, random bars
            targetBars = 1 + (arc4random_uniform(5)); // 1-5 bars
        }
        
        // Move gradually toward the target bars (max +/- 1 bar change per update)
        int barsDiff = targetBars - currentCellularSignalBars;
        
        // Limit the change to ensure realistic gradual signal fluctuations
        if (barsDiff > 1) {
            currentCellularSignalBars += 1;
        } else if (barsDiff < -1) {
            currentCellularSignalBars -= 1;
        } else {
            currentCellularSignalBars = targetBars;
        }
        
        // Enforce bounds
        if (currentCellularSignalBars < 1) currentCellularSignalBars = 1;
        if (currentCellularSignalBars > 5) currentCellularSignalBars = 5;
        
        PXLog(@"[NetworkHook] Updated cellular signal bars to %d", currentCellularSignalBars);
    }
    
    return currentCellularSignalBars;
}

// Get a realistic cellular network type (4G/5G) that changes based on signal strength
static NSString *getCurrentCellularNetworkType() {
    // Initialize the network type if not set
    if (!currentCellularNetworkType) {
        // Default to LTE (4G) initially
        currentCellularNetworkType = kCellularNetworkType4G;
        lastNetworkTypeChangeTime = [NSDate date];
    }
    
    // Only consider changing network type after a minimum duration
    NSTimeInterval timeSinceLastChange = [[NSDate date] timeIntervalSinceDate:lastNetworkTypeChangeTime];
    if (timeSinceLastChange < kMinNetworkTypeChangeDuration) {
        return currentCellularNetworkType;
    }
    
    // Only change network type occasionally (10% chance per check)
    if (arc4random_uniform(100) >= 10) {
        return currentCellularNetworkType;
    }
    
    // Determine probability of 5G based on signal strength
    // Higher signal = higher chance of 5G
    CGFloat probabilityOf5G = 0.0;
    
    // Map signal bars (1-5) to 5G probability
    switch (currentCellularSignalBars) {
        case 5: probabilityOf5G = 0.85; break; // Excellent signal: 85% chance of 5G
        case 4: probabilityOf5G = 0.65; break; // Good signal: 65% chance of 5G
        case 3: probabilityOf5G = 0.40; break; // Fair signal: 40% chance of 5G
        case 2: probabilityOf5G = 0.15; break; // Poor signal: 15% chance of 5G
        case 1: probabilityOf5G = 0.05; break; // Very poor signal: 5% chance of 5G
        default: probabilityOf5G = 0.0;        // No signal: 0% chance of 5G
    }
    
    // Random decision based on probability
    CGFloat random = (CGFloat)arc4random_uniform(100) / 100.0;
    
    NSString *newNetworkType;
    if (random < probabilityOf5G) {
        // Decide between standalone 5G and NSA 5G
        // NSA is more common in early 5G deployments
        if (arc4random_uniform(100) < 70) {
            newNetworkType = kCellularNetworkType5GNSA; // 70% of 5G is NSA
        } else {
            newNetworkType = kCellularNetworkType5G;    // 30% of 5G is standalone
        }
    } else {
        newNetworkType = kCellularNetworkType4G;        // Default to 4G
    }
    
    // Only log if network type actually changed
    if (![newNetworkType isEqualToString:currentCellularNetworkType]) {
        PXLog(@"[NetworkHook] Changed cellular network type from %@ to %@", 
              currentCellularNetworkType, newNetworkType);
        
        // Update stored values
        currentCellularNetworkType = newNetworkType;
        lastNetworkTypeChangeTime = [NSDate date];
    }
    
    return currentCellularNetworkType;
}

#pragma mark - SCNetworkReachability Hooks

// Hook SCNetworkReachabilityGetFlags to modify network type
static Boolean (*original_SCNetworkReachabilityGetFlags)(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags);

Boolean hooked_SCNetworkReachabilityGetFlags(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags) {
    Boolean result = original_SCNetworkReachabilityGetFlags(target, flags);
    if (!result || !flags) {
        return result;
    }
    @try {
        if (shouldShowAsWiFi()) {
            *flags |= kSCNetworkReachabilityFlagsReachable;
            *flags &= ~kSCNetworkReachabilityFlagsIsWWAN;
        } else if (shouldShowAsCellular()) {
            *flags |= kSCNetworkReachabilityFlagsReachable;
            *flags |= kSCNetworkReachabilityFlagsIsWWAN;
        } else {
            *flags &= ~kSCNetworkReachabilityFlagsReachable;
            *flags &= ~kSCNetworkReachabilityFlagsIsWWAN;
        }
    } @catch (NSException *exception) {}
    return result;
}

#pragma mark - CoreTelephony Hooks

// Hook for CTTelephonyNetworkInfo
%hook CTTelephonyNetworkInfo

- (NSDictionary *)serviceSubscriberCellularProviders {

    NetworkInfo * networkInfo = CurrentPhoneInfo().networkInfo;
    CTCarrier *carrier = [[CTCarrier alloc] init];

    [carrier setValue:networkInfo.mcc forKey:@"mobileCountryCode"];
    [carrier setValue:networkInfo.mnc forKey:@"mobileNetworkCode"];
    [carrier setValue:networkInfo.carrierName forKey:@"carrierName"];
    [carrier setValue:networkInfo.countryCode forKey:@"isoCountryCode"];

    return @{
        @"0000000100000001" : carrier
    };
}

- (NSString *)currentRadioAccessTechnology {
    if (CurrentPhoneInfo().networkInfo.radioAccessTechnology.length) return CurrentPhoneInfo().networkInfo.radioAccessTechnology;
    // if (shouldShowAsCellular()) {
    //     return getCurrentCellularNetworkType();
    // }
    // return %orig;
    return CTRadioAccessTechnologyLTE;
}

- (NSDictionary<NSString *, NSString *> *)serviceCurrentRadioAccessTechnology {
    if (CurrentPhoneInfo().networkInfo.radioAccessTechnology.length) {
        NSDictionary *original=%orig;
        NSMutableDictionary *result=[NSMutableDictionary dictionary];
        for (NSString *key in original) result[key]=CurrentPhoneInfo().networkInfo.radioAccessTechnology;
        if (!result.count) result[@"0000000100000001"]=CurrentPhoneInfo().networkInfo.radioAccessTechnology;
        return result;
    }
    if (shouldShowAsCellular()) {
        return @{ @"0": getCurrentCellularNetworkType() };
    }
    return %orig;
}

%end

// Hook for CTCarrier
%hook CTCarrier

- (NSString *)carrierName {
    if (shouldShowAsCellular()) {
        return CurrentPhoneInfo().networkInfo.carrierName;
    }
    return %orig;
}

- (NSString *)mobileCountryCode {
    if (shouldShowAsCellular()) {
        return CurrentPhoneInfo().networkInfo.mcc;
    }
    return %orig;
}

- (NSString *)mobileNetworkCode {
    if (shouldShowAsCellular()) {
        return CurrentPhoneInfo().networkInfo.mnc;
    }
    return %orig;
}

- (NSString *)isoCountryCode {
    if (shouldShowAsCellular()) {
        return getCurrentISOCountryCode();
    }
    return %orig;
}

- (BOOL)allowsVOIP {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    // Allow VOIP in all network modes
    return YES;
}

%end

#pragma mark - NSURLSession and CFNetwork Hooks

// Hook for cellular detection in NSURLSession
%hook NSURLSessionConfiguration

- (BOOL)allowsCellularAccess {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    return %orig;
}

- (BOOL)isDiscretionary {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    // Discretionary transfers are typically used for background transfers 
    // that prefer WiFi. Return NO to indicate high priority connection.
    return NO;
}

%end

#pragma mark - getifaddrs Hook for Local IP Address

// Enable getifaddrs hook for local IP spoofing
static int (*original_getifaddrs)(struct ifaddrs **);
static int hooked_getifaddrs(struct ifaddrs **ifap) {
    // 调用原始函数获取真实的接口列表
    int result = original_getifaddrs(ifap);
    
    // 如果获取失败或者返回列表为空，直接返回结果
    if (result != 0 || ifap == NULL || *ifap == NULL) {
        return result;
    }

    NetworkInfo *networkInfo = CurrentPhoneInfo().networkInfo;
    NetworkConnectionType type = networkInfo.connectionType;
    NSString *spoofedIP = networkInfo.localIPAddress;
    NSString *spoofedIPv6 = networkInfo.localIPv6Address;

    struct ifaddrs *ifa = *ifap;
    while (ifa) {
        if (ifa->ifa_addr == NULL) {
            ifa = ifa->ifa_next;
            continue;
        }

        const char *name = ifa->ifa_name;
        uint16_t family = ifa->ifa_addr->sa_family;

        // --- 处理 IPv4 逻辑 ---
        if (family == AF_INET) {
            struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
            
            if (type == NetworkConnectionTypeWiFi && strcmp(name, "en0") == 0) {
                if (spoofedIP && spoofedIP.length > 0) {
                    sin->sin_addr.s_addr = inet_addr([spoofedIP UTF8String]);
                    // 配合 WiFi 环境，通常将掩码设为 255.255.255.0
                    if (ifa->ifa_netmask) {
                        ((struct sockaddr_in *)ifa->ifa_netmask)->sin_addr.s_addr = inet_addr("255.255.255.0");
                    }
                }
            } 
            else if (type == NetworkConnectionTypeCellular && strcmp(name, "pdp_ip0") == 0) {
                if (spoofedIP && spoofedIP.length > 0) {
                    sin->sin_addr.s_addr = inet_addr([spoofedIP UTF8String]);
                    // 蜂窝网掩码通常是 255.255.255.255
                    if (ifa->ifa_netmask) {
                        ((struct sockaddr_in *)ifa->ifa_netmask)->sin_addr.s_addr = inet_addr("255.255.255.255");
                    }
                }
            }
        }
        
        // --- 处理 IPv6 逻辑 ---
        else if (family == AF_INET6) {
            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)ifa->ifa_addr;
            
            BOOL isWiFiTarget = (type == NetworkConnectionTypeWiFi && strcmp(name, "en0") == 0);
            BOOL isCellularTarget = (type == NetworkConnectionTypeCellular && strcmp(name, "pdp_ip0") == 0);
            
            if (isWiFiTarget || isCellularTarget) {
                NSString *targetIPv6 = spoofedIPv6 ? spoofedIPv6 : @"fe80::1234:abcd:5678:9abc";
                inet_pton(AF_INET6, [targetIPv6 UTF8String], &sin6->sin6_addr);
                // IPv6 掩码通常保持系统默认，不做强制修改以防结构破坏
            }
        }

        ifa = ifa->ifa_next;
    }

    return result;
}

#pragma mark - Network.framework Hooks (iOS 12+)

// Attempt to hook NWPathMonitor for newer iOS versions
%group NetworkFrameworkHooks

%hook NWPath

- (BOOL)isExpensive {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    // WiFi is not expensive, cellular is
    return shouldShowAsCellular();
}

- (BOOL)usesInterfaceType:(NSInteger)type {
    if (shouldShowAsWiFi()) {
        // Interface type 1 is typically WiFi
        if (type == 1) {
            return YES;
        }
        // Interface type 2 is typically cellular
        else if (type == 2) {
            return NO;
        }
    }
    // For cellular mode
    else {
        // Interface type 1 is typically WiFi
        if (type == 1) {
            return NO;
        }
        // Interface type 2 is typically cellular
        else if (type == 2) {
            return YES;
        }
    }
    
    return %orig;
}

%end

%end


// Hook for WiFi signal strength (CNCopyCurrentNetworkInfo)
static CFDictionaryRef (*original_CNCopyCurrentNetworkInfo)(CFStringRef interfaceName);

static CFDictionaryRef hooked_CNCopyCurrentNetworkInfo(CFStringRef interfaceName) {
    if (shouldShowAsWiFi()) {
        return original_CNCopyCurrentNetworkInfo(interfaceName);
    }
    // Always call the original so WiFiHook.x can spoof as needed
    CFDictionaryRef originalDict = original_CNCopyCurrentNetworkInfo(interfaceName);
    if (!originalDict) return originalDict;
    // Existing WiFi signal strength spoofing logic
    CFMutableDictionaryRef newDict = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, originalDict);
    int signalStrength = getWiFiSignalStrength();
    CFNumberRef rssiNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &signalStrength);
    CFDictionarySetValue(newDict, CFSTR("RSSI"), rssiNumber);
    CFRelease(originalDict);
    CFRelease(rssiNumber);
    return newDict;
}

// Add hooks for CoreTelephony signal strength
%hook CTServiceDescriptor

- (NSString *)signalStrengthBars {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    // Return spoofed signal bars
    int bars = getCellularSignalBars();
    NSString *barsString = [NSString stringWithFormat:@"%d", bars];
    
    PXLog(@"[NetworkHook] Spoofed cellular signal bars to %@", barsString);
    
    return barsString;
}

%end

%hook UIStatusBarSignalStrengthItemView

- (void)setCellularSignalStrengthBars:(int)bars {
    if (shouldShowAsWiFi()) {
        %orig;
        return;
    }
    
    // Get spoofed signal bars
    int spoofedBars = getCellularSignalBars();
    
    PXLog(@"[NetworkHook] Spoofed UI cellular signal bars from %d to %d", bars, spoofedBars);
    
    %orig(spoofedBars);
}

%end

#pragma mark - Initialization

%ctor {
    @autoreleasepool {
        
        PXLog(@"[NetworkHook] Initializing network connection type hooks");
        
        // Initialize CoreTelephony hooks
        %init;
        
        // Initialize Network.framework hooks if available
        Class NWPathClass = NSClassFromString(@"NWPath");
        if (NWPathClass) {
            %init(NetworkFrameworkHooks);
            PXLog(@"[NetworkHook] Successfully initialized Network.framework hooks");
        }
        
        // Setup the SCNetworkReachabilityGetFlags hook
        void *SCNetworkReachabilityGetFlagsPtr = dlsym(RTLD_DEFAULT, "SCNetworkReachabilityGetFlags");
        if (SCNetworkReachabilityGetFlagsPtr) {
            MSHookFunction(SCNetworkReachabilityGetFlagsPtr, 
                    (void *)hooked_SCNetworkReachabilityGetFlags, 
                    (void **)&original_SCNetworkReachabilityGetFlags);
            PXLog(@"[NetworkHook] Successfully hooked SCNetworkReachabilityGetFlags");
        } else {
            PXLog(@"[NetworkHook] ERROR: Could not find SCNetworkReachabilityGetFlags function!");
        }
        
        // Enable getifaddrs hook for local IP spoofing
        void *getifaddrsPtr = dlsym(RTLD_DEFAULT, "getifaddrs");
        if (getifaddrsPtr) {
            MSHookFunction(getifaddrsPtr, (void *)hooked_getifaddrs, (void **)&original_getifaddrs);
            PXLog(@"[NetworkHook] Successfully hooked getifaddrs for local IP spoofing");
        } else {
            PXLog(@"[NetworkHook] ERROR: Could not find getifaddrs function!");
        }
        
        NetworkInfo * networkInfo = CurrentPhoneInfo().networkInfo;
        // Log initial state
        NetworkConnectionType initialType = networkInfo.connectionType;
        if (initialType != -1) {
            NSString *connectionName;
            switch (initialType) {
                case NetworkConnectionTypeWiFi:
                    connectionName = @"WiFi";
                    break;
                case NetworkConnectionTypeCellular:
                    connectionName = @"Cellular";
                    break;
                default:
                    connectionName = @"Unknown";
                    break;
            }
        } else {
            PXLog(@"[NetworkHook] Network connection type spoofing disabled");
        }
        
        // Setup CNCopyCurrentNetworkInfo hook for WiFi signal strength
        void *CNCopyCurrentNetworkInfoPtr = dlsym(RTLD_DEFAULT, "CNCopyCurrentNetworkInfo");
        if (CNCopyCurrentNetworkInfoPtr) {
            MSHookFunction(CNCopyCurrentNetworkInfoPtr,
                    (void *)hooked_CNCopyCurrentNetworkInfo,
                    (void **)&original_CNCopyCurrentNetworkInfo);
            PXLog(@"[NetworkHook] Successfully hooked CNCopyCurrentNetworkInfo for WiFi signal strength spoofing");
        } else {
            PXLog(@"[NetworkHook] ERROR: Could not find CNCopyCurrentNetworkInfo function!");
        }
    
    }
} 