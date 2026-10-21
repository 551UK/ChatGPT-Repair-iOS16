#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface CGConversationPagingState : NSObject
@property(nonatomic,copy) NSString *conversationID;
@property(nonatomic,assign) NSUInteger generation;
@property(nonatomic,strong) NSArray *messages;
@property(nonatomic,strong) NSDictionary *baseRoot;
@property(nonatomic,copy) NSString *currentNode;
@property(nonatomic,copy) NSString *startCursor;
@property(nonatomic,assign) BOOL hasPrevious;
@property(nonatomic,assign) BOOL loadedOlder;
@property(nonatomic,assign) BOOL loadingOlder;
@property(nonatomic,assign) NSTimeInterval retryNotBefore;
@property(nonatomic,strong) NSURLRequest *originalRequest;
@property(nonatomic,strong) NSURLSessionConfiguration *configuration;
@property(nonatomic,strong) NSURLResponse *responseTemplate;
@property(nonatomic,copy) void (^completion)(NSData *, NSURLResponse *, NSError *);
@property(nonatomic,weak) UIScrollView *scrollView;
@end

extern CGConversationPagingState *CGPagingState;
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
void CGPagingLoadOlder(void);
