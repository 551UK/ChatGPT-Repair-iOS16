/*
 * ChatGPT Repair iOS16 v0.4.0 — 551UK — GPL-3.0
 *
 * Passive, privacy-conscious comparison instrumentation for 1.2024.200.
 * NO NSURLProtocol registration, URLSessionConfiguration mutation, request
 * replay, fake HTTP success, body replacement or user-data modification.
 *
 * ChatGBeFree 2.3.5 also intercepts URLSession; v0.1–0.3 experiments could
 * interfere with its forwarding and therefore must not be used as proof that
 * the remote service is broken. This test isolates that risk.
 */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, CGRRoute) {
    CGRNone = 0, CGRHistory = 1, CGRInit = 2,
    CGRDetail = 3, CGRMetadata = 4
};

static NSString *CGRRouteName(CGRRoute route) {
    switch (route) {
        case CGRHistory: return @"history";
        case CGRInit: return @"init";
        case CGRDetail: return @"detail";
        case CGRMetadata: return @"metadata";
        default: return @"other";
    }
}

static BOOL CGROfficialHost(NSString *host) {
    NSString *h = host.lowercaseString;
    if (!h.length) return NO;
    return [h isEqualToString:@"chatgpt.com"] || [h hasSuffix:@".chatgpt.com"] ||
           [h isEqualToString:@"openai.com"] || [h hasSuffix:@".openai.com"];
}

static CGRRoute CGRRouteForRequest(NSURLRequest *request) {
    if (!request || !CGROfficialHost(request.URL.host)) return CGRNone;
    NSString *p = request.URL.path ?: @"";
    NSString *method = request.HTTPMethod.uppercaseString ?: @"GET";
    if ([method isEqualToString:@"GET"] &&
        ([p isEqualToString:@"/backend-api/conversations"] ||
         [p isEqualToString:@"/backend-api/conversations/"] ||
         [p isEqualToString:@"/conversations"] ||
         [p isEqualToString:@"/conversations/"])) return CGRHistory;
    if ([method isEqualToString:@"POST"] &&
        ([p isEqualToString:@"/backend-api/conversation/init"] ||
         [p isEqualToString:@"/conversation/init"])) return CGRInit;
    if ([method isEqualToString:@"GET"] &&
        ([p containsString:@"conversation_detail_metadata"] ||
         [p containsString:@"conversation-detail-metadata"])) return CGRMetadata;
    if (![method isEqualToString:@"GET"]) return CGRNone;
    NSArray *parts = [p componentsSeparatedByString:@"/"];
    if (parts.count == 4 &&
        [parts[1] isEqualToString:@"backend-api"] &&
        [parts[2] isEqualToString:@"conversation"] &&
        [parts[3] length]) return CGRDetail;
    if (parts.count == 3 && [parts[1] isEqualToString:@"conversation"] &&
        [parts[2] length]) return CGRDetail;
    return CGRNone;
}

static void CGRLog(NSString *line) {
    if (!line.length) return;
    @synchronized([NSFileHandle class]) {
        NSString *directory = [NSHomeDirectory()
            stringByAppendingPathComponent:@"Library/Caches"];
        NSString *path = [directory
            stringByAppendingPathComponent:@"ChatGPT551Repair.log"];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
        if ([attrs fileSize] > 512 * 1024) {
            [fm removeItemAtPath:path error:NULL]; // simple size-bound rollover
        }
        if (![fm fileExistsAtPath:path]) {
            [fm createFileAtPath:path contents:nil attributes:nil];
        }
        NSData *bytes = [[NSString stringWithFormat:@"%@ %@\n",
            [NSDate date], line] dataUsingEncoding:NSUTF8StringEncoding];
        NSFileHandle *out = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!out) return;
        @try { [out seekToEndOfFile]; [out writeData:bytes]; }
        @catch (__unused NSException *e) {}
        @finally { [out closeFile]; }
    }
}

static NSString *CGRPage(NSURL *url, NSString *name) {
    NSURLComponents *p = [NSURLComponents componentsWithURL:url
                                    resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in p.queryItems) {
        if (![item.name isEqualToString:name]) continue;
        NSString *s = item.value ?: @"";
        if (!s.length || s.length > 7 ||
            [s rangeOfCharacterFromSet:
              [[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location
              != NSNotFound) return @"invalid";
        return s;
    }
    return @"absent";
}

static BOOL CGRHasKey(NSDictionary *object, NSString *key) {
    return object[key] != nil && object[key] != [NSNull null];
}
static id CGRFirstKey(NSDictionary *object, NSArray<NSString *> *keys) {
    if (![object isKindOfClass:[NSDictionary class]]) return nil;
    for (NSString *key in keys) if (CGRHasKey(object,key)) return object[key];
    return nil;
}

static NSString *CGRBlockedType(id value) {
    if (!value || value == [NSNull null]) return @"absent";
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = value;
        BOOL upload = NO;
        for (NSString *key in dict) {
            if ([key.lowercaseString containsString:@"fileupload"] ||
                [key.lowercaseString containsString:@"file_upload"]) {
                upload = YES; break;
            }
        }
        return upload ? @"dict-upload-key" : @"dict-other";
    }
    if ([value isKindOfClass:[NSArray class]]) {
        BOOL upload = NO;
        for (id element in value) {
            if ([element isKindOfClass:[NSString class]] &&
                [[element lowercaseString] containsString:@"file"]) upload = YES;
            if ([element isKindOfClass:[NSDictionary class]]) {
                NSDictionary *d = element;
                for (NSString *key in @[@"feature", @"type", @"name"]) {
                    id feature = d[key];
                    if ([feature isKindOfClass:[NSString class]] &&
                        [[feature lowercaseString] containsString:@"file"]) {
                        upload = YES;
                    }
                }
            }
        }
        return upload ? @"array-file-entry" : @"array-other";
    }
    return @"other";
}

/* No raw model names, IDs, titles, message bodies, tokens, headers or URLs. */
static void CGRInspect(NSURLRequest *request, NSData *data,
                       NSURLResponse *response, NSError *error) {
    CGRRoute route = CGRRouteForRequest(request);
    if (route == CGRNone) return;
    NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
        ? [(NSHTTPURLResponse *)response statusCode] : 0;
    NSString *prefix = CGRRouteName(route);
    CGRLog([NSString stringWithFormat:
        @"complete route=%@ status=%ld bytes=%lu error_code=%ld",
        prefix, (long)status, (unsigned long)data.length,
        (long)(error ? error.code : 0)]);
    if (data.length == 0 || data.length > 6 * 1024 * 1024) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        CGRLog([NSString stringWithFormat:
            @"structure route=%@ json_dictionary=0", prefix]);
        return;
    }
    NSDictionary *root = json;
    if (route == CGRHistory) {
        id items = root[@"items"];
        if (![items isKindOfClass:[NSArray class]]) items = root[@"conversations"];
        id inner = root[@"data"];
        if (![items isKindOfClass:[NSArray class]] &&
            [inner isKindOfClass:[NSDictionary class]])
            items = CGRFirstKey(inner, @[@"items", @"conversations"]);
        CGRLog([NSString stringWithFormat:
            @"structure history items_array=%d count=%ld total_present=%d cursor_present=%d",
            (int)[items isKindOfClass:[NSArray class]],
            (long)([items isKindOfClass:[NSArray class]] ? [items count] : -1),
            (int)CGRHasKey(root, @"total"),
            (int)(CGRHasKey(root, @"cursor") || CGRHasKey(root, @"next_cursor"))]);
    }
    if (route == CGRInit || route == CGRMetadata) {
        id details = CGRFirstKey(root, @[@"conversation_detail_metadata",
                  @"conversationDetailMetadata", @"conversation", @"data"]);
        if (![details isKindOfClass:[NSDictionary class]]) details = root;
        NSDictionary *d = details;
        id blocked = CGRFirstKey(d, @[@"blockedFeatures", @"blocked_features"]);
        if (!blocked && d != root)
            blocked = CGRFirstKey(root, @[@"blockedFeatures", @"blocked_features"]);
        CGRLog([NSString stringWithFormat:
            @"structure route=%@ has_default_model=%d has_model_limits=%d blocked=%@",
            prefix,
            (int)(CGRHasKey(d, @"defaultModelSlug") ||
                  CGRHasKey(d, @"default_model_slug")),
            (int)(CGRHasKey(d, @"modelLimits") ||
                  CGRHasKey(d, @"model_limits")),
            CGRBlockedType(blocked)]);
    }
    if (route == CGRDetail) {
        CGRLog([NSString stringWithFormat:
            @"structure detail has_mapping=%d has_current_node=%d has_blocked=%d",
            (int)CGRHasKey(root, @"mapping"),
            (int)CGRHasKey(root, @"current_node"),
            (int)(CGRHasKey(root, @"blockedFeatures") ||
                  CGRHasKey(root, @"blocked_features"))]);
    }
}

@interface NSURLSession (CGRPassive)
- (NSURLSessionDataTask *)cgr_observeDataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
- (NSURLSessionDataTask *)cgr_observeDataTaskWithURL:(NSURL *)url
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
@end
@implementation NSURLSession (CGRPassive)
- (NSURLSessionDataTask *)cgr_observeDataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    if (!completion || CGRRouteForRequest(request) == CGRNone)
        return [self cgr_observeDataTaskWithRequest:request completionHandler:completion];
    void (^observed)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            CGRInspect(request, data, response, error);
            completion(data, response, error);
        };
    return [self cgr_observeDataTaskWithRequest:request completionHandler:observed];
}
- (NSURLSessionDataTask *)cgr_observeDataTaskWithURL:(NSURL *)url
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    if (!completion || CGRRouteForRequest(request) == CGRNone)
        return [self cgr_observeDataTaskWithURL:url completionHandler:completion];
    void (^observed)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            CGRInspect(request, data, response, error);
            completion(data, response, error);
        };
    return [self cgr_observeDataTaskWithURL:url completionHandler:observed];
}
@end

@interface NSURLSessionTask (CGRPassiveTask)
- (void)cgr_observeResume;
@end
@implementation NSURLSessionTask (CGRPassiveTask)
- (void)cgr_observeResume {
    NSURLRequest *request = self.currentRequest ?: self.originalRequest;
    CGRRoute route = CGRRouteForRequest(request);
    if (route == CGRHistory) {
        CGRLog([NSString stringWithFormat:
            @"start history offset=%@ limit=%@",
            CGRPage(request.URL, @"offset"), CGRPage(request.URL, @"limit")]);
    } else if (route == CGRInit || route == CGRMetadata) {
        CGRLog([NSString stringWithFormat:@"start route=%@", CGRRouteName(route)]);
    }
    [self cgr_observeResume];
}
@end

/*
 * Delegate callback observer. The older app and ChatGBeFree's URLProtocol
 * forwarder can use URLSession delegate callbacks without a completion block.
 * Wrap ONLY callbacks a delegate already implements, pass original arguments
 * unchanged, and never modify networking state or payloads.
 */
static char kCGRCapturedBytes, kCGRDataOriginal, kCGRDoneOriginal, kCGRInstalled;
static const NSUInteger kCGRCaptureLimit = 4 * 1024 * 1024;
static NSValue *CGRSavedDelegateImplementation(id object, const void *key) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        NSValue *value = objc_getAssociatedObject((id)cls, key);
        if (value) return value;
    }
    return nil;
}


typedef void (*CGRDataCallback)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *);
typedef void (*CGRDoneCallback)(id, SEL, NSURLSession *, NSURLSessionTask *, NSError *);

static void CGRDelegateReceived(id object, SEL selector,
                                NSURLSession *session,
                                NSURLSessionDataTask *task, NSData *chunk) {
    NSValue *value = CGRSavedDelegateImplementation(object, &kCGRDataOriginal);
    CGRDataCallback previous = (CGRDataCallback)[value pointerValue];
    // Preserve the original application's processing and callback order.
    if (previous) previous(object, selector, session, task, chunk);
    if (CGRRouteForRequest(task.originalRequest ?: task.currentRequest) == CGRNone)
        return;
    @synchronized(task) {
        NSMutableData *captured = objc_getAssociatedObject(task, &kCGRCapturedBytes);
        if (!captured) {
            captured = [NSMutableData data];
            objc_setAssociatedObject(task, &kCGRCapturedBytes, captured,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (captured.length < kCGRCaptureLimit && chunk.length > 0) {
            NSUInteger bytes = MIN(chunk.length, kCGRCaptureLimit - captured.length);
            [captured appendBytes:chunk.bytes length:bytes];
        }
    }
}

static void CGRDelegateFinished(id object, SEL selector,
                                NSURLSession *session, NSURLSessionTask *task,
                                NSError *error) {
    CGRRoute route = CGRRouteForRequest(task.originalRequest ?: task.currentRequest);
    if (route != CGRNone) {
        NSData *captured = nil;
        @synchronized(task) {
            captured = [objc_getAssociatedObject(task, &kCGRCapturedBytes) copy];
            objc_setAssociatedObject(task, &kCGRCapturedBytes, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        CGRInspect(task.originalRequest ?: task.currentRequest, captured,
                   task.response, error);
        if (captured.length >= kCGRCaptureLimit)
            CGRLog(@"delegate response capture truncated at 4MB");
    }
    NSValue *value = CGRSavedDelegateImplementation(object, &kCGRDoneOriginal);
    CGRDoneCallback previous = (CGRDoneCallback)[value pointerValue];
    if (previous) previous(object, selector, session, task, error);
}

static BOOL CGRInstallDelegateMethod(Class cls, SEL selector, IMP replacement, void *key) {
    Method previous = class_getInstanceMethod(cls, selector);
    if (!previous) return NO; // Do not introduce new optional delegate behaviour.
    IMP original = method_getImplementation(previous);
    if (!original || original == replacement) return NO;
    objc_setAssociatedObject((id)cls, key, [NSValue valueWithPointer:(void *)original],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    const char *types = method_getTypeEncoding(previous);
    if (!class_addMethod(cls, selector, replacement, types)) {
        // Direct implementation on this class; original is saved above.
        Method own = class_getInstanceMethod(cls, selector);
        method_setImplementation(own, replacement);
    }
    return YES;
}

static void CGRWatchDelegate(id delegate) {
    if (!delegate) return;
    Class cls = object_getClass(delegate);
    if (!cls) return;
    @synchronized([NSURLSession class]) {
        if (objc_getAssociatedObject((id)cls, &kCGRInstalled)) return;
        BOOL received = CGRInstallDelegateMethod(cls,
               @selector(URLSession:dataTask:didReceiveData:),
               (IMP)CGRDelegateReceived, &kCGRDataOriginal);
        BOOL finished = CGRInstallDelegateMethod(cls,
               @selector(URLSession:task:didCompleteWithError:),
               (IMP)CGRDelegateFinished, &kCGRDoneOriginal);
        objc_setAssociatedObject((id)cls, &kCGRInstalled, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGRLog([NSString stringWithFormat:
            @"delegate hooks data=%d finished=%d", (int)received, (int)finished]);
    }
}

@interface NSURLSession (CGRDelegateObserver)
+ (NSURLSession *)cgr_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                       delegate:(id<NSURLSessionDelegate>)delegate
                                  delegateQueue:(NSOperationQueue *)queue;
@end
@implementation NSURLSession (CGRDelegateObserver)
+ (NSURLSession *)cgr_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                       delegate:(id<NSURLSessionDelegate>)delegate
                                  delegateQueue:(NSOperationQueue *)queue {
    CGRWatchDelegate(delegate);
    return [self cgr_sessionWithConfiguration:configuration
                                      delegate:delegate delegateQueue:queue];
}
@end

static BOOL CGRSwapSessionFactory(void) {
    Class cls = [NSURLSession class];
    Method a = class_getClassMethod(cls,
        @selector(sessionWithConfiguration:delegate:delegateQueue:));
    Method b = class_getClassMethod(cls,
        @selector(cgr_sessionWithConfiguration:delegate:delegateQueue:));
    if (!a || !b) return NO;
    method_exchangeImplementations(a, b);
    return YES;
}

static BOOL CGRSwap(Class cls, SEL a, SEL b) {
    Method old = class_getInstanceMethod(cls, a);
    Method new = class_getInstanceMethod(cls, b);
    if (!old || !new) return NO;
    method_exchangeImplementations(old, new);
    return YES;
}

__attribute__((constructor)) static void CGRInitProbe(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"])
            return;
        BOOL request = CGRSwap([NSURLSession class],
            @selector(dataTaskWithRequest:completionHandler:),
            @selector(cgr_observeDataTaskWithRequest:completionHandler:));
        BOOL url = CGRSwap([NSURLSession class],
            @selector(dataTaskWithURL:completionHandler:),
            @selector(cgr_observeDataTaskWithURL:completionHandler:));
        BOOL resume = CGRSwap([NSURLSessionTask class],
            @selector(resume), @selector(cgr_observeResume));
        BOOL delegateFactory = CGRSwapSessionFactory();
        CGRLog([NSString stringWithFormat:
            @"v0.5.0 passive delegate capture request_hook=%d url_hook=%d resume_hook=%d delegate_factory=%d no_network_rewriting=1",
            (int)request, (int)url, (int)resume, (int)delegateFactory]);
    }
}
