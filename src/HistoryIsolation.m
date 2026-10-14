/*
 * ChatGPT Repair iOS16 / 551UK
 * v0.6.0 isolated history networking experiment (GPL-3.0).
 *
 * Unlike earlier URLProtocol wrappers, this source does not copy or repackage
 * Liam's dylib. It only asks its Objective-C protocol not to claim the exact
 * read-only conversation-list GETs. Everything else remains unchanged.
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
            @"v0.6 protocol_probe history original_would_intercept=%d force_bypass=1 offset=%@ limit=%@",
            (int)original, CGRPage(request.URL, @"offset"),
            CGRPage(request.URL, @"limit")]);
        return NO;
    }
    return original;
}

@interface NSURLSessionTask (CGRHistoryStartProbe)
- (void)cgr_historyResume;
@end

@implementation NSURLSessionTask (CGRHistoryStartProbe)
- (void)cgr_historyResume {
    NSURLRequest *request = self.currentRequest ?: self.originalRequest;
    if (CGRHistoryRequest(request)) {
        CGRLog([NSString stringWithFormat:@"v0.6 task_history_resume offset=%@ limit=%@",
                CGRPage(request.URL, @"offset"), CGRPage(request.URL, @"limit")]);
    }
    [self cgr_historyResume];
}
@end

static void CGRInstallHistoryInterceptorBypass(void) {
    Class protocolClass = objc_getClass("LVBVoiceURLProtocol");
    if (!protocolClass) {
        CGRLog(@"v0.6 LVBVoiceURLProtocol class missing: no bypass installed");
        return;
    }
    Method old = class_getClassMethod(protocolClass, @selector(canInitWithRequest:));
    if (!old) {
        CGRLog(@"v0.6 +canInitWithRequest: missing: no bypass installed");
        return;
    }
    sOriginalCanInit = (CGRCanInitIMP)method_getImplementation(old);
    if (!sOriginalCanInit || sOriginalCanInit == (CGRCanInitIMP)CGRLegacyCanInit) {
        CGRLog(@"v0.6 original interceptor unavailable: no bypass installed");
        return;
    }
    // Install a method on the specific metaclass; leave NSURLProtocol and every
    // other protocol's canInitWithRequest: implementation unchanged.
    const char *encoding = method_getTypeEncoding(old);
    class_replaceMethod(object_getClass(protocolClass),
                        @selector(canInitWithRequest:),
                        (IMP)CGRLegacyCanInit, encoding);
    CGRLog(@"v0.6 original protocol located; conversation-list GET bypass installed");
}

__attribute__((constructor)) static void CGRStart(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
        CGRLog(@"v0.6.0 isolated history test loaded; no response rewriting or new URLProtocol");
        CGRInstallHistoryInterceptorBypass();
        Method m = class_getInstanceMethod([NSURLSessionTask class], @selector(resume));
        Method ours = class_getInstanceMethod([NSURLSessionTask class],
                                               @selector(cgr_historyResume));
        if (m && ours) method_exchangeImplementations(m, ours);
    }
}
