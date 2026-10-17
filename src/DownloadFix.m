#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSDictionary<NSString *, NSString *> *gCGRDownloadHeaders;

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
        gCGRDownloadHeaders = [captured copy];
    }
}

static NSURLRequest *CGRAuthenticatedEstuaryRequest(NSURLRequest *request) {
    if (!CGRIsEstuaryRequest(request)) return request;

    NSDictionary<NSString *, NSString *> *headers;
    @synchronized([NSURLSession class]) {
        headers = [gCGRDownloadHeaders copy];
    }

    if ([headers[@"Authorization"] length] == 0) {
        return request;
    }

    NSMutableURLRequest *mutable = [request mutableCopy];
    for (NSString *key in headers) {
        NSString *value = headers[key];
        if (value.length == 0) continue;

        if ([[mutable valueForHTTPHeaderField:key] length] == 0 ||
            [key caseInsensitiveCompare:@"Authorization"] == NSOrderedSame) {
            [mutable setValue:value forHTTPHeaderField:key];
        }
    }

    if ([[mutable valueForHTTPHeaderField:@"Referer"] length] == 0) {
        [mutable setValue:@"https://chatgpt.com/" forHTTPHeaderField:@"Referer"];
    }

    return mutable;
}

static NSURLRequest *CGRPrepareRequest(NSURLRequest *request) {
    if (!request) return request;

    if (CGRIsResolverRequest(request)) {
        CGRCaptureResolverHeaders(request);
        return request;
    }

    if (CGRIsEstuaryRequest(request)) {
        return CGRAuthenticatedEstuaryRequest(request);
    }

    return request;
}

@interface NSURLSession (CGRDownloadFix)
- (NSURLSessionDataTask *)cgrdf_dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)cgrdf_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionDataTask *)cgrdf_dataTaskWithURL:(NSURL *)url;
- (NSURLSessionDataTask *)cgrdf_dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;

- (NSURLSessionDownloadTask *)cgrdf_downloadTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDownloadTask *)cgrdf_downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionDownloadTask *)cgrdf_downloadTaskWithURL:(NSURL *)url;
- (NSURLSessionDownloadTask *)cgrdf_downloadTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler;
@end

@implementation NSURLSession (CGRDownloadFix)

- (NSURLSessionDataTask *)cgrdf_dataTaskWithRequest:(NSURLRequest *)request {
    return [self cgrdf_dataTaskWithRequest:CGRPrepareRequest(request)];
}

- (NSURLSessionDataTask *)cgrdf_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    return [self cgrdf_dataTaskWithRequest:CGRPrepareRequest(request) completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)cgrdf_dataTaskWithURL:(NSURL *)url {
    if (CGRIsEstuaryURL(url)) {
        return [self dataTaskWithRequest:[NSURLRequest requestWithURL:url]];
    }
    return [self cgrdf_dataTaskWithURL:url];
}

- (NSURLSessionDataTask *)cgrdf_dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (CGRIsEstuaryURL(url)) {
        return [self dataTaskWithRequest:[NSURLRequest requestWithURL:url] completionHandler:completionHandler];
    }
    return [self cgrdf_dataTaskWithURL:url completionHandler:completionHandler];
}

- (NSURLSessionDownloadTask *)cgrdf_downloadTaskWithRequest:(NSURLRequest *)request {
    return [self cgrdf_downloadTaskWithRequest:CGRPrepareRequest(request)];
}

- (NSURLSessionDownloadTask *)cgrdf_downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler {
    return [self cgrdf_downloadTaskWithRequest:CGRPrepareRequest(request) completionHandler:completionHandler];
}

- (NSURLSessionDownloadTask *)cgrdf_downloadTaskWithURL:(NSURL *)url {
    if (CGRIsEstuaryURL(url)) {
        return [self downloadTaskWithRequest:[NSURLRequest requestWithURL:url]];
    }
    return [self cgrdf_downloadTaskWithURL:url];
}

- (NSURLSessionDownloadTask *)cgrdf_downloadTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler {
    if (CGRIsEstuaryURL(url)) {
        return [self downloadTaskWithRequest:[NSURLRequest requestWithURL:url] completionHandler:completionHandler];
    }
    return [self cgrdf_downloadTaskWithURL:url completionHandler:completionHandler];
}

@end

static BOOL CGRSwapDownloadMethod(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (!a || !b) return NO;
    method_exchangeImplementations(a, b);
    return YES;
}

static void CGRRemoveOldDownloadTestLog(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject;
    if (documents.length == 0) return;

    NSString *path = [documents stringByAppendingPathComponent:@"ChatGPTRepairDownloadFixTest.log"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

__attribute__((constructor))
static void CGRDownloadFixInit(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;

        CGRRemoveOldDownloadTestLog();

        // Preserve the proven Fix7 load order: make sure the existing 55.5 core is loaded first.
        dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/ChatGPTRepair.dylib", RTLD_LAZY | RTLD_GLOBAL);

        Class cls = [NSURLSession class];
        CGRSwapDownloadMethod(cls, @selector(dataTaskWithRequest:), @selector(cgrdf_dataTaskWithRequest:));
        CGRSwapDownloadMethod(cls, @selector(dataTaskWithRequest:completionHandler:), @selector(cgrdf_dataTaskWithRequest:completionHandler:));
        CGRSwapDownloadMethod(cls, @selector(dataTaskWithURL:), @selector(cgrdf_dataTaskWithURL:));
        CGRSwapDownloadMethod(cls, @selector(dataTaskWithURL:completionHandler:), @selector(cgrdf_dataTaskWithURL:completionHandler:));
        CGRSwapDownloadMethod(cls, @selector(downloadTaskWithRequest:), @selector(cgrdf_downloadTaskWithRequest:));
        CGRSwapDownloadMethod(cls, @selector(downloadTaskWithRequest:completionHandler:), @selector(cgrdf_downloadTaskWithRequest:completionHandler:));
        CGRSwapDownloadMethod(cls, @selector(downloadTaskWithURL:), @selector(cgrdf_downloadTaskWithURL:));
        CGRSwapDownloadMethod(cls, @selector(downloadTaskWithURL:completionHandler:), @selector(cgrdf_downloadTaskWithURL:completionHandler:));
    }
}
