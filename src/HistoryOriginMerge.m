#import "HistoryOriginMerge.h"

static NSString *const kMergeHeader = @"X-551UK-History-Merge";

@interface CGOriginPendingMerge : NSObject
@property(nonatomic,copy) CGOriginMergeCompletion completion;
@property(nonatomic,strong) NSData *data;
@property(nonatomic,strong) NSURLResponse *response;
@property(nonatomic,strong) NSError *error;
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,assign) BOOL finished;
@property(nonatomic,assign) BOOL progressive;
@end
@implementation CGOriginPendingMerge
@end

static NSObject *CGOriginPendingLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock=[NSObject new]; });
    return lock;
}
static NSMutableSet<CGOriginPendingMerge *> *CGOriginPendings(void) {
    static NSMutableSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set=[NSMutableSet set]; });
    return set;
}
static void CGOriginFinishPending(CGOriginPendingMerge *pending,
                                  NSData *data, NSURLResponse *response,
                                  NSError *error, BOOL cancelSession) {
    if (!pending) return;
    CGOriginMergeCompletion completion=nil;
    NSURLSession *session=nil;
    @synchronized(CGOriginPendingLock()) {
        if (pending.finished) return;
        pending.finished=YES;
        completion=[pending.completion copy];
        session=pending.session;
        [CGOriginPendings() removeObject:pending];
    }
    if (cancelSession && session) [session invalidateAndCancel];
    if (completion) completion(data,response,error);
}
static void CGOriginCancelPending(CGOriginPendingMerge *pending) {
    if (!pending) return;
    NSURLSession *session=nil;
    @synchronized(CGOriginPendingLock()) {
        if (pending.finished) return;
        pending.finished=YES;
        session=pending.session;
        [CGOriginPendings() removeObject:pending];
    }
    if (session) [session invalidateAndCancel];
}
void CGOriginMergeConversationDidOpen(void) {
    NSArray<CGOriginPendingMerge *> *pending=nil;
    @synchronized(CGOriginPendingLock()) {
        pending=CGOriginPendings().allObjects;
    }
    for (CGOriginPendingMerge *item in pending) {
        if (item.progressive) CGOriginCancelPending(item);
        else CGOriginFinishPending(item,item.data,item.response,item.error,YES);
    }
}

static BOOL CGValidOriginHost(NSString *host) {
    NSString *h=host.lowercaseString;
    return [h isEqualToString:@"chatgpt.com"] || [h hasSuffix:@".chatgpt.com"] ||
           [h isEqualToString:@"openai.com"] || [h hasSuffix:@".openai.com"];
}
static BOOL CGReadPage(NSURLRequest *request, NSUInteger *offset, NSUInteger *limit) {
    NSURLComponents *url=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    if (!url) return NO;
    NSUInteger off=0, lim=20;
    for (NSURLQueryItem *q in url.queryItems) {
        if (![q.name isEqualToString:@"offset"] && ![q.name isEqualToString:@"limit"]) continue;
        NSString *number=q.value ?: @"";
        if (!number.length || number.length>5 ||
            [number rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location!=NSNotFound)
            return NO;
        NSUInteger parsed=(NSUInteger)number.integerValue;
        if ([q.name isEqualToString:@"offset"]) off=parsed;
        else lim=parsed;
    }
    if (!lim || lim>50 || off>100 || off+lim>150) return NO;
    if (offset) *offset=off;
    if (limit) *limit=lim;
    return YES;
}
BOOL CGOriginMergeEligible(NSURLRequest *request) {
    if (![request.HTTPMethod.uppercaseString isEqualToString:@"GET"] ||
        !CGValidOriginHost(request.URL.host)) return NO;
    NSString *path=request.URL.path ?: @"";
    if (![path isEqualToString:@"/backend-api/conversations"] &&
        ![path isEqualToString:@"/backend-api/conversations/"]) return NO;
    if ([[request valueForHTTPHeaderField:kMergeHeader] isEqualToString:@"1"] ||
        [[request valueForHTTPHeaderField:@"X-551UK-History-Retry"] isEqualToString:@"1"]) return NO;
    NSURLComponents *url=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *q in url.queryItems) {
        if ([q.name isEqualToString:@"conversation_origin"] ||
            [q.name isEqualToString:@"query"] || [q.name isEqualToString:@"search"] ||
            [q.name isEqualToString:@"filter"] || [q.name isEqualToString:@"project_id"]) return NO;
        if (([q.name isEqualToString:@"is_archived"] || [q.name isEqualToString:@"is_starred"]) &&
            [q.value.lowercaseString isEqualToString:@"true"]) return NO;
        if ([q.name isEqualToString:@"exclude_conversation_origin"] &&
            ![q.value isEqualToString:@"tpp"]) return NO;
    }
    return CGReadPage(request,NULL,NULL);
}
static NSDictionary *CGPageDocument(NSData *data) {
    if (!data.length || data.length>4*1024*1024) return nil;
    id root=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![root isKindOfClass:NSDictionary.class] ||
        ![root[@"items"] isKindOfClass:NSArray.class] ||
        ![root[@"total"] isKindOfClass:NSNumber.class]) return nil;
    return root;
}
static NSString *CGTimeForRow(NSDictionary *row) {
    NSString *updated=[row[@"update_time"] isKindOfClass:NSString.class]?row[@"update_time"]:nil;
    NSString *created=[row[@"create_time"] isKindOfClass:NSString.class]?row[@"create_time"]:nil;
    return updated ?: created ?: @"";
}
NSData *CGOriginMergeJSON(NSData *normalJSON, NSData *tppJSON, NSUInteger offset, NSUInteger limit) {
    NSDictionary *normal=CGPageDocument(normalJSON), *tpp=CGPageDocument(tppJSON);
    if (!normal || !tpp || !limit) return nil;
    NSMutableDictionary<NSString *, NSDictionary *> *byID=[NSMutableDictionary dictionary];
    for (id row in [normal[@"items"] arrayByAddingObjectsFromArray:tpp[@"items"]]) {
        if (![row isKindOfClass:NSDictionary.class]) return nil;
        NSString *identifier=row[@"id"];
        if (![identifier isKindOfClass:NSString.class] || !identifier.length) return nil;
        NSDictionary *previous=byID[identifier];
        if (!previous || [CGTimeForRow(row) compare:CGTimeForRow(previous)]==NSOrderedDescending)
            byID[identifier]=row;
    }
    NSArray<NSDictionary *> *sorted=[byID.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult time=[CGTimeForRow(b) compare:CGTimeForRow(a)];
        if (time!=NSOrderedSame) return time;
        return [a[@"id"] compare:b[@"id"]];
    }];
    // Missing rows in the requested prefix would silently corrupt native
    // pagination. Prefer the unmodified response over a fabricated empty page.
    NSUInteger wanted=offset+limit;
    NSUInteger total=[normal[@"total"] unsignedIntegerValue]+[tpp[@"total"] unsignedIntegerValue];
    if (offset>sorted.count || (sorted.count<wanted && total>wanted)) return nil;
    NSUInteger count=MIN(limit,sorted.count-offset);
    NSArray *slice=[sorted subarrayWithRange:NSMakeRange(offset,count)];
    NSMutableDictionary *document=[normal mutableCopy];
    document[@"items"]=slice;
    document[@"total"]=@(total);
    document[@"offset"]=@(offset);
    document[@"limit"]=@(limit);
    return [NSJSONSerialization dataWithJSONObject:document options:0 error:NULL];
}
static NSMutableURLRequest *CGOriginRequest(NSURLRequest *original, BOOL tpp, NSUInteger prefix) {
    NSURLComponents *url=[NSURLComponents componentsWithURL:original.URL resolvingAgainstBaseURL:NO];
    if (!url) return nil;
    NSMutableArray<NSURLQueryItem *> *query=[NSMutableArray array];
    for (NSURLQueryItem *part in url.queryItems) {
        if ([@[@"offset",@"limit",@"conversation_origin",@"exclude_conversation_origin",@"expand",
                @"hide_snorlax",@"is_archived",@"is_starred",@"order"] containsObject:part.name]) continue;
        [query addObject:part];
    }
    [query addObject:[NSURLQueryItem queryItemWithName:tpp?@"conversation_origin":@"exclude_conversation_origin" value:@"tpp"]];
    [query addObject:[NSURLQueryItem queryItemWithName:@"expand" value:@"false"]];
    [query addObject:[NSURLQueryItem queryItemWithName:@"hide_snorlax" value:@"false"]];
    [query addObject:[NSURLQueryItem queryItemWithName:@"is_archived" value:@"false"]];
    [query addObject:[NSURLQueryItem queryItemWithName:@"is_starred" value:@"false"]];
    [query addObject:[NSURLQueryItem queryItemWithName:@"order" value:@"updated"]];
    [query addObject:[NSURLQueryItem queryItemWithName:@"offset" value:@"0"]];
    [query addObject:[NSURLQueryItem queryItemWithName:@"limit" value:[NSString stringWithFormat:@"%lu",(unsigned long)prefix]]];
    url.queryItems=query;
    if (!url.URL) return nil;
    NSMutableURLRequest *request=[original mutableCopy];
    request.URL=url.URL;
    request.cachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    [request setValue:@"1" forHTTPHeaderField:kMergeHeader];
    return request;
}
static NSString *CGOriginHeader(NSHTTPURLResponse *response, NSString *name) {
    for (id key in response.allHeaderFields) {
        if ([key isKindOfClass:NSString.class] &&
            [key caseInsensitiveCompare:name]==NSOrderedSame) {
            id value=response.allHeaderFields[key];
            return [value isKindOfClass:NSString.class]?value:[value description];
        }
    }
    return @"";
}
static NSTimeInterval CGOriginRetryDelay(NSURLResponse *response, NSUInteger attempt) {
    static const NSTimeInterval backoff[]={8,20};
    NSTimeInterval delay=backoff[MIN(attempt,1)];
    if (![response isKindOfClass:NSHTTPURLResponse.class]) return delay;
    NSString *value=CGOriginHeader((NSHTTPURLResponse *)response,@"Retry-After");
    if (!value.length) return delay;
    double seconds=value.doubleValue;
    if (seconds>0 && seconds<=90) return MAX(delay,seconds);
    return delay;
}
static void CGOriginFetchWithRetry(NSURLSession *session, NSURLRequest *request,
                                   NSUInteger attempt, NSTimeInterval startDelay,
                                   void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    if (!session || !request || !completion) return;
    void (^start)(void)=^{
        @try {
            [[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
                NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]
                    ?((NSHTTPURLResponse *)response).statusCode:0;
                if (!error && status==429 && attempt<2) {
                    NSTimeInterval retryDelay=CGOriginRetryDelay(response,attempt);
                    CGOriginFetchWithRetry(session,request,attempt+1,retryDelay,completion);
                    return;
                }
                completion(data,response,error);
            }] resume];
        } @catch (__unused NSException *exception) {
            NSError *cancel=[NSError errorWithDomain:NSURLErrorDomain
                code:NSURLErrorCancelled
                userInfo:@{NSLocalizedDescriptionKey:@"History merge retry session was no longer active"}];
            completion(nil,nil,cancel);
        }
    };
    if (startDelay>0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(startDelay*NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY,0),start);
    } else {
        start();
    }
}
void CGOriginMergePageProgressive(NSURLSessionConfiguration *configuration, NSURLRequest *request,
                                  NSData *data, NSURLResponse *response, NSError *error,
                                  CGOriginMergeCompletion initialCompletion,
                                  CGOriginMergeCompletion mergedCompletion) {
    if (!initialCompletion) return;
    NSInteger code=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
    NSUInteger offset=0, limit=0;
    if (error || code!=200 || !CGOriginMergeEligible(request) ||
        !CGReadPage(request,&offset,&limit) || offset!=0 || !CGPageDocument(data)) {
        initialCompletion(data,response,error);
        return;
    }

    initialCompletion(data,response,error);
    if (!mergedCompletion) return;

    NSMutableURLRequest *tpp=CGOriginRequest(request,YES,limit);
    if (!tpp) return;

    NSURLSessionConfiguration *config=[configuration copy] ?: [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest=12;
    config.timeoutIntervalForResource=30;
    __block NSURLSession *session=[NSURLSession sessionWithConfiguration:config];

    CGOriginPendingMerge *pending=[CGOriginPendingMerge new];
    pending.completion=mergedCompletion;
    pending.response=response;
    pending.session=session;
    pending.progressive=YES;
    @synchronized(CGOriginPendingLock()) {
        [CGOriginPendings() addObject:pending];
    }

    BOOL baseWasRateLimitFallback=NO;
    if ([response isKindOfClass:NSHTTPURLResponse.class]) {
        baseWasRateLimitFallback=[CGOriginHeader((NSHTTPURLResponse *)response,@"X-551UK-History-Cache")
                                  isEqualToString:@"rate-limit-fallback"];
    }
    NSTimeInterval initialDelay=baseWasRateLimitFallback?8.0:0.0;
    CGOriginFetchWithRetry(session,tpp,0,initialDelay,^(NSData *tppData, NSURLResponse *reply, NSError *networkError) {
        NSInteger status=[reply isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)reply).statusCode:0;
        NSData *merged=nil;
        if (!networkError && status==200 && CGPageDocument(tppData))
            merged=CGOriginMergeJSON(data,tppData,0,limit);

        [session finishTasksAndInvalidate];
        session=nil;

        if (!merged) {
            CGOriginCancelPending(pending);
            return;
        }
        CGOriginFinishPending(pending,merged,response,nil,NO);
    });
}

void CGOriginMergePage(NSURLSessionConfiguration *configuration, NSURLRequest *request,
                       NSData *data, NSURLResponse *response, NSError *error,
                       CGOriginMergeCompletion completion) {
    if (!completion) return;
    NSInteger code=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
    NSUInteger offset=0, limit=0;
    if (error || code!=200 || !CGOriginMergeEligible(request) ||
        !CGReadPage(request,&offset,&limit) || !CGPageDocument(data)) {
        completion(data,response,error);
        return;
    }
    NSUInteger prefix=offset+limit;
    NSMutableURLRequest *tpp=CGOriginRequest(request,YES,prefix);
    NSMutableURLRequest *normal=offset?CGOriginRequest(request,NO,prefix):nil;
    if (!tpp || (offset && !normal)) { completion(data,response,error); return; }

    NSURLSessionConfiguration *config=[configuration copy] ?: [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest=12;
    config.timeoutIntervalForResource=30;
    __block NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
    CGOriginPendingMerge *pending=[CGOriginPendingMerge new];
    pending.completion=completion;
    pending.data=data;
    pending.response=response;
    pending.error=error;
    pending.session=session;
    @synchronized(CGOriginPendingLock()) {
        [CGOriginPendings() addObject:pending];
    }

    dispatch_group_t group=dispatch_group_create();
    NSObject *lock=[NSObject new];
    __block NSData *tppData=nil, *normalData=offset?nil:data;
    __block BOOL failed=NO;
    NSArray<NSURLRequest *> *requests=normal?@[tpp,normal]:@[tpp];
    BOOL baseWasRateLimitFallback=NO;
    if ([response isKindOfClass:NSHTTPURLResponse.class]) {
        baseWasRateLimitFallback=[CGOriginHeader((NSHTTPURLResponse *)response,@"X-551UK-History-Cache")
                                  isEqualToString:@"rate-limit-fallback"];
    }
    for (NSURLRequest *extra in requests) {
        BOOL isTPP=(extra==tpp);
        dispatch_group_enter(group);
        // When the base page only succeeded via the local 429 fallback, do
        // not immediately hammer the history endpoint again for TPP.
        NSTimeInterval initialDelay=baseWasRateLimitFallback?8.0:0.0;
        CGOriginFetchWithRetry(session,extra,0,initialDelay,^(NSData *more, NSURLResponse *reply, NSError *networkError) {
            NSInteger status=[reply isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)reply).statusCode:0;
            @synchronized(lock) {
                if (networkError || status!=200 || !CGPageDocument(more)) failed=YES;
                else if (isTPP) tppData=more;
                else normalData=more;
            }
            dispatch_group_leave(group);
        });
    }
    dispatch_group_notify(group,dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSData *merged=nil;
        @synchronized(lock) {
            if (!failed && normalData && tppData)
                merged=CGOriginMergeJSON(normalData,tppData,offset,limit);
        }
        [session finishTasksAndInvalidate];
        session=nil;
        // If a conversation was opened while this merge was pending, that
        // path already forwarded the base response and marked this finished.
        // Otherwise deliver the combined page exactly once.
        CGOriginFinishPending(pending,merged?:data,response,error,NO);
    });
}
