#import <Foundation/Foundation.h>
// Preserve exact successful page bytes when the same authenticated request
// is rate limited. This function never starts a network request.
FOUNDATION_EXPORT void CGHistoryPageResult(NSURLRequest *request,
    NSURLSessionConfiguration *configuration, NSData *data, NSURLResponse *response,
    NSError *error, void (^completion)(NSData *, NSURLResponse *, NSError *));

