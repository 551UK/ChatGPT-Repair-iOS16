#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSURLRequest *CGConversationPagingPrepareDetailRequest(NSURLRequest *originalRequest,
                                                        NSUInteger * _Nullable generationOut);

void CGConversationPagingProcessDetailResponse(
    NSURLSessionConfiguration * _Nullable configuration,
    NSURLRequest *originalRequest,
    NSUInteger generation,
    NSData * _Nullable data,
    NSURLResponse * _Nullable response,
    NSError * _Nullable error,
    void (^completion)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable));

NS_ASSUME_NONNULL_END
