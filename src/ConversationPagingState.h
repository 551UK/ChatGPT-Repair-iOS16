#import <Foundation/Foundation.h>

extern NSString *CGPagingSelectedID;
extern NSUInteger CGPagingGeneration;

NSObject *CGPagingStateLock(void);
NSString *CGPagingConversationID(NSURLRequest *request);
NSURLRequest *CGPagingModernRequest(NSURLRequest *original, NSString *before);
NSInteger CGPagingStatus(NSURLResponse *response);
BOOL CGPagingCompatibilityFailure(NSInteger status);
BOOL CGPagingTransientFailure(NSInteger status, NSError *error);
NSTimeInterval CGPagingRetryAfter(NSURLResponse *response);
NSURLResponse *CGPagingLegacyResponse(NSURLResponse *response, NSURL *legacyURL, NSUInteger length);
BOOL CGPagingStillActive(NSString *cid, NSUInteger generation);
BOOL CGPagingValidPageRoot(NSDictionary *root, BOOL *hasPrevious, NSString **cursor);
void CGPagingFetchLegacy(NSURLSessionConfiguration *configuration, NSURLRequest *request,
                         NSString *cid, NSUInteger generation,
                         void (^completion)(NSData *,NSURLResponse *,NSError *));
