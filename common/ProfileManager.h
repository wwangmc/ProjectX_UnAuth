#import <Foundation/Foundation.h>

@class Profile;

NS_ASSUME_NONNULL_BEGIN

@interface Profile : NSObject <NSSecureCoding>

@property (nonatomic, strong) NSString *id;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong, nullable) NSDate *createdDate;
- (NSDictionary *)toDictionary;
+ (nullable Profile *)fromDictionary:(NSDictionary *)dictionary;
@end

@interface ProfileManager : NSObject

@property (nonatomic, strong) NSMutableArray<Profile *> *mutableProfiles;
@property (nonatomic, strong, nullable) NSString *currentId;
+ (instancetype)sharedManager;
- (instancetype)initWithDataDirectory:(NSString *)directory;
- (nullable NSString *)genBackupDirectory;

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

- (BOOL)saveData;
- (BOOL)loadData;
- (BOOL)clearData;

@end

NS_ASSUME_NONNULL_END
