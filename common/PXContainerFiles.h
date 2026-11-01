#import <Foundation/Foundation.h>
BOOL PXCopyContainer(NSString *source, NSString *destination, NSArray<NSString *> *preservedPaths, NSError **error);
BOOL PXClearContainer(NSString *directory, NSArray<NSString *> *preservedPaths, NSError **error);
BOOL PXCopyRelatedContainer(NSString *source, NSString *destination, NSError **error);
BOOL PXClearRelatedContainer(NSString *directory, NSError **error);
BOOL PXValidateDirectoryTree(NSString *directory, NSError **error);
