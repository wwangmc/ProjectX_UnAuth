#import "PXContainerFiles.h"
#import "PXConfiguration.h"
#import <sys/stat.h>

static BOOL Preserved(NSString *relative, NSArray *rules) {
    for (NSString *rule in rules) if ([relative isEqual:rule] || [relative hasPrefix:[rule stringByAppendingString:@"/"]]) return YES;
    return NO;
}
static BOOL Ancestor(NSString *relative, NSArray *rules) {
    for (NSString *rule in rules) if ([rule hasPrefix:[relative stringByAppendingString:@"/"]]) return YES;
    return NO;
}
static BOOL Directory(NSString *path,NSError **error) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation,&st) || !S_ISDIR(st.st_mode)) {
        if (error) *error=PXError(@"目录不存在或为符号链接"); return NO;
    }
    return YES;
}
static BOOL EnsureDirectory(NSString *path,NSError **error) {
    struct stat st;
    if (!lstat(path.fileSystemRepresentation,&st)) return Directory(path,error);
    if (errno!=ENOENT) { if (error) *error=PXError(@"无法检查目录"); return NO; }
    return [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:error];
}
static BOOL Copy(NSString *source,NSString *destination,NSString *relative,NSArray *rules,NSError **error) {
    if (Preserved(relative,rules)) return YES;
    NSFileManager *fm=NSFileManager.defaultManager;
    struct stat st;
    if (lstat(source.fileSystemRepresentation,&st)) return errno==ENOENT;
    if (!S_ISDIR(st.st_mode) && !S_ISREG(st.st_mode)) { if (error) *error=PXError(@"容器包含链接或特殊文件，操作已停止"); return NO; }
    struct stat dst;
    if (!lstat(destination.fileSystemRepresentation,&dst) && !S_ISDIR(dst.st_mode) && !S_ISREG(dst.st_mode)) {
        if (error) *error=PXError(@"目标路径包含链接"); return NO;
    }
    if (S_ISREG(st.st_mode)) {
        if ([fm fileExistsAtPath:destination] && ![fm removeItemAtPath:destination error:error]) return NO;
        return [fm copyItemAtPath:source toPath:destination error:error];
    }
    if (!EnsureDirectory(destination,error)) return NO;
    NSArray *children=[fm contentsOfDirectoryAtPath:source error:error];
    if (!children) return NO;
    for (NSString *child in children) if (!Copy([source stringByAppendingPathComponent:child],
        [destination stringByAppendingPathComponent:child],[relative stringByAppendingPathComponent:child],rules,error)) return NO;
    return YES;
}
static BOOL Clear(NSString *path,NSString *relative,NSArray *rules,NSError **error) {
    if (Preserved(relative,rules)) return YES;
    NSFileManager *fm=NSFileManager.defaultManager;
    struct stat st;
    if (lstat(path.fileSystemRepresentation,&st)) return errno==ENOENT;
    if (!Ancestor(relative,rules) || !S_ISDIR(st.st_mode)) return [fm removeItemAtPath:path error:error];
    NSArray *children=[fm contentsOfDirectoryAtPath:path error:error];
    if (!children) return NO;
    for (NSString *child in children) if (!Clear([path stringByAppendingPathComponent:child],
        [relative stringByAppendingPathComponent:child],rules,error)) return NO;
    return YES;
}
BOOL PXCopyContainer(NSString *source,NSString *destination,NSArray *preservedPaths,NSError **error) {
    if (error) *error=nil;
    NSArray *rules=PXValidatedRelativePaths(preservedPaths ?: @[],error);
    if (!rules || !Directory(source,error)) return NO;
    NSFileManager *fm=NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:error] || !Directory(destination,error)) return NO;
    for (NSString *name in @[@"Documents",@"Library",@"tmp",@"SystemData"]) {
        if (!Copy([source stringByAppendingPathComponent:name],[destination stringByAppendingPathComponent:name],name,rules,error)) return NO;
    }
    return YES;
}
BOOL PXClearContainer(NSString *directory,NSArray *preservedPaths,NSError **error) {
    if (error) *error=nil;
    NSArray *rules=PXValidatedRelativePaths(preservedPaths ?: @[],error);
    if (!rules || !Directory(directory,error)) return NO;
    for (NSString *name in @[@"Documents",@"Library",@"tmp",@"SystemData"]) {
        NSString *path=[directory stringByAppendingPathComponent:name];
        if (!Clear(path,name,rules,error)) return NO;
        if (!EnsureDirectory(path,error)) return NO;
    }
    return YES;
}
BOOL PXCopyRelatedContainer(NSString *source,NSString *destination,NSError **error) {
    if (!Directory(source,error)) return NO;
    if (![NSFileManager.defaultManager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    return Copy(source,destination,@"",@[@".com.apple.mobile_container_manager.metadata.plist"],error);
}
BOOL PXClearRelatedContainer(NSString *directory,NSError **error) {
    if (!Directory(directory,error)) return NO;
    NSArray *children=[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:error];
    if (!children) return NO;
    for (NSString *name in children) {
        if ([name isEqual:@".com.apple.mobile_container_manager.metadata.plist"]) continue;
        if (!Clear([directory stringByAppendingPathComponent:name],name,@[],error)) return NO;
    }
    return YES;
}
BOOL PXValidateDirectoryTree(NSString *directory,NSError **error) {
    if (!Directory(directory,error)) return NO;
    NSArray *paths=[NSFileManager.defaultManager subpathsOfDirectoryAtPath:directory error:error];
    if (!paths) return NO;
    for (NSString *relative in paths) {
        struct stat st; NSString *path=[directory stringByAppendingPathComponent:relative];
        if (lstat(path.fileSystemRepresentation,&st) || (!S_ISDIR(st.st_mode) && !S_ISREG(st.st_mode))) {
            if (error) *error=PXError(@"备份包含链接或特殊文件"); return NO;
        }
    }
    return YES;
}
