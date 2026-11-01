#import <Foundation/Foundation.h>

@class Profile;

NS_ASSUME_NONNULL_BEGIN

@interface Profile : NSObject <NSSecureCoding>

@property (nonatomic, strong) NSString *id;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong, nullable) NSDate *createdDate;
@property (nonatomic, strong, nullable) NSDate *disabledUntil;
- (BOOL)isDisabled;
- (NSDictionary *)toDictionary;
+ (nullable Profile *)fromDictionary:(NSDictionary *)dictionary;
@end

@interface ProfileManager : NSObject

@property (nonatomic, strong) NSMutableArray<Profile *> *mutableProfiles;
@property (nonatomic, strong, nullable) NSString *currentId;
@property (nonatomic, readonly) NSString *dataDirectory;
+ (instancetype)sharedManager;
- (instancetype)initWithDataDirectory:(NSString *)directory;
- (nullable NSString *)genBackupDirectory;
- (nullable NSString *)genInactiveBackupDirectory;

// Profile ID generation
- (NSString *)generateProfileID;
- (nullable NSString *)profileIdentityPath;
- (nullable NSString *)getActiveProfileId;
- (nullable NSString *)getActiveDataPath;
- (nullable Profile *) getProfileById:(NSString *) id;

- (BOOL)switchToProfile:(Profile *)profile;
- (BOOL)renameProfile:(NSString *)id to:(NSString *)newName;
- (BOOL)remove:(Profile *)profile;
- (BOOL)isCurrent:(Profile *)profile;
- (BOOL) removeProfileById:(NSString *) id;
- (BOOL)removeProfilesWithIDs:(NSArray<NSString *> *)identifiers;

- (BOOL)saveData;
- (BOOL)loadData;
- (BOOL)clearData;
- (nullable NSString *)pathForProfile:(NSString *)identifier;
- (BOOL)setDisabledUntil:(nullable NSDate *)date forProfile:(NSString *)identifier;
- (BOOL)moveProfile:(NSString *)identifier toIndex:(NSUInteger)index;
- (nullable Profile *)navigationTarget:(NSString *)operation wrap:(BOOL)wrap;
// Copies a validated import directory and remaps its identity. Never activates it.
- (nullable Profile *)importProfileDirectory:(NSString *)directory name:(NSString *)name error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
