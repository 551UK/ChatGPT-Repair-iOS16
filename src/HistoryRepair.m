/*
 * ChatGPT Repair iOS16 — 551UK — GPL-3.0
 * Experimental history compatibility and attachment-related metadata probe.
 *
 * No chat messages, titles, conversation IDs, credentials or headers are logged.
 * This package does not include or modify Liam's ChatGBeFree binary.
 */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *const kCGRHandled = @"com.551uk.ChatGPTRepair.requestHandled";

static void CGRLog(NSString *line) {
    if (!line) return;
    @synchronized([NSFileHandle class]) {
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/ChatGPT551Repair.log"];
        NSString *message = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], line];
        NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path])
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *f = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!f) return;
        @try { [f seekToEndOfFile]; [f writeData:data]; }
        @catch (__unused NSException *e) {}
        @finally { [f closeFile]; }
    }
}

typedef NS_ENUM(NSInteger, CGRRoute) { CGRRouteNone, CGRRouteHistory, CGRRouteDetail };

static BOOL CGROfficialHost(NSString *host) {
    NSString *h = host.lowercaseString;
    return [h isEqualToString:@"openai.com"] || [h hasSuffix:@".openai.com"] ||
           [h isEqualToString:@"chatgpt.com"] || [h hasSuffix:@".chatgpt.com"];
}
static CGRRoute CGRRouteForRequest(NSURLRequest *request) {
    if (![[request.HTTPMethod uppercaseString] isEqualToString:@"GET"]) return CGRRouteNone;
    if (!CGROfficialHost(request.URL.host)) return CGRRouteNone;
    NSString *path = request.URL.path ?: @"";
    if ([path isEqualToString:@"/backend-api/conversations"] ||
        [path isEqualToString:@"/backend-api/conversations/"] ||
        [path isEqualToString:@"/conversations"] ||
        [path isEqualToString:@"/conversations/"]) return CGRRouteHistory;

    // Only a single conversation detail GET; not POST streams or voice operations.
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    if (parts.count == 4 && [parts[1] isEqualToString:@"backend-api"] &&
        [parts[2] isEqualToString:@"conversation"] && [parts[3] length] > 0)
        return CGRRouteDetail;
    if (parts.count == 3 && [parts[1] isEqualToString:@"conversation"] &&
        [parts[2] length] > 0) return CGRRouteDetail;
    return CGRRouteNone;
}
static NSArray *CGRAlternativeItems(NSDictionary *root) {
    id v = root[@"conversations"];
    if ([v isKindOfClass:[NSArray class]]) return v;
    id inner = root[@"data"];
    if (![inner isKindOfClass:[NSDictionary class]]) return nil;
    v = inner[@"items"];
    if ([v isKindOfClass:[NSArray class]]) return v;
    v = inner[@"conversations"];
    return [v isKindOfClass:[NSArray class]] ? v : nil;
}

static NSData *CGRRewriteIfSafe(NSData *data, NSURLResponse *response, CGRRoute route) {
    if (!data || data.length > 5 * 1024 * 1024 ||
        ![response isKindOfClass:[NSHTTPURLResponse class]]) return data;
    if (((NSHTTPURLResponse *)response).statusCode != 200) return data;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![root isKindOfClass:[NSDictionary class]]) {
        CGRLog(route == CGRRouteHistory ? @"history invalid JSON envelope" :
                                            @"detail invalid JSON envelope");
        return data;
    }
    NSDictionary *j = (NSDictionary *)root;
    if (route == CGRRouteDetail) {
        // Compare the structural presence of fields across web- vs app-created chats.
        // No values, content, model names, or identifiers leave the device.
        NSMutableArray *found = [NSMutableArray array];
        for (NSString *key in @[@"model_slug", @"model", @"supports_attachments",
                               @"can_upload", @"capabilities", @"mapping",
                               @"current_node", @"conversation_template_id"]) {
            if (j[key] != nil) [found addObject:key];
        }
        CGRLog([NSString stringWithFormat:@"detail fields=%@",
                [found componentsJoinedByString:@","]]);
        return data;
    }
    id native = j[@"items"];
    if ([native isKindOfClass:[NSArray class]]) {
        CGRLog([NSString stringWithFormat:@"history native items=%lu",
                (unsigned long)[native count]]);
        return data;
    }
    NSArray *alternative = CGRAlternativeItems(j);
    if (!alternative) {
        NSMutableArray *known = [NSMutableArray array];
        for (NSString *key in @[@"data", @"conversations", @"items",
                                @"total", @"offset", @"limit", @"cursor"]) {
            if (j[key] != nil) [known addObject:key];
        }
        CGRLog([NSString stringWithFormat:@"history unknown format fields=%@",
                [known componentsJoinedByString:@","]]);
        return data;
    }
    NSMutableDictionary *converted = [j mutableCopy];
    converted[@"items"] = alternative;
    if (!converted[@"total"]) converted[@"total"] = @(alternative.count);
    if (!converted[@"offset"]) converted[@"offset"] = @0;
    if (!converted[@"limit"]) converted[@"limit"] = @(alternative.count);
    NSData *result = [NSJSONSerialization dataWithJSONObject:converted options:0 error:NULL];
    if (!result) return data;
    CGRLog([NSString stringWithFormat:@"history converted items=%lu",
            (unsigned long)alternative.count]);
    return result;
}

@interface CGRHistoryProtocol : NSURLProtocol
@property (nonatomic, strong) NSURLSession *cgrSession;
@property (nonatomic, strong) NSURLSessionDataTask *cgrTask;
@property (nonatomic, assign) BOOL cgrStopped;
@end

@implementation CGRHistoryProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:kCGRHandled inRequest:request]) return NO;
    return CGRRouteForRequest(request) != CGRRouteNone;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    self.cgrStopped = NO;
    CGRRoute route = CGRRouteForRequest(self.request);
    if (route == CGRRouteNone) return;
    NSMutableURLRequest *copy = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kCGRHandled inRequest:copy];
    if (route == CGRRouteHistory) {
        copy.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        [copy setValue:nil forHTTPHeaderField:@"If-None-Match"];
        [copy setValue:nil forHTTPHeaderField:@"If-Modified-Since"];
    }
    self.cgrSession = [NSURLSession sessionWithConfiguration:
                       [NSURLSessionConfiguration ephemeralSessionConfiguration]];
    __weak typeof(self) weakSelf = self;
    self.cgrTask = [self.cgrSession dataTaskWithRequest:copy
      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.cgrStopped) return;
        id<NSURLProtocolClient> client = strongSelf.client;
        NSString *label = route == CGRRouteHistory ? @"history" : @"detail";
        if (error) {
            CGRLog([NSString stringWithFormat:@"%@ network_error=%ld",
                    label, (long)error.code]);
            [client URLProtocol:strongSelf didFailWithError:error];
        } else if (!response) {
            [client URLProtocol:strongSelf didFailWithError:
                [NSError errorWithDomain:NSURLErrorDomain
                                    code:NSURLErrorUnknown userInfo:nil]];
        } else {
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
                ? [(NSHTTPURLResponse *)response statusCode] : 0;
            CGRLog([NSString stringWithFormat:@"%@ status=%ld bytes=%lu",
                    label, (long)status, (unsigned long)data.length]);
            NSData *output = CGRRewriteIfSafe(data, response, route);
            NSURLResponse *sent = response;
            if (output != data && [response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
                NSMutableDictionary *headers = [http.allHeaderFields mutableCopy];
                for (NSString *key in [headers allKeys]) {
                    if ([key caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame ||
                        [key caseInsensitiveCompare:@"Content-Encoding"] == NSOrderedSame ||
                        [key caseInsensitiveCompare:@"Content-MD5"] == NSOrderedSame) {
                        [headers removeObjectForKey:key];
                    }
                }
                sent = [[NSHTTPURLResponse alloc] initWithURL:http.URL
                       statusCode:http.statusCode HTTPVersion:@"HTTP/1.1"
                       headerFields:headers];
            }
            [client URLProtocol:strongSelf didReceiveResponse:sent
                          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            if (output.length) [client URLProtocol:strongSelf didLoadData:output];
            [client URLProtocolDidFinishLoading:strongSelf];
        }
        [strongSelf.cgrSession finishTasksAndInvalidate];
        strongSelf.cgrTask = nil;
    }];
    [self.cgrTask resume];
}
- (void)stopLoading {
    self.cgrStopped = YES;
    [self.cgrTask cancel];
    [self.cgrSession invalidateAndCancel];
    self.cgrTask = nil;
    self.cgrSession = nil;
}
@end

static void CGRInsert(NSURLSessionConfiguration *cfg) {
    if (!cfg) return;
    NSArray *classes = cfg.protocolClasses ?: @[];
    if (![classes containsObject:[CGRHistoryProtocol class]]) {
        cfg.protocolClasses = [@[[CGRHistoryProtocol class]]
                                arrayByAddingObjectsFromArray:classes];
    }
}

@interface NSURLSessionConfiguration (CGRCompatibility)
+ (NSURLSessionConfiguration *)cgr_defaultSessionConfiguration;
+ (NSURLSessionConfiguration *)cgr_ephemeralSessionConfiguration;
@end
@implementation NSURLSessionConfiguration (CGRCompatibility)
+ (NSURLSessionConfiguration *)cgr_defaultSessionConfiguration {
    NSURLSessionConfiguration *cfg = [self cgr_defaultSessionConfiguration];
    CGRInsert(cfg);
    return cfg;
}
+ (NSURLSessionConfiguration *)cgr_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *cfg = [self cgr_ephemeralSessionConfiguration];
    CGRInsert(cfg);
    return cfg;
}
@end

static void CGRSwizzle(Class cls, SEL a, SEL b) {
    Method oldMethod = class_getClassMethod(cls, a);
    Method newMethod = class_getClassMethod(cls, b);
    if (oldMethod && newMethod) method_exchangeImplementations(oldMethod, newMethod);
}

__attribute__((constructor)) static void CGRBoot(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
        [NSURLProtocol registerClass:[CGRHistoryProtocol class]];
        CGRSwizzle([NSURLSessionConfiguration class],
                   @selector(defaultSessionConfiguration),
                   @selector(cgr_defaultSessionConfiguration));
        CGRSwizzle([NSURLSessionConfiguration class],
                   @selector(ephemeralSessionConfiguration),
                   @selector(cgr_ephemeralSessionConfiguration));
        CGRLog(@"v0.1.0 loaded: source-written history adapter and attachment probe");
    }
}
