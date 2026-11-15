#import <Foundation/Foundation.h>
BOOL PXIsGPTCommandURL(NSURL *url);
NSDictionary *PXParseCommandURL(NSURL *url, NSError **error);
