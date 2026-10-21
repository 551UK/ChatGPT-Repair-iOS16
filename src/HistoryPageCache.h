// ChatGPTRepair: Cached older history page API.
#import <Foundation/Foundation.h>
// Preserve successful authenticated history pages and retry rate-limited
// requests at a bounded pace before returning the final result.
FOUNDATION_EXPORT void CGHistoryPageResult(NSURLRequest *request,
    NSURLSessionConfiguration *configuration, NSData *data, NSURLResponse *response,
    NSError *error, void (^completion)(NSData *, NSURLResponse *, NSError *));

