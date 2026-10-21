#import "ConversationPagingCompat.h"
#import "ConversationPagingState.h"
#import "ConversationPagingCore.h"

@interface NSURLSession (CGConversationPagingOriginal)
- (NSURLSessionDataTask *)cgp_dataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

static NSError *CGPagingCancelledError(void) {
    return [NSError errorWithDomain:NSURLErrorDomain
                               code:NSURLErrorCancelled
                           userInfo:nil];
}

static void CGPagingFinishFallback(NSURLSessionConfiguration *configuration,
                                   NSURLRequest *originalRequest,
                                   NSString *cid,
                                   NSUInteger generation,
                                   void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    CGPagingFetchLegacy(configuration,originalRequest,cid,generation,completion);
}

static NSTimeInterval CGPagingBackoff(NSUInteger attempt, NSURLResponse *response) {
    static const NSTimeInterval delays[]={2,5,10,20,30,45,60};
    NSTimeInterval delay=delays[MIN(attempt,6)];
    NSTimeInterval server=CGPagingRetryAfter(response);
    return MAX(delay,server);
}

static void CGPagingDeliverComplete(NSDictionary *newestRoot,
                                    NSArray *allMessages,
                                    NSString *currentNode,
                                    NSURLRequest *originalRequest,
                                    NSURLResponse *responseTemplate,
                                    void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    NSData *legacy=CGConversationPagingLegacyData(newestRoot,allMessages,currentNode);
    if (!legacy.length) {
        completion(nil,responseTemplate,
            [NSError errorWithDomain:@"com.551uk.chatgptrepair.paging"
                                code:2
                            userInfo:@{NSLocalizedDescriptionKey:@"Unable to convert complete conversation page set"}]);
        return;
    }
    completion(legacy,
               CGPagingLegacyResponse(responseTemplate,originalRequest.URL,legacy.length),
               nil);
}

static void CGPagingFetchOlderPage(NSURLSessionConfiguration *configuration,
                                   NSURLRequest *originalRequest,
                                   NSString *cid,
                                   NSUInteger generation,
                                   NSDictionary *newestRoot,
                                   NSString *currentNode,
                                   NSArray *newerMessages,
                                   NSString *before,
                                   NSMutableSet<NSString *> *seenCursors,
                                   NSURLResponse *responseTemplate,
                                   NSUInteger retryAttempt,
                                   void (^completion)(NSData *,NSURLResponse *,NSError *));

static void CGPagingRetryOlder(NSURLSessionConfiguration *configuration,
                               NSURLRequest *originalRequest,
                               NSString *cid,
                               NSUInteger generation,
                               NSDictionary *newestRoot,
                               NSString *currentNode,
                               NSArray *newerMessages,
                               NSString *before,
                               NSMutableSet<NSString *> *seenCursors,
                               NSURLResponse *responseTemplate,
                               NSUInteger retryAttempt,
                               NSURLResponse *failedResponse,
                               void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    if (retryAttempt>=7) {
        CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
        return;
    }
    NSTimeInterval delay=CGPagingBackoff(retryAttempt,failedResponse);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        if (!CGPagingStillActive(cid,generation)) {
            completion(nil,nil,CGPagingCancelledError());
            return;
        }
        CGPagingFetchOlderPage(configuration,originalRequest,cid,generation,
                               newestRoot,currentNode,newerMessages,before,
                               seenCursors,responseTemplate,retryAttempt+1,completion);
    });
}

static void CGPagingFetchOlderPage(NSURLSessionConfiguration *configuration,
                                   NSURLRequest *originalRequest,
                                   NSString *cid,
                                   NSUInteger generation,
                                   NSDictionary *newestRoot,
                                   NSString *currentNode,
                                   NSArray *newerMessages,
                                   NSString *before,
                                   NSMutableSet<NSString *> *seenCursors,
                                   NSURLResponse *responseTemplate,
                                   NSUInteger retryAttempt,
                                   void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    if (!CGPagingStillActive(cid,generation)) {
        completion(nil,nil,CGPagingCancelledError());
        return;
    }
    if (!before.length || [seenCursors containsObject:before]) {
        CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
        return;
    }
    [seenCursors addObject:before];

    NSURLRequest *pageRequest=CGPagingModernRequest(originalRequest,before);
    NSURLSessionConfiguration *config=[configuration copy] ?: [NSURLSessionConfiguration defaultSessionConfiguration];
    if (config.timeoutIntervalForRequest<30) config.timeoutIntervalForRequest=30;
    __block NSURLSession *session=[NSURLSession sessionWithConfiguration:config];

    @try {
        NSURLSessionDataTask *task=[session cgp_dataTaskWithRequest:pageRequest completionHandler:
            ^(NSData *data, NSURLResponse *response, NSError *error) {
                [session finishTasksAndInvalidate];
                session=nil;

                if (!CGPagingStillActive(cid,generation)) {
                    completion(nil,nil,CGPagingCancelledError());
                    return;
                }

                NSInteger status=CGPagingStatus(response);
                if (CGPagingTransientFailure(status,error)) {
                    [seenCursors removeObject:before];
                    CGPagingRetryOlder(configuration,originalRequest,cid,generation,
                                       newestRoot,currentNode,newerMessages,before,
                                       seenCursors,responseTemplate,retryAttempt,response,completion);
                    return;
                }
                if (error || status<200 || status>=300) {
                    CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
                    return;
                }

                NSDictionary *page=CGConversationPagingJSONObject(data);
                BOOL hasPrevious=NO;
                NSString *nextCursor=nil;
                if (!page || ![page[@"page_info"] isKindOfClass:NSDictionary.class]) {
                    CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
                    return;
                }

                NSArray *olderMessages=CGConversationPagingMessages(page);
                nextCursor=CGConversationPagingStartCursor(page,&hasPrevious);
                if (!olderMessages.count) {
                    if (hasPrevious) {
                        CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
                    } else {
                        CGPagingDeliverComplete(newestRoot,newerMessages,currentNode,
                                                originalRequest,responseTemplate,completion);
                    }
                    return;
                }

                NSArray *merged=CGConversationPagingMergeMessages(olderMessages,newerMessages);
                if (merged.count<=newerMessages.count) {
                    CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
                    return;
                }

                if (!hasPrevious) {
                    CGPagingDeliverComplete(newestRoot,merged,currentNode,
                                            originalRequest,responseTemplate,completion);
                    return;
                }
                if (!nextCursor.length || [seenCursors containsObject:nextCursor]) {
                    CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
                    return;
                }

                CGPagingFetchOlderPage(configuration,originalRequest,cid,generation,
                                       newestRoot,currentNode,merged,nextCursor,
                                       seenCursors,responseTemplate,0,completion);
            }];
        if (task) {
            [task resume];
        } else {
            [session invalidateAndCancel];
            session=nil;
            CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
        }
    } @catch (__unused NSException *exception) {
        [session invalidateAndCancel];
        session=nil;
        CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
    }
}

NSURLRequest *CGConversationPagingPrepareDetailRequest(NSURLRequest *originalRequest,
                                                        NSUInteger *generationOut) {
    if (generationOut) *generationOut=0;
    NSString *cid=CGPagingConversationID(originalRequest);
    if (!cid.length) return originalRequest;

    @synchronized(CGPagingStateLock()) {
        if (![CGPagingSelectedID isEqualToString:cid]) {
            CGPagingSelectedID=[cid copy];
            CGPagingGeneration++;
            CGPagingState=nil;
        }
        if (generationOut) *generationOut=CGPagingGeneration;
    }
    return CGPagingModernRequest(originalRequest,nil);
}

void CGConversationPagingProcessDetailResponse(
    NSURLSessionConfiguration *configuration,
    NSURLRequest *originalRequest,
    NSUInteger generation,
    NSData *data,
    NSURLResponse *response,
    NSError *error,
    void (^completion)(NSData *, NSURLResponse *, NSError *)) {

    NSString *cid=CGPagingConversationID(originalRequest);
    if (!cid.length || !generation || !completion) {
        if (completion) completion(data,response,error);
        return;
    }
    if (!CGPagingStillActive(cid,generation)) {
        completion(nil,nil,CGPagingCancelledError());
        return;
    }

    NSInteger status=CGPagingStatus(response);
    if (error || status<200 || status>=300) {
        if (!error && CGPagingCompatibilityFailure(status)) {
            CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
        } else {
            // Let the existing legacy detail retry layer handle transient
            // failure of the very first page. It already preserves selection
            // generation and Retry-After semantics.
            completion(data,response,error);
        }
        return;
    }

    NSDictionary *root=CGConversationPagingJSONObject(data);
    BOOL hasPrevious=NO;
    NSString *cursor=nil;
    if (!root || ![root[@"page_info"] isKindOfClass:NSDictionary.class]) {
        CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
        return;
    }

    NSArray *newest=CGConversationPagingMessages(root);
    cursor=CGConversationPagingStartCursor(root,&hasPrevious);
    if (!newest.count) {
        CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
        return;
    }

    NSString *current=[root[@"current_node"] isKindOfClass:NSString.class]?root[@"current_node"]:nil;
    if (!current.length) {
        NSDictionary *raw=[newest.lastObject isKindOfClass:NSDictionary.class]?newest.lastObject:nil;
        NSDictionary *message=[raw[@"message"] isKindOfClass:NSDictionary.class]?raw[@"message"]:raw;
        id identifier=message[@"id"] ?: message[@"message_id"];
        if ([identifier isKindOfClass:NSString.class]) current=identifier;
    }

    if (!hasPrevious) {
        CGPagingDeliverComplete(root,newest,current,originalRequest,response,completion);
        return;
    }
    if (!cursor.length) {
        CGPagingFinishFallback(configuration,originalRequest,cid,generation,completion);
        return;
    }

    NSMutableSet<NSString *> *seen=[NSMutableSet set];
    CGPagingFetchOlderPage(configuration,originalRequest,cid,generation,
                           root,current,newest,cursor,seen,response,0,completion);
}
