#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static const void *kCGDiagTaskIDKey = &kCGDiagTaskIDKey;
static unsigned long long gCGDiagSequence = 0;
static dispatch_queue_t gCGDiagLogQueue;

static NSString *CGDiagLogPath(void) {
    NSArray<NSString *> *paths=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES);
    NSString *documents=paths.firstObject;
    return documents.length?[documents stringByAppendingPathComponent:@"ChatGPTBlankChatsDiag.log"]:nil;
}

static NSString *CGDiagStamp(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        formatter=[NSDateFormatter new];
        formatter.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone=[NSTimeZone localTimeZone];
        formatter.dateFormat=@"yyyy-MM-dd HH:mm:ss.SSS Z";
    });
    @synchronized(formatter) {
        return [formatter stringFromDate:[NSDate date]];
    }
}

static void CGDiagWrite(NSString *line) {
    if (!line.length) return;
    if (!gCGDiagLogQueue) gCGDiagLogQueue=dispatch_queue_create("com.551uk.chatgpt.blankdiag.log",DISPATCH_QUEUE_SERIAL);
    NSString *entry=[NSString stringWithFormat:@"%@ %@\n",CGDiagStamp(),line];
    dispatch_async(gCGDiagLogQueue,^{
        @autoreleasepool {
            NSString *path=CGDiagLogPath();
            if (!path.length) return;
            NSData *data=[entry dataUsingEncoding:NSUTF8StringEncoding];
            NSFileManager *fm=NSFileManager.defaultManager;
            if (![fm fileExistsAtPath:path]) {
                [data writeToFile:path atomically:YES];
                return;
            }
            NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:path];
            if (!h) return;
            @try {
                [h seekToEndOfFile];
                [h writeData:data];
            } @catch (__unused NSException *e) {}
            [h closeFile];
        }
    });
}

static NSString *CGDiagSafe(NSString *s, NSUInteger max) {
    if (!s) return @"";
    NSString *v=[s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    v=[v stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    return v.length>max?[[v substringToIndex:max] stringByAppendingString:@"…"]:v;
}

static BOOL CGDiagTrustedHost(NSString *host) {
    NSString *h=host.lowercaseString;
    return [h isEqualToString:@"chatgpt.com"] || [h hasSuffix:@".chatgpt.com"] ||
           [h isEqualToString:@"openai.com"] || [h hasSuffix:@".openai.com"];
}

static NSString *CGDiagKind(NSURLRequest *request) {
    NSURL *u=request.URL;
    if (!CGDiagTrustedHost(u.host)) return nil;
    NSString *path=u.path?:@"";
    NSString *method=request.HTTPMethod.uppercaseString?:@"GET";
    if ([method isEqualToString:@"GET"] &&
        ([path isEqualToString:@"/backend-api/conversations"] ||
         [path isEqualToString:@"/backend-api/conversations/"] ||
         [path isEqualToString:@"/conversations"] ||
         [path isEqualToString:@"/conversations/"])) return @"HISTORY";
    NSArray<NSString *> *parts=[path componentsSeparatedByString:@"/"];
    if ([method isEqualToString:@"GET"] &&
        ((parts.count==4 && [parts[1] isEqualToString:@"backend-api"] && [parts[2] isEqualToString:@"conversation"] && [parts[3] length]) ||
         (parts.count==3 && [parts[1] isEqualToString:@"conversation"] && [parts[2] length])))
        return @"DETAIL";
    if ([path containsString:@"/backend-api/pins"]) return @"PINS";
    return nil;
}

static NSString *CGDiagQueryValue(NSURL *url, NSString *name) {
    NSURLComponents *parts=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *q in parts.queryItems) if ([q.name isEqualToString:name]) return q.value?:@"";
    return @"";
}

static NSString *CGDiagRequestSummary(NSURLRequest *request) {
    NSURL *u=request.URL;
    NSString *kind=CGDiagKind(request)?:@"OTHER";
    NSString *offset=CGDiagQueryValue(u,@"offset");
    NSString *limit=CGDiagQueryValue(u,@"limit");
    NSString *origin=CGDiagQueryValue(u,@"conversation_origin");
    NSString *exclude=CGDiagQueryValue(u,@"exclude_conversation_origin");
    BOOL auth=[[request valueForHTTPHeaderField:@"Authorization"] length]>0;
    BOOL retry=[[request valueForHTTPHeaderField:@"X-551UK-History-Retry"] isEqualToString:@"1"];
    BOOL merge=[[request valueForHTTPHeaderField:@"X-551UK-History-Merge"] isEqualToString:@"1"];
    return [NSString stringWithFormat:@"kind=%@ method=%@ host=%@ path=%@ offset=%@ limit=%@ origin=%@ exclude=%@ auth=%d retry=%d merge=%d",
            kind,request.HTTPMethod?:@"GET",u.host?:@"",u.path?:@"",
            offset.length?offset:@"-",limit.length?limit:@"-",
            origin.length?origin:@"-",exclude.length?exclude:@"-",
            auth,retry,merge];
}

static NSString *CGDiagHeader(NSHTTPURLResponse *response, NSString *name) {
    for (id key in response.allHeaderFields) {
        if ([key isKindOfClass:NSString.class] && [key caseInsensitiveCompare:name]==NSOrderedSame) {
            id value=response.allHeaderFields[key];
            return [value isKindOfClass:NSString.class]?value:[value description];
        }
    }
    return @"";
}

static void CGDiagLogHistoryJSON(unsigned long long ident, NSData *data) {
    if (!data.length || data.length>16*1024*1024) {
        CGDiagWrite([NSString stringWithFormat:@"[%llu] HISTORY_PARSE invalid-bytes=%lu",ident,(unsigned long)data.length]);
        return;
    }
    NSError *err=nil;
    id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (![json isKindOfClass:NSDictionary.class]) {
        CGDiagWrite([NSString stringWithFormat:@"[%llu] HISTORY_PARSE invalid-json error=%@",ident,CGDiagSafe(err.localizedDescription,180)]);
        return;
    }
    NSArray *items=[json[@"items"] isKindOfClass:NSArray.class]?json[@"items"]:nil;
    id total=json[@"total"];
    CGDiagWrite([NSString stringWithFormat:@"[%llu] HISTORY_JSON items=%lu total=%@ topKeys=%@",
                 ident,(unsigned long)items.count,total?:@"-",[[json allKeys] componentsJoinedByString:@","]]);
    NSUInteger index=0;
    for (id row in items) {
        if (![row isKindOfClass:NSDictionary.class]) continue;
        NSString *cid=[row[@"id"] isKindOfClass:NSString.class]?row[@"id"]:@"";
        NSString *title=[row[@"title"] isKindOfClass:NSString.class]?row[@"title"]:@"";
        NSString *updated=[row[@"update_time"] isKindOfClass:NSString.class]?row[@"update_time"]:@"";
        NSString *origin=[row[@"conversation_origin"] isKindOfClass:NSString.class]?row[@"conversation_origin"]:@"";
        CGDiagWrite([NSString stringWithFormat:@"[%llu] HISTORY_ITEM #%lu id=%@ title=\"%@\" updated=%@ origin=%@",
                     ident,(unsigned long)index++,cid,CGDiagSafe(title,120),updated,origin.length?origin:@"-"]);
    }
}

static void CGDiagLogDetailJSON(unsigned long long ident, NSData *data) {
    if (!data.length || data.length>32*1024*1024) {
        CGDiagWrite([NSString stringWithFormat:@"[%llu] DETAIL_PARSE invalid-bytes=%lu",ident,(unsigned long)data.length]);
        return;
    }
    NSError *err=nil;
    id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (![json isKindOfClass:NSDictionary.class]) {
        CGDiagWrite([NSString stringWithFormat:@"[%llu] DETAIL_PARSE invalid-json error=%@",ident,CGDiagSafe(err.localizedDescription,180)]);
        return;
    }
    NSDictionary *root=(NSDictionary *)json;
    NSString *cid=[root[@"conversation_id"] isKindOfClass:NSString.class]?root[@"conversation_id"]:
                  ([root[@"id"] isKindOfClass:NSString.class]?root[@"id"]:@"");
    NSString *title=[root[@"title"] isKindOfClass:NSString.class]?root[@"title"]:@"";
    NSDictionary *mapping=[root[@"mapping"] isKindOfClass:NSDictionary.class]?root[@"mapping"]:nil;
    NSString *current=[root[@"current_node"] isKindOfClass:NSString.class]?root[@"current_node"]:@"";
    NSUInteger messageNodes=0, assistantNodes=0, userNodes=0, contentParts=0;
    for (id key in mapping) {
        id node=mapping[key];
        if (![node isKindOfClass:NSDictionary.class]) continue;
        id message=node[@"message"];
        if (![message isKindOfClass:NSDictionary.class] || (id)message==(id)[NSNull null]) continue;
        messageNodes++;
        NSDictionary *author=[message[@"author"] isKindOfClass:NSDictionary.class]?message[@"author"]:nil;
        NSString *role=[author[@"role"] isKindOfClass:NSString.class]?author[@"role"]:@"";
        if ([role isEqualToString:@"assistant"]) assistantNodes++;
        if ([role isEqualToString:@"user"]) userNodes++;
        NSDictionary *content=[message[@"content"] isKindOfClass:NSDictionary.class]?message[@"content"]:nil;
        NSArray *parts=[content[@"parts"] isKindOfClass:NSArray.class]?content[@"parts"]:nil;
        contentParts+=parts.count;
    }
    BOOL currentPresent=current.length && mapping[current]!=nil;
    BOOL blankRisk=(mapping.count==0 || !current.length || !currentPresent || messageNodes==0);
    CGDiagWrite([NSString stringWithFormat:@"[%llu] DETAIL_JSON id=%@ title=\"%@\" mapping=%lu messages=%lu user=%lu assistant=%lu parts=%lu current=%@ currentPresent=%d BLANK_RISK=%d topKeys=%@",
                 ident,cid,CGDiagSafe(title,120),(unsigned long)mapping.count,(unsigned long)messageNodes,
                 (unsigned long)userNodes,(unsigned long)assistantNodes,(unsigned long)contentParts,
                 current.length?current:@"-",(int)currentPresent,(int)blankRisk,
                 [[root allKeys] componentsJoinedByString:@","]]);
}

static void CGDiagResponse(unsigned long long ident, NSString *kind, NSURLRequest *request,
                           NSData *data, NSURLResponse *response, NSError *error) {
    NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
    NSHTTPURLResponse *http=[response isKindOfClass:NSHTTPURLResponse.class]?(NSHTTPURLResponse *)response:nil;
    NSString *cache=http?CGDiagHeader(http,@"X-551UK-History-Cache"):@"";
    NSString *retry=http?CGDiagHeader(http,@"Retry-After"):@"";
    NSString *requestID=http?CGDiagHeader(http,@"x-request-id"):@"";
    NSString *ray=http?CGDiagHeader(http,@"cf-ray"):@"";
    CGDiagWrite([NSString stringWithFormat:@"[%llu] COMPLETE kind=%@ status=%ld bytes=%lu error=%@ cache=%@ retryAfter=%@ requestID=%@ cfRay=%@ url=%@",
                 ident,kind,(long)status,(unsigned long)data.length,
                 error?CGDiagSafe([NSString stringWithFormat:@"%@/%ld %@",error.domain,(long)error.code,error.localizedDescription],240):@"none",
                 cache.length?cache:@"-",retry.length?retry:@"-",requestID.length?requestID:@"-",ray.length?ray:@"-",
                 request.URL.absoluteString?:@""]);
    if ([kind isEqualToString:@"HISTORY"] && status==200 && !error) CGDiagLogHistoryJSON(ident,data);
    if ([kind isEqualToString:@"DETAIL"] && status==200 && !error) CGDiagLogDetailJSON(ident,data);
    if ((status<200 || status>=300 || error) && data.length && data.length<=4096) {
        NSString *preview=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (preview.length) CGDiagWrite([NSString stringWithFormat:@"[%llu] ERROR_BODY %@",ident,CGDiagSafe(preview,700)]);
    }
}

static void CGDiagPollTask(NSURLSessionTask *task, unsigned long long ident, NSString *kind, NSTimeInterval delay) {
    if (!task) return;
    __weak NSURLSessionTask *weakTask=task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSURLSessionTask *t=weakTask;
        if (!t) {
            CGDiagWrite([NSString stringWithFormat:@"[%llu] POLL %.0fs kind=%@ task=deallocated",ident,delay,kind]);
            return;
        }
        NSURLRequest *current=t.currentRequest;
        NSURLResponse *response=t.response;
        NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
        CGDiagWrite([NSString stringWithFormat:@"[%llu] POLL %.0fs kind=%@ state=%ld status=%ld recv=%lld sent=%lld error=%@ current=%@",
                     ident,delay,kind,(long)t.state,(long)status,t.countOfBytesReceived,t.countOfBytesSent,
                     t.error?CGDiagSafe([NSString stringWithFormat:@"%@/%ld %@",t.error.domain,(long)t.error.code,t.error.localizedDescription],220):@"none",
                     current.URL.absoluteString?:@""]);
    });
}

static void CGDiagAttachTask(NSURLSessionTask *task, unsigned long long ident, NSString *kind) {
    if (!task) return;
    if (objc_getAssociatedObject(task,kCGDiagTaskIDKey)) return;
    objc_setAssociatedObject(task,kCGDiagTaskIDKey,@(ident),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGDiagPollTask(task,ident,kind,1.0);
    CGDiagPollTask(task,ident,kind,5.0);
    CGDiagPollTask(task,ident,kind,15.0);
}

@interface NSURLSession (CGBlankDiag)
- (NSURLSessionDataTask *)cgdiag_dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)cgdiag_dataTaskWithRequest:(NSURLRequest *)request
                                  completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion;
@end

@implementation NSURLSession (CGBlankDiag)
- (NSURLSessionDataTask *)cgdiag_dataTaskWithRequest:(NSURLRequest *)request {
    NSString *kind=CGDiagKind(request);
    if (!kind) return [self cgdiag_dataTaskWithRequest:request];
    unsigned long long ident=__sync_add_and_fetch(&gCGDiagSequence,1);
    CGDiagWrite([NSString stringWithFormat:@"[%llu] CREATE no-completion %@ url=%@",ident,CGDiagRequestSummary(request),request.URL.absoluteString?:@""]);
    NSURLSessionDataTask *task=[self cgdiag_dataTaskWithRequest:request];
    CGDiagAttachTask(task,ident,kind);
    return task;
}

- (NSURLSessionDataTask *)cgdiag_dataTaskWithRequest:(NSURLRequest *)request
                                  completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion {
    NSString *kind=CGDiagKind(request);
    if (!kind) return [self cgdiag_dataTaskWithRequest:request completionHandler:completion];
    unsigned long long ident=__sync_add_and_fetch(&gCGDiagSequence,1);
    CGDiagWrite([NSString stringWithFormat:@"[%llu] CREATE completion %@ url=%@",ident,CGDiagRequestSummary(request),request.URL.absoluteString?:@""]);
    void (^wrapped)(NSData *,NSURLResponse *,NSError *)=completion?^(NSData *data,NSURLResponse *response,NSError *error) {
        CGDiagResponse(ident,kind,request,data,response,error);
        completion(data,response,error);
    }:nil;
    NSURLSessionDataTask *task=[self cgdiag_dataTaskWithRequest:request completionHandler:wrapped];
    CGDiagAttachTask(task,ident,kind);
    return task;
}
@end

static void CGDiagSwizzle(Class cls, SEL original, SEL replacement) {
    Method a=class_getInstanceMethod(cls,original);
    Method b=class_getInstanceMethod(cls,replacement);
    if (a && b) method_exchangeImplementations(a,b);
}

static void CGDiagLogCacheState(void) {
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/ChatGPT551HistoryPages"];
    NSArray<NSString *> *files=[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:NULL];
    CGDiagWrite([NSString stringWithFormat:@"CACHE directory=%@ files=%lu",dir,(unsigned long)files.count]);
    NSDate *now=[NSDate date];
    for (NSString *name in files) {
        NSString *path=[dir stringByAppendingPathComponent:name];
        NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
        NSDate *date=attrs[NSFileModificationDate];
        NSNumber *size=attrs[NSFileSize];
        NSTimeInterval age=date?[now timeIntervalSinceDate:date]:-1;
        CGDiagWrite([NSString stringWithFormat:@"CACHE_FILE %@ bytes=%@ age=%.0fs",name,size?:@0,age]);
    }
}

static void CGDiagVisibleController(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        UIWindow *window=nil;
        for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
            if (!candidate.hidden && candidate.alpha>0) { window=candidate; break; }
        }
        UIViewController *vc=window.rootViewController;
        NSMutableArray<NSString *> *chain=[NSMutableArray array];
        NSUInteger guard=0;
        while (vc && guard++<20) {
            [chain addObject:NSStringFromClass(vc.class)];
            if (vc.presentedViewController) vc=vc.presentedViewController;
            else if ([vc isKindOfClass:UINavigationController.class]) vc=((UINavigationController *)vc).visibleViewController;
            else if ([vc isKindOfClass:UITabBarController.class]) vc=((UITabBarController *)vc).selectedViewController;
            else break;
        }
        CGDiagWrite([NSString stringWithFormat:@"UI visible=%@",[chain componentsJoinedByString:@" > "]]);
    });
}

__attribute__((constructor))
static void CGBlankDiagInit(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;

        // Force the known-good production components to load first, then attach passive diagnostics.
        dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/ChatGPTRepair.dylib",RTLD_LAZY|RTLD_GLOBAL);
        dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/ChatGBeFree.dylib",RTLD_LAZY|RTLD_GLOBAL);
        dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/ZZChatGPTDownloadFix.dylib",RTLD_LAZY|RTLD_GLOBAL);
        dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/ZZChatGPTLinkFix.dylib",RTLD_LAZY|RTLD_GLOBAL);

        NSString *path=CGDiagLogPath();
        if (path.length) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

        CGDiagWrite(@"=== ChatGPT Blank Chats Diagnostic 1 launch ===");
        CGDiagWrite([NSString stringWithFormat:@"bundle=%@ shortVersion=%@ build=%@ os=%@",
                     NSBundle.mainBundle.bundleIdentifier?:@"",
                     [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"",
                     [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"",
                     UIDevice.currentDevice.systemVersion?:@""]);
        CGDiagLogCacheState();

        CGDiagSwizzle(NSURLSession.class,@selector(dataTaskWithRequest:),@selector(cgdiag_dataTaskWithRequest:));
        CGDiagSwizzle(NSURLSession.class,@selector(dataTaskWithRequest:completionHandler:),@selector(cgdiag_dataTaskWithRequest:completionHandler:));
        CGDiagWrite(@"hooks installed: NSURLSession request + completion paths");

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *note) {
            CGDiagWrite(@"APP didBecomeActive");
            CGDiagVisibleController();
        }];
    }
}
