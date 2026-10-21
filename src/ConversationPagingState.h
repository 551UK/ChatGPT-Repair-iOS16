#import <Foundation/Foundation.h>

extern NSString *CGPagingSelectedID;
extern NSUInteger CGPagingGeneration;

NSObject *CGPagingStateLock(void);
NSString *CGPagingConversationID(NSURLRequest *request);
NSURLRequest *CGPagingModernRequest(NSURLRequest *original, NSString * _Nullable before);
NSInteger CGPagingStatus(NSURLResponse * _Nullable response);
BOOL CGPagingCompatibilityFailure(NSInteger status);
BOOL CGPagingTransientFailure(NSInteger status, NSError * _Nullable error);
NSTimeInterval CGPagingRetryAfter(NSURLResponse * _Nullable response);
NSURLResponse * _Nullable CGPagingLegacyResponse(NSURLResponse * _Nullable response,
                                                  NSURL *legacyURL,
                                                  NSUInteger length);
BOOL CGPagingStillActive(NSString *cid, NSUInteger generation);
void CGPagingFetchLegacy(NSURLSessionConfiguration * _Nullable configuration,
                         NSURLRequest *request,
                         NSString *cid,
                         NSUInteger generation,
                         void (^completion)(NSData * _Nullable,
                                            NSURLResponse * _Nullable,
                                            NSError * _Nullable));
