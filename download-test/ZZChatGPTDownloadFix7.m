#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSDictionary<NSString *, NSString *> *gCGRDownload7Headers;

static NSString *CGRLogPath(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject;
    if (documents.length == 0) return nil;
    return [documents stringByAppendingPathComponent:@"ChatGPTRepairDownloadFixTest.log"];
}

static void CGRLog(NSString *line) {
    if (line.length == 0) return;
    @autoreleasepool {
        NSString *path = CGRLogPath();
        if (path.length == 0) return;
        NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        @synchronized([NSFileHandle class]) {
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                [data writeToFile:path atomically:YES];
                return;
            }
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            if (!handle) return;
            [handle seekToEndOfFile];
            [handle writeData:data];
            [handle closeFile];
        }
    }
}

static BOOL CGRTrustedURL(NSURL *url) {
    if (!url) return NO;
    if (![[url.scheme lowercaseString] isEqualToString:@"https"]) return NO;
    if (url.port && url.port.integerValue != 443) return NO;
    NSString *host = [url.host lowercaseString];
    if (host.length == 0) return NO;
    static NSSet<NSString *> *allowed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowed = [NSSet setWithArray:@[
            @"chatgpt.com",
            @"chat.openai.com",
            @"api.openai.com",
            @"ios.chat.openai.com"
        ]];
    });
    return [allowed containsObject:host];
}

static BOOL CGRIsResolverRequest(NSURLRequest *request) {
    NSURL *url = request.URL;
    return CGRTrustedURL(url) && [url.path hasSuffix:@"/interpreter/download"];
}

static BOOL CGRIsEstuaryURL(NSURL *url) {
    return CGRTrustedURL(url) && [url.path hasSuffix:@"/backend-api/estuary/content"];
}

static BOOL CGRIsEstuaryRequest(NSURLRequest *request) {
    return CGRIsEstuaryURL(request.URL);
}

static void CGRCaptureResolverHeaders(NSURLRequest *request) {
    if (!CGRIsResolverRequest(request)) return;

    NSArray<NSString *> *keys = @[
        @"Authorization",
        @"ChatGPT-Account-Id",
        @"originator",
        @"User-Agent",
        @"Cookie",
        @"Accept",
        @"Referer"
    ];
    NSMutableDictionary<NSString *, NSString *> *captured = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSString *value = [request valueForHTTPHeaderField:key];
        if (value.length) captured[key] = value;
    }

    @synchronized([NSURLSession class]) {
        gCGRDownload7Headers = [captured copy];
    }

    CGRLog([NSString stringWithFormat:
        @"fix7 resolver captured host=%@ auth=%d account=%d cookie=%d",
        request.URL.host ?: @"",
        [captured[@"Authorization"] length] > 0,
        [captured[@"ChatGPT-Account-Id"] length] > 0,
        [captured[@"Cookie"] length] > 0]);
}

static NSURLRequest *CGRAuthenticatedEstuaryRequest(NSURLRequest *request, NSString *source) {
    if (!CGRIsEstuaryRequest(request)) return request;

    NSDictionary<NSString *, NSString *> *headers;
    @synchronized([NSURLSession class]) {
        headers = [gCGRDownload7Headers copy];
    }

    NSString *authorization = headers[@"Authorization"];
    if (authorization.length == 0) {
        CGRLog([NSString stringWithFormat:@"fix7 file request source=%@ host=%@ auth=0 (no captured Authorization)",
                source ?: @"?", request.URL.host ?: @""]);
        return request;
    }

    NSMutableURLRequest *mutable = [request mutableCopy];
    for (NSString *key in headers) {
        NSString *value = headers[key];
        if (value.length == 0) continue;
        if ([[mutable valueForHTTPHeaderField:key] length] == 0 || [key caseInsensitiveCompare:@"Authorization"] == NSOrderedSame) {
            [mutable setValue:value forHTTPHeaderField:key];
        }
    }
    if ([[mutable valueForHTTPHeaderField:@"Referer"] length] == 0) {
        [mutable setValue:@"https://chatgpt.com/" forHTTPHeaderField:@"Referer"];
    }

    CGRLog([NSString stringWithFormat:
        @"fix7 file request source=%@ host=%@ auth=%d account=%d path=%@",
        source ?: @"?",
        mutable.URL.host ?: @"",
        [[mutable valueForHTTPHeaderField:@"Authorization"] length] > 0,
        [[mutable valueForHTTPHeaderField:@"ChatGPT-Account-Id"] length] > 0,
        mutable.URL.path ?: @""]);

    return mutable;
}

static NSURLRequest *CGRPrepareRequest(NSURLRequest *request, NSString *source) {
    if (!request) return request;
    if (CGRIsResolverRequest(request)) {
        CGRCaptureResolverHeaders(request);
        return request; // Critical: resolver request and completion remain untouched.
    }
    if (CGRIsEstuaryRequest(request)) {
        return CGRAuthenticatedEstuaryRequest(request, source);
    }
    return request;
}

@interface NSURLSession (CGRDownload7)
- (NSURLSessionDataTask *)cgr7_dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)cgr7_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionDataTask *)cgr7_dataTaskWithURL:(NSURL *)url;
- (NSURLSessionDataTask *)cgr7_dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;

- (NSURLSessionDownloadTask *)cgr7_downloadTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDownloadTask *)cgr7_downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionDownloadTask *)cgr7_downloadTaskWithURL:(NSURL *)url;
- (NSURLSessionDownloadTask *)cgr7_downloadTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler;
@end

@implementation NSURLSession (CGRDownload7)

- (NSURLSessionDataTask *)cgr7_dataTaskWithRequest:(NSURLRequest *)request {
    return [self cgr7_dataTaskWithRequest:CGRPrepareRequest(request, @"data-request")];
}

- (NSURLSessionDataTask *)cgr7_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    return [self cgr7_dataTaskWithRequest:CGRPrepareRequest(request, @"data-request-completion") completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)cgr7_dataTaskWithURL:(NSURL *)url {
    if (CGRIsEstuaryURL(url)) {
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        return [self dataTaskWithRequest:request];
    }
    return [self cgr7_dataTaskWithURL:url];
}

- (NSURLSessionDataTask *)cgr7_dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (CGRIsEstuaryURL(url)) {
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        return [self dataTaskWithRequest:request completionHandler:completionHandler];
    }
    return [self cgr7_dataTaskWithURL:url completionHandler:completionHandler];
}

- (NSURLSessionDownloadTask *)cgr7_downloadTaskWithRequest:(NSURLRequest *)request {
    return [self cgr7_downloadTaskWithRequest:CGRPrepareRequest(request, @"download-request")];
}

- (NSURLSessionDownloadTask *)cgr7_downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler {
    return [self cgr7_downloadTaskWithRequest:CGRPrepareRequest(request, @"download-request-completion") completionHandler:completionHandler];
}

- (NSURLSessionDownloadTask *)cgr7_downloadTaskWithURL:(NSURL *)url {
    if (CGRIsEstuaryURL(url)) {
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        return [self downloadTaskWithRequest:request];
    }
    return [self cgr7_downloadTaskWithURL:url];
}

- (NSURLSessionDownloadTask *)cgr7_downloadTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler {
    if (CGRIsEstuaryURL(url)) {
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        return [self downloadTaskWithRequest:request completionHandler:completionHandler];
    }
    return [self cgr7_downloadTaskWithURL:url completionHandler:completionHandler];
}

@end

static BOOL CGRSwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (!a || !b) return NO;
    method_exchangeImplementations(a, b);
    return YES;
}

__attribute__((constructor))
static void CGRDownload7Init(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;

        void *baseline = dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/ChatGPTRepair.dylib", RTLD_LAZY | RTLD_GLOBAL);
        CGRLog(@"=== ChatGPTRepair download fix7 pipeline test launch ===");
        if (!baseline) {
            CGRLog(@"fix7 baseline load failed; hook still attempting install");
        }

        Class cls = [NSURLSession class];
        int installed = 0;
        installed += CGRSwap(cls, @selector(dataTaskWithRequest:), @selector(cgr7_dataTaskWithRequest:));
        installed += CGRSwap(cls, @selector(dataTaskWithRequest:completionHandler:), @selector(cgr7_dataTaskWithRequest:completionHandler:));
        installed += CGRSwap(cls, @selector(dataTaskWithURL:), @selector(cgr7_dataTaskWithURL:));
        installed += CGRSwap(cls, @selector(dataTaskWithURL:completionHandler:), @selector(cgr7_dataTaskWithURL:completionHandler:));
        installed += CGRSwap(cls, @selector(downloadTaskWithRequest:), @selector(cgr7_downloadTaskWithRequest:));
        installed += CGRSwap(cls, @selector(downloadTaskWithRequest:completionHandler:), @selector(cgr7_downloadTaskWithRequest:completionHandler:));
        installed += CGRSwap(cls, @selector(downloadTaskWithURL:), @selector(cgr7_downloadTaskWithURL:));
        installed += CGRSwap(cls, @selector(downloadTaskWithURL:completionHandler:), @selector(cgr7_downloadTaskWithURL:completionHandler:));

        CGRLog([NSString stringWithFormat:@"fix7 hooks installed=%d/8", installed]);
    }
}
