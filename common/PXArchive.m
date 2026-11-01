#import "PXArchive.h"
#import "PXConfiguration.h"
#include <stdint.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

// iOS exposes libarchive but some Theos SDKs omit its public headers.
// These declarations use the stable libarchive C ABI, also checked on macOS.
#if __has_include(<archive.h>)
#include <archive.h>
#include <archive_entry.h>
#else
struct archive; struct archive_entry;
struct archive *archive_write_new(void);
int archive_write_set_format_zip(struct archive *);
int archive_write_open_filename(struct archive *,const char *);
int archive_write_header(struct archive *,struct archive_entry *);
ssize_t archive_write_data(struct archive *,const void *,size_t);
int archive_write_close(struct archive *);
int archive_write_free(struct archive *);
struct archive *archive_read_new(void);
int archive_read_support_format_zip(struct archive *);
int archive_read_support_filter_all(struct archive *);
int archive_read_open_filename(struct archive *,const char *,size_t);
int archive_read_next_header(struct archive *,struct archive_entry **);
ssize_t archive_read_data(struct archive *,void *,size_t);
int archive_read_free(struct archive *);
const char *archive_error_string(struct archive *);
struct archive_entry *archive_entry_new(void);
void archive_entry_free(struct archive_entry *);
void archive_entry_set_pathname(struct archive_entry *,const char *);
void archive_entry_set_filetype(struct archive_entry *,unsigned int);
void archive_entry_set_perm(struct archive_entry *,mode_t);
void archive_entry_set_size(struct archive_entry *,int64_t);
const char *archive_entry_pathname(struct archive_entry *);
unsigned int archive_entry_filetype(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
#endif

static BOOL ArchiveFailure(struct archive *a, NSError **error) {
    const char *message=a?archive_error_string(a):NULL;
    if (error) *error=PXError(message?[NSString stringWithUTF8String:message]:@"归档操作失败");
    return NO;
}
BOOL PXCreateArchive(NSString *directory, NSString *destination, NSError **error) {
    if (error) *error=nil;
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *temporary=[destination stringByAppendingFormat:@".%@.tmp",NSUUID.UUID.UUIDString];
    struct archive *a=archive_write_new();
    BOOL ok=a && archive_write_set_format_zip(a)==0 && archive_write_open_filename(a,temporary.fileSystemRepresentation)==0;
    NSArray *paths=ok?[fm subpathsOfDirectoryAtPath:directory error:error]:nil;
    if (!paths) ok=NO;
    uint8_t buffer[65536];
    for (NSString *relative in paths) {
        if (!ok) break;
        NSString *path=[directory stringByAppendingPathComponent:relative];
        struct stat st;
        if (lstat(path.fileSystemRepresentation,&st) || (!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode))) {
            if (error) *error=PXError(@"备份包含符号链接或特殊文件，未导出"); ok=NO; break;
        }
        struct archive_entry *entry=archive_entry_new();
        archive_entry_set_pathname(entry,relative.UTF8String);
        archive_entry_set_filetype(entry,S_ISDIR(st.st_mode)?S_IFDIR:S_IFREG);
        archive_entry_set_perm(entry,S_ISDIR(st.st_mode)?0700:0600);
        archive_entry_set_size(entry,S_ISDIR(st.st_mode)?0:st.st_size);
        ok=archive_write_header(a,entry)==0; archive_entry_free(entry);
        if (!ok || S_ISDIR(st.st_mode)) continue;
        int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
        if (fd<0) { ok=NO; break; }
        ssize_t length;
        while ((length=read(fd,buffer,sizeof(buffer)))>0) {
            if (archive_write_data(a,buffer,(size_t)length)!=length) { ok=NO; break; }
        }
        if (length<0) ok=NO;
        close(fd);
    }
    if (ok) ok=archive_write_close(a)==0;
    if (!ok && error && !*error) ArchiveFailure(a,error);
    if (a) archive_write_free(a);
    if (ok) ok=[fm moveItemAtPath:temporary toPath:destination error:error];
    if (!ok) [fm removeItemAtPath:temporary error:NULL];
    return ok;
}
BOOL PXExtractArchive(NSString *archivePath, NSString *destination, NSError **error) {
    if (error) *error=nil;
    NSFileManager *fm=NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:destination]) { if (error) *error=PXError(@"导入暂存目录已存在"); return NO; }
    if (![fm createDirectoryAtPath:destination withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
    struct archive *a=archive_read_new();
    if (!a) { [fm removeItemAtPath:destination error:NULL]; return ArchiveFailure(NULL,error); }
    archive_read_support_format_zip(a); archive_read_support_filter_all(a);
    BOOL ok=archive_read_open_filename(a,archivePath.fileSystemRepresentation,65536)==0;
    uint64_t total=0; NSUInteger count=0; NSMutableSet *seen=[NSMutableSet set];
    int result=0; struct archive_entry *entry=NULL;
    uint8_t buffer[65536];
    while (ok && (result=archive_read_next_header(a,&entry))==0) {
        const char *raw=archive_entry_pathname(entry);
        NSString *name=raw?[NSString stringWithUTF8String:raw]:nil;
        unsigned type=archive_entry_filetype(entry);
        NSArray *components=[name componentsSeparatedByString:@"/"];
        if (!name.length || name.isAbsolutePath || [components containsObject:@".."] ||
            [name containsString:@"\\"] || archive_entry_symlink(entry) || archive_entry_hardlink(entry) ||
            (type!=S_IFREG && type!=S_IFDIR) || ++count>100000 || archive_entry_size(entry)<0 ||
            archive_entry_size(entry)>(int64_t)(8ULL<<30)) {
            if (error) *error=PXError(@"归档中存在不安全路径、链接、特殊文件或超限条目"); ok=NO; break;
        }
        name=name.stringByStandardizingPath;
        if ([name isEqual:@"."] || [seen containsObject:name]) { if (error) *error=PXError(@"归档路径重复"); ok=NO; break; }
        [seen addObject:name];
        NSString *path=[destination stringByAppendingPathComponent:name];
        NSString *parent=path.stringByDeletingLastPathComponent;
        if (![fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) { ok=NO; break; }
        if (type==S_IFDIR) {
            if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) ok=NO;
            continue;
        }
        int fd=open(path.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);
        if (fd<0) { if (error) *error=PXError(@"无法创建导入文件"); ok=NO; break; }
        ssize_t length; int64_t fileSize=0;
        while ((length=archive_read_data(a,buffer,sizeof(buffer)))>0) {
            total+=(uint64_t)length; fileSize+=length;
            if (total>(8ULL<<30) || fileSize>archive_entry_size(entry)) { ok=NO; break; }
            ssize_t written=0;
            while (written<length) {
                ssize_t n=write(fd,buffer+written,(size_t)(length-written));
                if (n<=0) { ok=NO; break; }
                written+=n;
            }
            if (!ok) break;
        }
        if (length<0 || fileSize!=archive_entry_size(entry)) ok=NO;
        if (close(fd)) ok=NO;
    }
    if (result!=1) ok=NO; // ARCHIVE_EOF is 1.
    if (!ok && error && !*error) ArchiveFailure(a,error);
    archive_read_free(a);
    if (!ok) [fm removeItemAtPath:destination error:NULL];
    return ok;
}
