// ChatGPTRepair: Conversation-page loading state declarations.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * _Nullable CGPagingSelectedID;
extern NSUInteger CGPagingGeneration;

NSObject *CGPagingStateLock(void);
NSString * _Nullable CGPagingConversationID(NSURLRequest *request);
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

NS_ASSUME_NONNULL_END
