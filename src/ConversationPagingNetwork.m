// ChatGPTRepair: Fetch historical pages and merge complete conversations.
#import "ConversationPagingCompat.h"
#import "ConversationPagingState.h"
#import "ConversationPagingCore.h"
#import "ConversationLiveSync.h"

static NSString *sCachedConversationID;
static NSArray *sCachedMessages;

@interface NSURLSession (CGConversationPagingOriginal)
- (NSURLSessionDataTask *)cgp_dataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

// Diagnostic: log request outcomes only. No conversation text, identifiers or credentials.
static void CGPagingTrace(NSString *event, NSInteger status, NSUInteger count, NSUInteger attempt) {
    @try {
        @synchronized([NSFileManager class]) {
            NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:
                @"Documents/ChatGPTRepairLargeChat.log"];
            NSFileManager *fm=[NSFileManager defaultManager];
            NSDictionary *attrs=[fm attributesOfItemAtPath:path error:NULL];
            if ([attrs[NSFileSize] unsignedLongLongValue]>262144)
                [fm removeItemAtPath:path error:NULL];
            if (![fm fileExistsAtPath:path])
                [fm createFileAtPath:path contents:[NSData data] attributes:nil];
            NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
            if (handle) {
                [handle seekToEndOfFile];
                NSString *line=[NSString stringWithFormat:
                    @"%@ event=%@ status=%ld count=%lu attempt=%lu\n",
                    [NSDate date],event,(long)status,(unsigned long)count,
                    (unsigned long)attempt];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [handle closeFile];
            }
        }
    } @catch (__unused NSException *exception) {}
}

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
    CGPagingTrace(@"LEGACY_FALLBACK",0,0,0);
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
    CGPagingTrace(@"DELIVER_CONVERSATION",200,allMessages.count,0);
    NSData *legacy=CGConversationPagingLegacyData(newestRoot,allMessages,currentNode);
    if (!legacy.length) {
        completion(nil,responseTemplate,
            [NSError errorWithDomain:@"com.551uk.chatgptrepair.paging"
                                code:2
                            userInfo:@{NSLocalizedDescriptionKey:@"Unable to convert complete conversation page set"}]);
        return;
    }
    @synchronized(CGPagingStateLock()) {
        NSString *cid=CGPagingConversationID(originalRequest);
        if ([CGPagingSelectedID isEqualToString:cid]) {
            sCachedConversationID=[cid copy];
            sCachedMessages=[allMessages copy];
        }
    }
    CGChatSyncMarkDelivered(originalRequest,newestRoot);
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
    if (retryAttempt>=3) {
        CGPagingTrace(@"PARTIAL_HISTORY",0,newerMessages.count,retryAttempt);
        CGPagingDeliverComplete(newestRoot,newerMessages,currentNode,
                                originalRequest,responseTemplate,completion);
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
        CGPagingTrace(@"PARTIAL_HISTORY",0,newerMessages.count,retryAttempt);
        CGPagingDeliverComplete(newestRoot,newerMessages,currentNode,
                                originalRequest,responseTemplate,completion);
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
                CGPagingTrace(@"OLDER_PAGE",status,data.length,retryAttempt);
                if (CGPagingTransientFailure(status,error)) {
                    [seenCursors removeObject:before];
                    CGPagingRetryOlder(configuration,originalRequest,cid,generation,
                                       newestRoot,currentNode,newerMessages,before,
                                       seenCursors,responseTemplate,retryAttempt,response,completion);
                    return;
                }
                if (error || status<200 || status>=300) {
                    CGPagingTrace(@"PARTIAL_HISTORY",0,newerMessages.count,retryAttempt);
        CGPagingDeliverComplete(newestRoot,newerMessages,currentNode,
                                originalRequest,responseTemplate,completion);
                    return;
                }

                NSDictionary *page=CGConversationPagingJSONObject(data);
                BOOL hasPrevious=NO;
                NSString *nextCursor=nil;
                if (!page || ![page[@"page_info"] isKindOfClass:NSDictionary.class]) {
                    CGPagingTrace(@"PARTIAL_HISTORY",0,newerMessages.count,retryAttempt);
        CGPagingDeliverComplete(newestRoot,newerMessages,currentNode,
                                originalRequest,responseTemplate,completion);
                    return;
                }

                NSArray *olderMessages=CGConversationPagingMessages(page);
                nextCursor=CGConversationPagingStartCursor(page,&hasPrevious);
                if (!olderMessages.count) {
                    if (hasPrevious) {
                        CGPagingTrace(@"PARTIAL_HISTORY",0,newerMessages.count,retryAttempt);
        CGPagingDeliverComplete(newestRoot,newerMessages,currentNode,
                                originalRequest,responseTemplate,completion);
                    } else {
                        CGPagingDeliverComplete(newestRoot,newerMessages,currentNode,
                                                originalRequest,responseTemplate,completion);
                    }
                    return;
                }

                NSArray *merged=CGConversationPagingMergeMessages(olderMessages,newerMessages);
                if (merged.count<=newerMessages.count) {
                    CGPagingTrace(@"PARTIAL_HISTORY",0,newerMessages.count,retryAttempt);
        CGPagingDeliverComplete(newestRoot,newerMessages,currentNode,
                                originalRequest,responseTemplate,completion);
                    return;
                }

                if (!hasPrevious) {
                    CGPagingDeliverComplete(newestRoot,merged,currentNode,
                                            originalRequest,responseTemplate,completion);
                    return;
                }
                if (!nextCursor.length || [seenCursors containsObject:nextCursor]) {
                    CGPagingTrace(@"PARTIAL_HISTORY",0,newerMessages.count,retryAttempt);
        CGPagingDeliverComplete(newestRoot,newerMessages,currentNode,
                                originalRequest,responseTemplate,completion);
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
            CGPagingTrace(@"PARTIAL_HISTORY",0,newerMessages.count,retryAttempt);
        CGPagingDeliverComplete(newestRoot,newerMessages,currentNode,
                                originalRequest,responseTemplate,completion);
        }
    } @catch (__unused NSException *exception) {
        [session invalidateAndCancel];
        session=nil;
        CGPagingTrace(@"PARTIAL_HISTORY",0,newerMessages.count,retryAttempt);
        CGPagingDeliverComplete(newestRoot,newerMessages,currentNode,
                                originalRequest,responseTemplate,completion);
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
            sCachedConversationID=nil;
            sCachedMessages=nil;
            CGPagingGeneration++;
        }
        if (generationOut) *generationOut=CGPagingGeneration;
    }
    CGChatSyncTrackDetail(originalRequest,[NSURLSessionConfiguration defaultSessionConfiguration]);
    return CGPagingModernRequest(originalRequest,nil);
}

static void CGPagingProcessFirstResponse(
    NSURLSessionConfiguration *configuration,
    NSURLRequest *originalRequest,
    NSUInteger generation,
    NSData *data,
    NSURLResponse *response,
    NSError *error,
    NSUInteger initialAttempt,
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
    CGPagingTrace(@"FIRST_PAGE",status,data.length,initialAttempt);
    if (CGPagingTransientFailure(status,error)) {
        if (initialAttempt>=3) {
            CGPagingTrace(@"FIRST_PAGE_RETRIES_EXHAUSTED",status,0,initialAttempt);
            NSError *finalError=[NSError errorWithDomain:@"com.551uk.chatgptrepair.paging"
                code:503 userInfo:@{NSLocalizedDescriptionKey:
                    @"Paged conversation timed out after modern endpoint retries"}];
            completion(nil,nil,finalError);
            return;
        }
        NSTimeInterval delay=CGPagingBackoff(initialAttempt,response);
        CGPagingTrace(@"FIRST_PAGE_RETRY_SCHEDULED",status,0,initialAttempt);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
            if (!CGPagingStillActive(cid,generation)) {
                completion(nil,nil,CGPagingCancelledError());
                return;
            }
            NSURLRequest *modern=CGPagingModernRequest(originalRequest,nil);
            NSURLSessionConfiguration *config=[configuration copy]
                ?: [NSURLSessionConfiguration defaultSessionConfiguration];
            if (config.timeoutIntervalForRequest<30) config.timeoutIntervalForRequest=30;
            __block NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
            @try {
                NSURLSessionDataTask *task=[session cgp_dataTaskWithRequest:modern
                    completionHandler:^(NSData *nextData,NSURLResponse *nextResponse,NSError *nextError) {
                        [session finishTasksAndInvalidate];
                        session=nil;
                        CGPagingProcessFirstResponse(configuration,originalRequest,generation,
                            nextData,nextResponse,nextError,initialAttempt+1,completion);
                    }];
                if (task) [task resume];
                else {
                    [session invalidateAndCancel];
                    session=nil;
                    NSError *taskError=[NSError errorWithDomain:NSURLErrorDomain
                        code:NSURLErrorCannotConnectToHost userInfo:nil];
                    CGPagingProcessFirstResponse(configuration,originalRequest,generation,
                        nil,nil,taskError,initialAttempt+1,completion);
                }
            } @catch (__unused NSException *exception) {
                [session invalidateAndCancel];
                session=nil;
                NSError *taskError=[NSError errorWithDomain:NSURLErrorDomain
                    code:NSURLErrorCannotConnectToHost userInfo:nil];
                CGPagingProcessFirstResponse(configuration,originalRequest,generation,
                    nil,nil,taskError,initialAttempt+1,completion);
            }
        });
        return;
    }
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

    CGPagingTrace(@"FIRST_PAGE_MESSAGES",status,newest.count,hasPrevious ? 1 : 0);
    if (!hasPrevious) {
        CGPagingDeliverComplete(root,newest,current,originalRequest,response,completion);
        return;
    }
    NSArray *tailMerged=nil;
    @synchronized(CGPagingStateLock()) {
        if ([sCachedConversationID isEqualToString:cid])
            tailMerged=CGConversationPagingReplaceTail(sCachedMessages,newest);
    }
    if (tailMerged) {
        CGPagingTrace(@"LIVE_TAIL_MERGED",status,tailMerged.count,0);
        CGPagingDeliverComplete(root,tailMerged,current,originalRequest,response,completion);
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

void CGConversationPagingProcessDetailResponse(
    NSURLSessionConfiguration *configuration,
    NSURLRequest *originalRequest,
    NSUInteger generation,
    NSData *data,
    NSURLResponse *response,
    NSError *error,
    void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    CGPagingProcessFirstResponse(configuration,originalRequest,generation,
                                data,response,error,0,completion);
}
