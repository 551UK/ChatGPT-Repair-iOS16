/*
 * ChatGPT Repair iOS16 / 551UK
 * v0.8.0 original history-interceptor control experiment (GPL-3.0).
 *
 * Unlike earlier URLProtocol wrappers, this source does not copy or repackage
 * Liam's dylib. This controlled test observes the original protocol's
 * response without bypassing it. It leaves every request unchanged.
 */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

typedef BOOL (*CGRCanInitIMP)(id, SEL, NSURLRequest *);
static CGRCanInitIMP sOriginalCanInit = NULL;
static NSString *const kLog = @"ChatGPT551Repair.log";

static void CGRLog(NSString *line) {
    @synchronized([NSFileHandle class]) {
        NSString *path = [NSHomeDirectory()
          stringByAppendingPathComponent:@"Library/Caches/ChatGPT551Repair.log"];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
        if ([attrs fileSize] > 512*1024) [fm removeItemAtPath:path error:NULL];
        if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) return;
        @try {
            [h seekToEndOfFile];
            NSString *text = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], line ?: @""];
            [h writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];
        } @catch (__unused NSException *e) {}
        @finally { [h closeFile]; }
    }
}

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

static BOOL CGRLegacyCanInit(id cls, SEL selector, NSURLRequest *request) {
    BOOL original = sOriginalCanInit ? sOriginalCanInit(cls, selector, request) : NO;
    if (CGRHistoryRequest(request)) {
        CGRLog([NSString stringWithFormat:
            @"v0.8 protocol_probe history original_would_intercept=%d force_bypass=0 offset=%@ limit=%@",
            (int)original, CGRPage(request.URL, @"offset"),
            CGRPage(request.URL, @"limit")]);
        return original;
    }
    return original;
}

/*
 * Observe the history task's KVO state, independent of completion-handler
 * vs. delegate transport. We record only status/bytes/error at completion.
 * Original task execution and payloads are never changed.
 */
static char kCGRStateObserverKey;
static void *kCGRStateContext = &kCGRStateContext;
static NSUInteger sCGRHistoryTaskSequence = 0;

@interface CGRHistoryTaskObserver : NSObject
@property (nonatomic, weak) NSURLSessionTask *task;
@property (nonatomic, assign) BOOL observing;
@property (nonatomic, assign) NSUInteger sequence;
- (instancetype)initWithTask:(NSURLSessionTask *)task sequence:(NSUInteger)sequence;
- (void)stop;
@end

@implementation CGRHistoryTaskObserver
- (instancetype)initWithTask:(NSURLSessionTask *)task sequence:(NSUInteger)sequence {
    if ((self = [super init])) {
        _task = task;
        _sequence = sequence;
        @try {
            [task addObserver:self forKeyPath:@"state"
                       options:NSKeyValueObservingOptionNew
                       context:kCGRStateContext];
            _observing = YES;
        } @catch (__unused NSException *ex) {
            CGRLog([NSString stringWithFormat:
                @"v0.8 history_task=%lu state_observer_unavailable",
                (unsigned long)_sequence]);
        }
    }
    return self;
}
- (void)stop {
    @synchronized (self) {
        if (!_observing) return;
        _observing = NO;
        NSURLSessionTask *task = _task;
        if (task) {
            @try {
                [task removeObserver:self forKeyPath:@"state"
                             context:kCGRStateContext];
            } @catch (__unused NSException *ex) {}
        }
    }
}
- (void)dealloc { [self stop]; }
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object
    change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context != kCGRStateContext) {
        [super observeValueForKeyPath:path ofObject:object change:change context:context];
        return;
    }
    NSURLSessionTask *task = [object isKindOfClass:[NSURLSessionTask class]]
        ? object : nil;
    if (!task || task.state != NSURLSessionTaskStateCompleted) return;
    NSURLResponse *response = task.response;
    NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
        ? ((NSHTTPURLResponse *)response).statusCode : 0;
    NSError *error = task.error;
    CGRLog([NSString stringWithFormat:
        @"v0.8 history_task=%lu completed=1 http_status=%ld error_code=%ld received_bytes=%lld",
        (unsigned long)_sequence, (long)status, (long)(error ? error.code : 0),
        (long long)task.countOfBytesReceived]);
    [self stop];
}
@end


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
    if (!url || [url isEqual:request.URL]) return request;
    NSMutableURLRequest *adapted = [request mutableCopy];
    adapted.URL = url; // Retains method, headers, cookies policy, timeout and body.
    CGRLog([NSString stringWithFormat:
        @"v0.9 history_browser_query applied=1 offset=%@ limit=%@ archive=0 starred=0 exclude_tpp=1",
        offset, limit]);
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
    BOOL request = CGRSwizzleSessionMethod(
        @selector(dataTaskWithRequest:), @selector(cgr_browserDataTaskWithRequest:));
    BOOL completion = CGRSwizzleSessionMethod(
        @selector(dataTaskWithRequest:completionHandler:),
        @selector(cgr_browserDataTaskWithRequest:completionHandler:));
    BOOL url = CGRSwizzleSessionMethod(
        @selector(dataTaskWithURL:), @selector(cgr_browserDataTaskWithURL:));
    BOOL urlCompletion = CGRSwizzleSessionMethod(
        @selector(dataTaskWithURL:completionHandler:),
        @selector(cgr_browserDataTaskWithURL:completionHandler:));
    CGRLog([NSString stringWithFormat:
        @"v0.9 history_url_adapter hooks request=%d completion=%d url=%d url_completion=%d",
        (int)request, (int)completion, (int)url, (int)urlCompletion]);
}

@interface NSURLSessionTask (CGRHistoryStartProbe)
- (void)cgr_historyResume;
@end

@implementation NSURLSessionTask (CGRHistoryStartProbe)
- (void)cgr_historyResume {
    NSURLRequest *request = self.currentRequest ?: self.originalRequest;
    if (CGRHistoryRequest(request)) {
        @synchronized ([NSURLSessionTask class]) {
            if (!objc_getAssociatedObject(self, &kCGRStateObserverKey)) {
                NSUInteger next = ++sCGRHistoryTaskSequence;
                CGRHistoryTaskObserver *observer = [[CGRHistoryTaskObserver alloc]
                    initWithTask:self sequence:next];
                objc_setAssociatedObject(self, &kCGRStateObserverKey, observer,
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                CGRLog([NSString stringWithFormat:
                    @"v0.8 history_task=%lu started offset=%@ limit=%@ kvo=%d",
                    (unsigned long)next, CGRPage(request.URL, @"offset"),
                    CGRPage(request.URL, @"limit"), (int)observer.observing]);
            }
        }
    }
    [self cgr_historyResume];
}
@end

static void CGRInstallHistoryInterceptorProbe(void) {
    Class protocolClass = objc_getClass("LVBVoiceURLProtocol");
    if (!protocolClass) {
        CGRLog(@"v0.8 LVBVoiceURLProtocol class missing: no bypass installed");
        return;
    }
    Method old = class_getClassMethod(protocolClass, @selector(canInitWithRequest:));
    if (!old) {
        CGRLog(@"v0.8 +canInitWithRequest: missing: no bypass installed");
        return;
    }
    sOriginalCanInit = (CGRCanInitIMP)method_getImplementation(old);
    if (!sOriginalCanInit || sOriginalCanInit == (CGRCanInitIMP)CGRLegacyCanInit) {
        CGRLog(@"v0.8 original interceptor unavailable: no bypass installed");
        return;
    }
    // Install a method on the specific metaclass; leave NSURLProtocol and every
    // other protocol's canInitWithRequest: implementation unchanged.
    const char *encoding = method_getTypeEncoding(old);
    class_replaceMethod(object_getClass(protocolClass),
                        @selector(canInitWithRequest:),
                        (IMP)CGRLegacyCanInit, encoding);
    CGRLog(@"v0.8 original protocol located; passive history probe installed; bypass=0");
}

__attribute__((constructor)) static void CGRStart(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
        CGRLog(@"v0.9.0 browser history query experiment loaded; original interceptor preserved");
        CGRInstallBrowserListAdapter();
        CGRInstallHistoryInterceptorProbe();
        Method m = class_getInstanceMethod([NSURLSessionTask class], @selector(resume));
        Method ours = class_getInstanceMethod([NSURLSessionTask class],
                                               @selector(cgr_historyResume));
        if (m && ours) method_exchangeImplementations(m, ours);
    }
}
