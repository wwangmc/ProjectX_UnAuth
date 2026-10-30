#import "ProfileManager.h"

static NSString *const PXDefaultDataDirectory = @"/private/var/mobile/Media/ProjectX";

@implementation Profile
+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _id = [coder decodeObjectOfClass:[NSString class] forKey:@"id"];
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        _createdDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdDate"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_id forKey:@"id"];
    [coder encodeObject:_name forKey:@"name"];
    [coder encodeObject:_createdDate forKey:@"createdDate"];
}

- (NSDictionary *)toDictionary {
    return @{@"id": self.id ?: @"", @"name": self.name ?: @"",
             @"createdDate": self.createdDate ? @([self.createdDate timeIntervalSince1970]) : @0};
}

+ (Profile *)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]] ||
        ![dict[@"id"] isKindOfClass:[NSString class]] || ![dict[@"id"] length]) return nil;
    NSString *identifier = dict[@"id"];
    // IDs are also directory names. Refuse path components from corrupt metadata.
    if ([identifier isEqualToString:@"."] || [identifier isEqualToString:@".."] ||
        [identifier rangeOfString:@"/"].location != NSNotFound) return nil;
    Profile *profile = [[Profile alloc] init];
    profile.id = identifier;
    profile.name = [dict[@"name"] isKindOfClass:[NSString class]] ? dict[@"name"] : identifier;
    id date = dict[@"createdDate"];
    if (([date isKindOfClass:[NSNumber class]] || [date isKindOfClass:[NSString class]]) && [date doubleValue] > 0) {
        profile.createdDate = [NSDate dateWithTimeIntervalSince1970:[date doubleValue]];
    }
    return profile;
}
@end

@interface ProfileManager ()
@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, copy) NSString *profilesDirectory;
@property (nonatomic, copy) NSString *profileDataPath;
@end

@implementation ProfileManager
+ (instancetype)sharedManager {
    static ProfileManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (instancetype)init { return [self initWithDataDirectory:PXDefaultDataDirectory]; }

- (instancetype)initWithDataDirectory:(NSString *)directory {
    self = [super init];
    if (self) {
        _mutableProfiles = [NSMutableArray array];
        _fileManager = [NSFileManager defaultManager];
        _profilesDirectory = [directory copy];
        _profileDataPath = [directory stringByAppendingPathComponent:@"profiles.json"];
        [self createDirectoryIfNeeded:directory];
        [self loadData];
    }
    return self;
}

- (BOOL)createDirectoryIfNeeded:(NSString *)directory {
    BOOL isDirectory = NO;
    if ([_fileManager fileExistsAtPath:directory isDirectory:&isDirectory]) return isDirectory;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithObject:@0755 forKey:NSFilePosixPermissions];
    if ([_profilesDirectory isEqualToString:PXDefaultDataDirectory]) {
        attributes[NSFileOwnerAccountName] = @"mobile";
        attributes[NSFileGroupOwnerAccountName] = @"mobile";
    }
    NSError *error = nil;
    BOOL success = [_fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:attributes error:&error];
    if (!success) NSLog(@"[ProjectX] Create directory failed: %@", error.localizedDescription);
    return success;
}

- (BOOL)saveData {
    @synchronized (self) {
        NSMutableArray *profiles = [NSMutableArray array];
        for (Profile *profile in self.mutableProfiles) [profiles addObject:[profile toDictionary]];
        NSDictionary *data = @{@"currentId": self.currentId ?: @"", @"mutableProfiles": profiles};
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:&error];
        BOOL success = json && [json writeToFile:self.profileDataPath options:NSDataWritingAtomic error:&error];
        if (!success) NSLog(@"[ProjectX] Save profiles failed: %@", error.localizedDescription);
        return success;
    }
}

- (BOOL)loadData {
    @synchronized (self) {
        if (![_fileManager fileExistsAtPath:self.profileDataPath]) return NO;
        NSError *error = nil;
        NSData *json = [NSData dataWithContentsOfFile:self.profileDataPath options:0 error:&error];
        id data = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:&error] : nil;
        if (![data isKindOfClass:[NSDictionary class]] || ![data[@"mutableProfiles"] isKindOfClass:[NSArray class]]) {
            NSLog(@"[ProjectX] Invalid profiles file: %@", error.localizedDescription ?: @"unexpected JSON type");
            return NO;
        }
        NSMutableArray *profiles = [NSMutableArray array];
        NSMutableSet *identifiers = [NSMutableSet set];
        for (id item in data[@"mutableProfiles"]) {
            Profile *profile = [Profile fromDictionary:item];
            if (!profile || [identifiers containsObject:profile.id]) return NO;
            [profiles addObject:profile];
            [identifiers addObject:profile.id];
        }
        NSString *current = [data[@"currentId"] isKindOfClass:[NSString class]] ? data[@"currentId"] : nil;
        if (![identifiers containsObject:current ?: @""]) current = [profiles firstObject] ? ((Profile *)profiles.firstObject).id : nil;
        // Commit only after the entire file has been validated.
        self.mutableProfiles = profiles;
        self.currentId = current;
        return YES;
    }
}

- (BOOL)clearData {
    @synchronized (self) {
        NSError *error = nil;
        if ([_fileManager fileExistsAtPath:self.profileDataPath] &&
            ![_fileManager removeItemAtPath:self.profileDataPath error:&error]) {
            NSLog(@"[ProjectX] Clear profiles failed: %@", error.localizedDescription);
            return NO;
        }
        self.currentId = nil;
        [self.mutableProfiles removeAllObjects];
        return YES;
    }
}

- (NSString *)generateProfileID {
    static long long lastTimestamp;
    @synchronized ([ProfileManager class]) {
        long long timestamp = (long long)([NSDate date].timeIntervalSince1970 * 1000);
        lastTimestamp = MAX(timestamp, lastTimestamp + 1);
        return [NSString stringWithFormat:@"%lld", lastTimestamp];
    }
}

- (NSString *)genBackupDirectory {
    @synchronized (self) {
        NSString *identifier;
        NSString *path;
        do {
            identifier = [self generateProfileID];
            path = [self.profilesDirectory stringByAppendingPathComponent:identifier];
        } while ([_fileManager fileExistsAtPath:path]);
        if (![self createDirectoryIfNeeded:path]) return nil;
        Profile *profile = [[Profile alloc] init];
        profile.id = identifier;
        profile.name = identifier;
        profile.createdDate = [NSDate date];
        NSString *previousId = self.currentId;
        [self.mutableProfiles addObject:profile];
        self.currentId = identifier;
        if (![self saveData]) {
            [self.mutableProfiles removeLastObject];
            self.currentId = previousId;
            // Only the empty directory just created by this method is removed.
            [_fileManager removeItemAtPath:path error:NULL];
            return nil;
        }
        return path;
    }
}

- (Profile *)getProfileById:(NSString *)identifier {
    @synchronized (self) {
        for (Profile *profile in self.mutableProfiles) if ([profile.id isEqualToString:identifier]) return profile;
        return nil;
    }
}

- (BOOL)isCurrent:(Profile *)profile { return self.currentId && [self.currentId isEqualToString:profile.id]; }
- (BOOL)remove:(Profile *)profile { return profile && ![self isCurrent:profile] && [self removeProfileById:profile.id]; }

- (BOOL)removeProfileById:(NSString *)identifier {
    @synchronized (self) {
        Profile *profile = [self getProfileById:identifier];
        if (!profile || [self isCurrent:profile]) return NO;
        NSUInteger index = [self.mutableProfiles indexOfObject:profile];
        [self.mutableProfiles removeObjectAtIndex:index];
        if ([self saveData]) return YES;
        [self.mutableProfiles insertObject:profile atIndex:index];
        return NO;
    }
}

- (BOOL)switchToProfile:(Profile *)profile {
    @synchronized (self) {
        if (![self getProfileById:profile.id]) return NO;
        NSString *previousId = self.currentId;
        self.currentId = profile.id;
        if ([self saveData]) return YES;
        self.currentId = previousId;
        return NO;
    }
}

- (BOOL)renameProfile:(NSString *)identifier to:(NSString *)newName {
    if (![newName isKindOfClass:[NSString class]] || !newName.length) return NO;
    @synchronized (self) {
        Profile *profile = [self getProfileById:identifier];
        if (!profile) return NO;
        NSString *previousName = profile.name;
        profile.name = newName;
        if ([self saveData]) return YES;
        profile.name = previousName;
        return NO;
    }
}

- (NSString *)getActiveProfileId { return self.currentId; }
- (NSString *)getActiveDataPath {
    NSString *identifier = [self getActiveProfileId];
    return identifier.length ? [self.profilesDirectory stringByAppendingPathComponent:identifier] : nil;
}
- (NSString *)profileIdentityPath {
    NSString *activePath = [self getActiveDataPath];
    if (!activePath) return nil;
    NSString *path = [activePath stringByAppendingPathComponent:@"identity"];
    return [self createDirectoryIfNeeded:path] ? path : nil;
}
@end
