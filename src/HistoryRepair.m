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

static NSString *CGRModelCategory(NSDictionary *root) {
    id model = root[@"model_slug"] ?: root[@"default_model_slug"] ?: root[@"model"];
    if ([model isKindOfClass:[NSDictionary class]]) {
        model = model[@"slug"] ?: model[@"id"];
    }
    if (![model isKindOfClass:[NSString class]]) {
        id mapping = root[@"mapping"];
        id currentNode = root[@"current_node"];
        if ([mapping isKindOfClass:[NSDictionary class]] &&
            [currentNode isKindOfClass:[NSString class]]) {
            id node = mapping[currentNode];
            if ([node isKindOfClass:[NSDictionary class]]) {
                id msg = node[@"message"];
                id meta = [msg isKindOfClass:[NSDictionary class]] ? msg[@"metadata"] : nil;
                if ([meta isKindOfClass:[NSDictionary class]]) model = meta[@"model_slug"];
            }
        }
    }
    if (![model isKindOfClass:[NSString class]]) return @"missing";
    NSString *s = [(NSString *)model lowercaseString];
    if ([s hasPrefix:@"gpt-4"] || [s hasPrefix:@"gpt-3"]) return @"legacy-gpt";
    if ([s hasPrefix:@"gpt-5"] || [s hasPrefix:@"gpt-6"]) return @"newer-gpt";
    if ([s hasPrefix:@"o1"] || [s hasPrefix:@"o3"] || [s hasPrefix:@"o4"]) return @"reasoning";
    return @"other";
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
        CGRLog([NSString stringWithFormat:@"detail model_category=%@ fields=%@",
                CGRModelCategory(j), [found componentsJoinedByString:@","]]);
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
- (void)cgrCompleteWithData:(NSData *)data
                   response:(NSURLResponse *)response
                      error:(NSError *)error
                      route:(CGRRoute)route {
    if (self.cgrStopped) return;
    id<NSURLProtocolClient> client = self.client;
    NSString *label = route == CGRRouteHistory ? @"history" : @"detail";
    if (error) {
        CGRLog([NSString stringWithFormat:@"%@ network_error=%ld", label,
                (long)error.code]);
        [client URLProtocol:self didFailWithError:error];
    } else if (!response) {
        [client URLProtocol:self didFailWithError:
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
                    [key caseInsensitiveCompare:@"Content-MD5"] == NSOrderedSame)
                    [headers removeObjectForKey:key];
            }
            sent = [[NSHTTPURLResponse alloc] initWithURL:http.URL
                   statusCode:http.statusCode HTTPVersion:@"HTTP/1.1"
                   headerFields:headers];
        }
        [client URLProtocol:self didReceiveResponse:sent
                 cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        if (output.length) [client URLProtocol:self didLoadData:output];
        [client URLProtocolDidFinishLoading:self];
    }
    [self.cgrSession finishTasksAndInvalidate];
    self.cgrTask = nil;
}

/* A 500 might be caused by old optional query defaults.
 * Retry once with an explicit non-archived filter. If it does not return a
 * decodable list, deliver the ORIGINAL server reply, unchanged.
 * This never fabricates a conversation, authentication token, or success.
 */
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

        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? [(NSHTTPURLResponse *)response statusCode] : 0;
        NSURLComponents *components = [NSURLComponents componentsWithURL:copy.URL
                                               resolvingAgainstBaseURL:NO];
        BOOL archivedAlreadySpecified = NO;
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:@"is_archived"]) {
                archivedAlreadySpecified = YES;
                break;
            }
        }
        if (route == CGRRouteHistory && !error && status == 500 &&
            components && !archivedAlreadySpecified) {
            // Test only the observed missing flag. Preserve pagination, ordering,
            // cookies, account headers, and the original request otherwise.
            NSMutableArray<NSURLQueryItem *> *query =
                [components.queryItems mutableCopy] ?: [NSMutableArray array];
            [query addObject:[NSURLQueryItem queryItemWithName:@"is_archived"
                                                         value:@"false"]];
            components.queryItems = query;
            NSMutableURLRequest *alternative = [copy mutableCopy];
            alternative.URL = components.URL;
            alternative.timeoutInterval = 12;
            if (!alternative.URL) {
                [strongSelf cgrCompleteWithData:data response:response
                                          error:error route:route];
                return;
            }
            CGRLog(@"history original_500; retrying_once variant=is_archived_false");
            strongSelf.cgrTask = [strongSelf.cgrSession dataTaskWithRequest:alternative
              completionHandler:^(NSData *retryData, NSURLResponse *retryResponse,
                                  NSError *retryError) {
                __strong typeof(weakSelf) again = weakSelf;
                if (!again || again.cgrStopped) return;
                NSInteger retryStatus = [retryResponse isKindOfClass:
                                            [NSHTTPURLResponse class]]
                    ? [(NSHTTPURLResponse *)retryResponse statusCode] : 0;
                id retryJSON = retryData
                    ? [NSJSONSerialization JSONObjectWithData:retryData
                                                      options:0 error:NULL] : nil;
                BOOL listOK = [retryJSON isKindOfClass:[NSDictionary class]] &&
                    ([retryJSON[@"items"] isKindOfClass:[NSArray class]] ||
                     CGRAlternativeItems(retryJSON) != nil);
                CGRLog([NSString stringWithFormat:
                   @"history retry variant=is_archived_false status=%ld network_error=%ld list_valid=%d",
                   (long)retryStatus, (long)retryError.code, (int)listOK]);
                if (!retryError && retryStatus == 200 && listOK) {
                    [again cgrCompleteWithData:retryData response:retryResponse
                                         error:nil route:route];
                } else {
                    [again cgrCompleteWithData:data response:response
                                         error:error route:route];
                }
              }];
            [strongSelf.cgrTask resume];
            return;
        }
        [strongSelf cgrCompleteWithData:data response:response
                                  error:error route:route];
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

/*
 * IPA-grounded request probe. NSURLProtocol only observes sessions where the
 * client has registered it; the Swift client also uses its own task delegates.
 * An NSURLSessionTask resume hook supplies route/pagination evidence without
 * reading message bodies, request headers, cookies or conversation IDs.
 */
static NSString *CGRProbeLabel(NSURLRequest *request) {
    NSURL *url = request.URL;
    if (!CGROfficialHost(url.host)) return nil;
    NSString *p = url.path ?: @"";
    if ([p isEqualToString:@"/backend-api/conversations"] ||
        [p isEqualToString:@"/conversations"] ||
        [p isEqualToString:@"/backend-api/conversations/"] ||
        [p isEqualToString:@"/conversations/"]) return @"history-list";
    if ([p isEqualToString:@"/backend-api/conversation/init"] ||
        [p isEqualToString:@"/conversation/init"]) return @"conversation-init";
    if ([p isEqualToString:@"/backend-api/conversation"] ||
        [p isEqualToString:@"/conversation"]) return @"conversation-send";
    if ([p containsString:@"conversation_detail_metadata"] ||
        [p containsString:@"conversation-detail-metadata"] ||
        [p containsString:@"conversation_detail"]) return @"conversation-metadata";
    if (([p hasPrefix:@"/backend-api/conversation/"] ||
         [p hasPrefix:@"/conversation/"]) &&
        ![p containsString:@"/voice/"]) return @"conversation-detail";
    return nil;
}

static NSString *CGRSafePageValue(NSURL *url, NSString *key) {
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url
                                        resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *q in parts.queryItems) {
        if (![q.name isEqualToString:key]) continue;
        NSString *v = q.value ?: @"";
        if (v.length == 0 || v.length > 7) return @"invalid";
        NSCharacterSet *notDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        return [v rangeOfCharacterFromSet:notDigits].location == NSNotFound ? v : @"invalid";
    }
    return @"-";
}

@interface NSURLSessionTask (CGRIPARequestProbe)
- (void)cgr_probeResume;
@end

@implementation NSURLSessionTask (CGRIPARequestProbe)
- (void)cgr_probeResume {
    NSURLRequest *request = self.currentRequest ?: self.originalRequest;
    NSString *category = CGRProbeLabel(request);
    if (category) {
        NSString *method = [request.HTTPMethod.uppercaseString isEqualToString:@"POST"]
            ? @"POST" : @"GET";
        if ([category isEqualToString:@"history-list"]) {
            CGRLog([NSString stringWithFormat:
                @"probe route=%@ method=%@ offset=%@ limit=%@ order_present=%d archived_present=%d",
                category, method,
                CGRSafePageValue(request.URL, @"offset"),
                CGRSafePageValue(request.URL, @"limit"),
                (int)([NSURLComponents componentsWithURL:request.URL
                  resolvingAgainstBaseURL:NO].queryItems
                  ? [[request.URL.query lowercaseString] containsString:@"order="] : NO),
                (int)[[request.URL.query lowercaseString] containsString:@"is_archived="]]);
        } else {
            CGRLog([NSString stringWithFormat:@"probe route=%@ method=%@",
                   category, method]);
        }
    }
    [self cgr_probeResume];
}
@end

static void CGRSwizzleTaskResume(void) {
    Method original = class_getInstanceMethod([NSURLSessionTask class],
                                             @selector(resume));
    Method replacement = class_getInstanceMethod([NSURLSessionTask class],
                                                @selector(cgr_probeResume));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}

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
        CGRSwizzleTaskResume();
        CGRLog(@"v0.3.0 loaded: history 500 fallback experiment + attachment diagnostics");
    }
}
