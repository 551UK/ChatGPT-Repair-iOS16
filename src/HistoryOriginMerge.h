#import <Foundation/Foundation.h>

// Browser history has two independent, authenticated list feeds. The legacy
// ChatGPT app consumes one combined offset/limit feed, so page at the global
// offset rather than concatenating independently paginated responses.
typedef void (^CGOriginMergeCompletion)(NSData *, NSURLResponse *, NSError *);
FOUNDATION_EXPORT BOOL CGOriginMergeEligible(NSURLRequest *request);
FOUNDATION_EXPORT NSData *CGOriginMergeJSON(NSData *normalJSON, NSData *tppJSON,
                                            NSUInteger offset, NSUInteger limit);
FOUNDATION_EXPORT void CGOriginMergePage(NSURLSessionConfiguration *configuration,
                                         NSURLRequest *request, NSData *data,
                                         NSURLResponse *response, NSError *error,
                                         CGOriginMergeCompletion completion);
