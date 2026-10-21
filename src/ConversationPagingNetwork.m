#import "ConversationPagingCompat.h"
#import "ConversationPagingState.h"
#import "ConversationPagingCore.h"

@interface NSURLSession (CGConversationPagingOriginal)
- (NSURLSessionDataTask *)cgp_dataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

@interface CGConversationPageGather : NSObject
@property(nonatomic,copy) NSString *conversationID;
@property(nonatomic,assign) NSUInteger generation;
@property(nonatomic,strong) NSURLRequest *originalRequest;
@property(nonatomic,strong) NSURLSessionConfiguration *configuration;
@property(nonatomic,strong) NSDictionary *root;
@property(nonatomic,strong) NSArray *messages;
@property(nonatomic,strong) NSURLResponse *responseTemplate;
@property(nonatomic,copy) NSString *currentNode;
@property(nonatomic,copy) NSString *cursor;
@property(nonatomic,strong) NSMutableSet<NSString *> *seenCursors;
@property(nonatomic,assign) NSUInteger pageCount;
@property(nonatomic,copy) void (^completion)(NSData *,NSURLResponse *,NSError *);
@end
@implementation CGConversationPageGather
@end

static void CGPagingFinishLegacy(CGConversationPageGather *job) {
    if (!job || !CGPagingStillActive(job.conversationID,job.generation)) return;
    NSData *legacy=CGConversationPagingLegacyData(job.root,job.messages,job.currentNode);
    if (!legacy.length) {
        CGPagingFetchLegacy(job.configuration,job.originalRequest,
                            job.conversationID,job.generation,job.completion);
        return;
    }
    job.completion(legacy,
        CGPagingLegacyResponse(job.responseTemplate,job.originalRequest.URL,legacy.length),nil);
}

static void CGPagingFallback(CGConversationPageGather *job) {
    if (!job || !CGPagingStillActive(job.conversationID,job.generation)) return;
    CGPagingFetchLegacy(job.configuration,job.originalRequest,
                        job.conversationID,job.generation,job.completion);
}

static void CGPagingFetchOlderPage(CGConversationPageGather *job);

static void CGPagingScheduleOlderPage(CGConversationPageGather *job, NSTimeInterval delay) {
    if (!job) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(MAX(0.15,delay)*NSEC_PER_SEC)),
        dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
            CGPagingFetchOlderPage(job);
        });
}

static void CGPagingFetchOlderPage(CGConversationPageGather *job) {
    if (!job || !CGPagingStillActive(job.conversationID,job.generation)) return;
    if (!job.cursor.length || job.pageCount>=256) {
        CGPagingFallback(job);
        return;
    }
    if ([job.seenCursors containsObject:job.cursor]) {
        CGPagingFallback(job);
        return;
    }
    [job.seenCursors addObject:job.cursor];

    NSURLRequest *request=CGPagingModernRequest(job.originalRequest,job.cursor);
    NSURLSessionConfiguration *config=[job.configuration copy] ?:
        [NSURLSessionConfiguration defaultSessionConfiguration];
    if (config.timeoutIntervalForRequest<30) config.timeoutIntervalForRequest=30;
    __block NSURLSession *session=[NSURLSession sessionWithConfiguration:config];

    @try {
        NSURLSessionDataTask *task=[session cgp_dataTaskWithRequest:request
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                [session finishTasksAndInvalidate];
                session=nil;
                if (!CGPagingStillActive(job.conversationID,job.generation)) return;

                NSInteger status=CGPagingStatus(response);
                if (CGPagingTransientFailure(status,error)) {
                    NSTimeInterval delay=CGPagingRetryAfter(response);
                    if (delay<=0) delay=2.0;
                    if (delay>120) { CGPagingFallback(job); return; }
                    CGPagingScheduleOlderPage(job,delay);
                    return;
                }
                if (error || status<200 || status>=300) {
                    CGPagingFallback(job);
                    return;
                }

                NSDictionary *page=CGConversationPagingJSONObject(data);
                BOOL hasPrevious=NO;
                NSString *cursor=nil;
                if (!page || !CGPagingValidPageRoot(page,&hasPrevious,&cursor) ||
                    CGConversationPagingHasVersionMarkers(page)) {
                    CGPagingFallback(job);
                    return;
                }

                NSArray *older=CGConversationPagingMessages(page);
                if (!older.count) {
                    if (hasPrevious) CGPagingFallback(job);
                    else CGPagingFinishLegacy(job);
                    return;
                }

                NSUInteger beforeCount=job.messages.count;
                NSArray *merged=CGConversationPagingMergeMessages(older,job.messages);
                if (merged.count<=beforeCount) {
                    CGPagingFallback(job);
                    return;
                }

                job.messages=merged;
                job.pageCount++;

                if (!hasPrevious) {
                    CGPagingFinishLegacy(job);
                    return;
                }
                if (!cursor.length || [cursor isEqualToString:job.cursor]) {
                    CGPagingFallback(job);
                    return;
                }
                job.cursor=cursor;
                CGPagingScheduleOlderPage(job,0.05);
            }];
        if (task) [task resume];
        else {
            [session invalidateAndCancel];
            session=nil;
            CGPagingFallback(job);
        }
    } @catch (__unused NSException *exception) {
        [session invalidateAndCancel];
        session=nil;
        CGPagingFallback(job);
    }
}

NSURLRequest *CGConversationPagingPrepareDetailRequest(NSURLRequest *originalRequest,
                                                        NSUInteger *generationOut) {
    if (generationOut) *generationOut=0;
    NSString *cid=CGPagingConversationID(originalRequest);
    if (!cid.length) return originalRequest;

    @synchronized(CGPagingStateLock()) {
        // Every real detail load gets a new generation, even when the user
        // reopens the same conversation. This cancels any older gather still
        // walking cursors for that chat.
        CGPagingSelectedID=[cid copy];
        CGPagingGeneration++;
        if (generationOut) *generationOut=CGPagingGeneration;
    }
    return CGPagingModernRequest(originalRequest,nil);
}

void CGConversationPagingProcessDetailResponse(
    NSURLSessionConfiguration *configuration, NSURLRequest *originalRequest,
    NSUInteger generation, NSData *data, NSURLResponse *response, NSError *error,
    void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    NSString *cid=CGPagingConversationID(originalRequest);
    if (!cid.length || !generation || !completion) {
        if (completion) completion(data,response,error);
        return;
    }
    if (!CGPagingStillActive(cid,generation)) return;

    NSInteger status=CGPagingStatus(response);
    if (CGPagingTransientFailure(status,error)) {
        // The existing 2024 detail retry path is battle-tested; fall back to
        // that rather than exposing a partial paginated conversation.
        CGPagingFetchLegacy(configuration,originalRequest,cid,generation,completion);
        return;
    }
    if (error || status<200 || status>=300) {
        CGPagingFetchLegacy(configuration,originalRequest,cid,generation,completion);
        return;
    }

    NSDictionary *root=CGConversationPagingJSONObject(data);
    BOOL hasPrevious=NO;
    NSString *cursor=nil;
    if (!root || !CGPagingValidPageRoot(root,&hasPrevious,&cursor) ||
        CGConversationPagingHasVersionMarkers(root)) {
        CGPagingFetchLegacy(configuration,originalRequest,cid,generation,completion);
        return;
    }

    NSArray *messages=CGConversationPagingMessages(root);
    if (!messages.count) {
        CGPagingFetchLegacy(configuration,originalRequest,cid,generation,completion);
        return;
    }

    NSString *current=[root[@"current_node"] isKindOfClass:NSString.class]
        ?root[@"current_node"]:nil;
    if (!current.length) {
        NSDictionary *raw=[messages.lastObject isKindOfClass:NSDictionary.class]
            ?messages.lastObject:nil;
        NSDictionary *message=[raw[@"message"] isKindOfClass:NSDictionary.class]
            ?raw[@"message"]:raw;
        id identifier=message[@"id"] ?: message[@"message_id"];
        if ([identifier isKindOfClass:NSString.class]) current=identifier;
    }

    if (!hasPrevious) {
        NSData *legacy=CGConversationPagingLegacyData(root,messages,current);
        if (legacy.length) {
            completion(legacy,
                CGPagingLegacyResponse(response,originalRequest.URL,legacy.length),nil);
        } else {
            CGPagingFetchLegacy(configuration,originalRequest,cid,generation,completion);
        }
        return;
    }

    if (!cursor.length) {
        CGPagingFetchLegacy(configuration,originalRequest,cid,generation,completion);
        return;
    }

    // The 2026 app can render page 1 immediately because its repository and
    // MessagesViewModel understand incremental paging. ChatGPT 1.2024.200
    // cannot. Therefore gather every older page first and invoke the legacy
    // completion exactly once with one complete mapping tree.
    CGConversationPageGather *job=[CGConversationPageGather new];
    job.conversationID=cid;
    job.generation=generation;
    job.originalRequest=[originalRequest copy];
    job.configuration=[configuration copy] ?:
        [NSURLSessionConfiguration defaultSessionConfiguration];
    job.root=root;
    job.messages=messages;
    job.responseTemplate=response;
    job.currentNode=current;
    job.cursor=cursor;
    job.seenCursors=[NSMutableSet set];
    job.pageCount=1;
    job.completion=[completion copy];

    CGPagingFetchOlderPage(job);
}
