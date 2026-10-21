#import "ConversationPagingState.h"
#import "ConversationPagingCore.h"
#include <math.h>

static const NSUInteger kConversationPageSize=10;

@interface NSURLSession (CGConversationPagingOriginal)
- (NSURLSessionDataTask *)cgp_dataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

@implementation CGConversationPagingState
@end

CGConversationPagingState *CGPagingState;
NSString *CGPagingSelectedID;
NSUInteger CGPagingGeneration=0;

NSObject *CGPagingStateLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock=[NSObject new]; });
    return lock;
}

static BOOL CGPagingTrustedHost(NSString *host) {
    NSString *h=host.lowercaseString ?: @"";
    return [h isEqualToString:@"chatgpt.com"] || [h hasSuffix:@".chatgpt.com"] ||
           [h isEqualToString:@"openai.com"] || [h hasSuffix:@".openai.com"];
}

NSString *CGPagingConversationID(NSURLRequest *request) {
    if (![request.HTTPMethod.uppercaseString isEqualToString:@"GET"] ||
        !CGPagingTrustedHost(request.URL.host)) return nil;
    NSArray *parts=[(request.URL.path ?: @"") componentsSeparatedByString:@"/"];
    if (parts.count==4 && [parts[1] isEqualToString:@"backend-api"] &&
        [parts[2] isEqualToString:@"conversation"] && [parts[3] length]) return parts[3];
    return nil;
}

NSURLRequest *CGPagingModernRequest(NSURLRequest *original, NSString *before) {
    NSString *cid=CGPagingConversationID(original);
    if (!cid.length) return original;
    NSURLComponents *parts=[NSURLComponents componentsWithURL:original.URL resolvingAgainstBaseURL:NO];
    if (!parts) return original;
    parts.path=[@"/backend-api/conversations/" stringByAppendingString:cid];
    NSMutableArray *items=[NSMutableArray array];
    for (NSURLQueryItem *item in parts.queryItems) {
        if ([@[@"before",@"num_turns",@"include_has_versions",@"tree_transform"] containsObject:item.name]) continue;
        [items addObject:item];
    }
    [items addObject:[NSURLQueryItem queryItemWithName:@"include_has_versions" value:@"true"]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"num_turns"
        value:[NSString stringWithFormat:@"%lu",(unsigned long)kConversationPageSize]]];
    if (before.length) [items addObject:[NSURLQueryItem queryItemWithName:@"before" value:before]];
    parts.queryItems=items;
    if (!parts.URL) return original;
    NSMutableURLRequest *request=[original mutableCopy];
    request.URL=parts.URL;
    request.cachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    return request;
}

NSInteger CGPagingStatus(NSURLResponse *response) {
    return [response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
}

BOOL CGPagingCompatibilityFailure(NSInteger status) {
    return status==400 || status==404 || status==405 || status==410 || status==422;
}

BOOL CGPagingTransientFailure(NSInteger status, NSError *error) {
    if (status==408 || status==429 || status==500 || status==502 || status==503 ||
        status==504 || status==520 || status==522 || status==524) return YES;
    if (!error || ![error.domain isEqualToString:NSURLErrorDomain]) return NO;
    switch (error.code) {
        case NSURLErrorTimedOut: case NSURLErrorNetworkConnectionLost:
        case NSURLErrorCannotConnectToHost: case NSURLErrorCannotFindHost:
        case NSURLErrorNotConnectedToInternet: return YES;
        default: return NO;
    }
}

NSTimeInterval CGPagingRetryAfter(NSURLResponse *response) {
    if (![response isKindOfClass:NSHTTPURLResponse.class]) return 0;
    for (id key in ((NSHTTPURLResponse *)response).allHeaderFields) {
        if (![key isKindOfClass:NSString.class] || [key caseInsensitiveCompare:@"Retry-After"]!=NSOrderedSame) continue;
        id raw=((NSHTTPURLResponse *)response).allHeaderFields[key];
        double seconds=[[raw description] doubleValue];
        if (isfinite(seconds) && seconds>0) return seconds;
    }
    return 0;
}

NSURLResponse *CGPagingLegacyResponse(NSURLResponse *response, NSURL *legacyURL, NSUInteger length) {
    if (![response isKindOfClass:NSHTTPURLResponse.class] || !legacyURL) return response;
    NSHTTPURLResponse *http=(NSHTTPURLResponse *)response;
    NSMutableDictionary *headers=[http.allHeaderFields mutableCopy] ?: [NSMutableDictionary dictionary];
    for (id key in [headers.allKeys copy]) if ([key isKindOfClass:NSString.class] &&
        [(NSString *)key caseInsensitiveCompare:@"Content-Length"]==NSOrderedSame) [headers removeObjectForKey:key];
    headers[@"Content-Length"]=[NSString stringWithFormat:@"%lu",(unsigned long)length];
    return [[NSHTTPURLResponse alloc] initWithURL:legacyURL statusCode:http.statusCode
        HTTPVersion:@"HTTP/1.1" headerFields:headers];
}

BOOL CGPagingStillActive(NSString *cid, NSUInteger generation) {
    @synchronized(CGPagingStateLock()) {
        return [CGPagingSelectedID isEqualToString:cid] && CGPagingGeneration==generation;
    }
}

BOOL CGPagingValidPageRoot(NSDictionary *root, BOOL *hasPrevious, NSString **cursor) {
    BOOL previous=NO;
    NSString *start=CGConversationPagingStartCursor(root,&previous);
    if (hasPrevious) *hasPrevious=previous;
    if (cursor) *cursor=start;
    return [root[@"page_info"] isKindOfClass:NSDictionary.class] &&
           CGConversationPagingMessages(root).count>0 && (!previous || start.length>0);
}

void CGPagingFetchLegacy(NSURLSessionConfiguration *configuration, NSURLRequest *request,
                         NSString *cid, NSUInteger generation,
                         void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    NSURLSessionConfiguration *config=[configuration copy] ?: [NSURLSessionConfiguration defaultSessionConfiguration];
    if (config.timeoutIntervalForRequest<30) config.timeoutIntervalForRequest=30;
    __block NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
    @try {
        NSURLSessionDataTask *task=[session cgp_dataTaskWithRequest:request completionHandler:
            ^(NSData *data, NSURLResponse *response, NSError *error) {
                [session finishTasksAndInvalidate]; session=nil;
                if (!CGPagingStillActive(cid,generation)) {
                    completion(nil,nil,[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
                    return;
                }
                completion(data,response,error);
            }];
        if (task) [task resume];
        else { [session invalidateAndCancel]; session=nil; completion(nil,nil,[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]); }
    } @catch (__unused NSException *exception) {
        [session invalidateAndCancel]; session=nil;
        completion(nil,nil,[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]);
    }
}
