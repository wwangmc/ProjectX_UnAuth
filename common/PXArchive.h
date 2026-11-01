#import <Foundation/Foundation.h>
BOOL PXCreateArchive(NSString *directory, NSString *destination, NSError **error);
// Destination must not exist. The entire staging tree is removed on failure.
BOOL PXExtractArchive(NSString *archivePath, NSString *destination, NSError **error);
