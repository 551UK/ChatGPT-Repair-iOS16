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

FOUNDATION_EXPORT void CGOriginMergePageProgressive(NSURLSessionConfiguration *configuration,
                                                    NSURLRequest *request, NSData *data,
                                                    NSURLResponse *response, NSError *error,
                                                    CGOriginMergeCompletion initialCompletion,
                                                    CGOriginMergeCompletion mergedCompletion);

// If a conversation opens while an asynchronous two-origin history merge is
// still pending, immediately forward the already-valid base history result and
// ignore the late merge completion. This prevents the legacy 2024 app from
// clearing an already-loaded conversation when the history callback arrives.
FOUNDATION_EXPORT void CGOriginMergeConversationDidOpen(void);
