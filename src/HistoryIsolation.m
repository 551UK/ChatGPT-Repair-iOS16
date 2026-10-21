// ChatGPTRepair: Legacy conversation-list API and request adaptation.
/* ChatGPTRepair: production history URL adapter preserving v53 query semantics. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static BOOL CGRHistoryRequest(NSURLRequest *request) {
    if (![request.HTTPMethod.uppercaseString isEqualToString:@"GET"]) return NO;
    NSURL *url = request.URL;
    NSString *host = url.host.lowercaseString;
    if (!([host isEqualToString:@"chatgpt.com"] ||
          [host hasSuffix:@".chatgpt.com"] ||
          [host isEqualToString:@"openai.com"] ||
          [host hasSuffix:@".openai.com"])) return NO;
    NSString *path = url.path ?: @"";
    return [path isEqualToString:@"/backend-api/conversations"] ||
           [path isEqualToString:@"/backend-api/conversations/"] ||
           [path isEqualToString:@"/conversations"] ||
           [path isEqualToString:@"/conversations/"];
}

static NSString *CGRPage(NSURL *url, NSString *key) {
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url
                                            resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in parts.queryItems) {
        if (![item.name isEqualToString:key]) continue;
        NSString *value = item.value ?: @"";
        if (value.length > 0 && value.length <= 7 &&
            [value rangeOfCharacterFromSet:
               [[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound)
            return value;
        return @"invalid";
    }
    return @"absent";
}

/*
 * Browser-compatible conversation-list request adapter.
 * Desktop web 2026-10-14 returned HTTP 200 for both:
 *  - exclude_conversation_origin=tpp (normal list)
 *  - conversation_origin=tpp (separate list)
 * We adapt only the old app's ordinary list GET to the first shape.
 * Pages remain controlled by the app. A later implementation must still
 * handle the separate TPP-origin list to restore absolutely all history.
 */
static NSURLRequest *CGRAdaptHistoryRequest(NSURLRequest *request) {
    if (!CGRHistoryRequest(request)) return request;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:request.URL
                                        resolvingAgainstBaseURL:NO];
    if (!parts) return request;
    NSMutableDictionary<NSString *, NSString *> *original = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *q in parts.queryItems) {
        if (q.name.length && q.value) original[q.name] = q.value;
    }
    // Preserve explicit origin searches and specialised list requests.
    if (original[@"conversation_origin"] ||
        original[@"query"] || original[@"search"] ||
        original[@"filter"] || original[@"project_id"]) return request;
    NSString *offset = CGRPage(request.URL, @"offset");
    NSString *limit = CGRPage(request.URL, @"limit");
    if ([offset isEqualToString:@"invalid"] ||
        [limit isEqualToString:@"invalid"]) return request;
    if ([offset isEqualToString:@"absent"]) offset = @"0";
    if ([limit isEqualToString:@"absent"]) limit = @"20";
    NSString *archived = original[@"is_archived"];
    NSString *starred = original[@"is_starred"];
    // Do not turn an explicit archive/starred view into the normal list.
    if ([archived isEqualToString:@"true"] ||
        [starred isEqualToString:@"true"]) return request;
    NSArray<NSURLQueryItem *> *query = @[
        [NSURLQueryItem queryItemWithName:@"exclude_conversation_origin" value:@"tpp"],
        [NSURLQueryItem queryItemWithName:@"expand" value:@"false"],
        [NSURLQueryItem queryItemWithName:@"hide_snorlax" value:@"false"],
        [NSURLQueryItem queryItemWithName:@"is_archived" value:@"false"],
        [NSURLQueryItem queryItemWithName:@"is_starred" value:@"false"],
        [NSURLQueryItem queryItemWithName:@"limit" value:limit],
        [NSURLQueryItem queryItemWithName:@"order" value:@"updated"],
        [NSURLQueryItem queryItemWithName:@"offset" value:offset]
    ];
    parts.queryItems = query;
    NSURL *url = parts.URL;
    if (!url) return request;
    BOOL firstPage = [offset isEqualToString:@"0"];
    // Refresh the native first-page list from the server. The pinned list
    // already bypasses HTTP caches; without this, normal chats can remain
    // stale while pins and cross-device writes are working.
    if ([url isEqual:request.URL] && !firstPage) return request;
    NSMutableURLRequest *adapted = [request mutableCopy];
    adapted.URL = url; // Preserves account headers and app session.
    if (firstPage) {
        adapted.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        [adapted setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
        [adapted setValue:@"no-cache" forHTTPHeaderField:@"Pragma"];
    }
    return adapted;
}

@interface NSURLSession (CGRBrowserList)
- (NSURLSessionDataTask *)cgr_browserDataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)cgr_browserDataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionDataTask *)cgr_browserDataTaskWithURL:(NSURL *)url;
- (NSURLSessionDataTask *)cgr_browserDataTaskWithURL:(NSURL *)url
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

@implementation NSURLSession (CGRBrowserList)
- (NSURLSessionDataTask *)cgr_browserDataTaskWithRequest:(NSURLRequest *)request {
    return [self cgr_browserDataTaskWithRequest:CGRAdaptHistoryRequest(request)];
}
- (NSURLSessionDataTask *)cgr_browserDataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    return [self cgr_browserDataTaskWithRequest:CGRAdaptHistoryRequest(request)
                              completionHandler:completionHandler];
}
- (NSURLSessionDataTask *)cgr_browserDataTaskWithURL:(NSURL *)url {
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    if (CGRHistoryRequest(request)) {
        NSURLRequest *adapted = CGRAdaptHistoryRequest(request);
        return [self dataTaskWithRequest:adapted];
    }
    return [self cgr_browserDataTaskWithURL:url];
}
- (NSURLSessionDataTask *)cgr_browserDataTaskWithURL:(NSURL *)url
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    if (CGRHistoryRequest(request)) {
        NSURLRequest *adapted = CGRAdaptHistoryRequest(request);
        return [self dataTaskWithRequest:adapted completionHandler:completionHandler];
    }
    return [self cgr_browserDataTaskWithURL:url completionHandler:completionHandler];
}
@end

static BOOL CGRSwizzleSessionMethod(SEL original, SEL replacement) {
    Class cls = [NSURLSession class];
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (!a || !b) return NO;
    method_exchangeImplementations(a, b);
    return YES;
}

static void CGRInstallBrowserListAdapter(void) {
    CGRSwizzleSessionMethod(
        @selector(dataTaskWithRequest:), @selector(cgr_browserDataTaskWithRequest:));
    CGRSwizzleSessionMethod(
        @selector(dataTaskWithRequest:completionHandler:),
        @selector(cgr_browserDataTaskWithRequest:completionHandler:));
    CGRSwizzleSessionMethod(
        @selector(dataTaskWithURL:), @selector(cgr_browserDataTaskWithURL:));
    CGRSwizzleSessionMethod(
        @selector(dataTaskWithURL:completionHandler:),
        @selector(cgr_browserDataTaskWithURL:completionHandler:));
    
}

__attribute__((constructor)) static void CGRStart(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;

        CGRInstallBrowserListAdapter();
    }
}
