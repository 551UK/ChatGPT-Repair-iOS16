#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <sys/time.h>

static FILE *sLogFile;
static NSLock *sLogLock;
static NSString *sLogPath;
static BOOL sNetworkHooked;
static BOOL sHistoryHooked;
static uint64_t sRequestSerial;
static NSString *sLastDetailID;
static uint64_t sLastDetailRequestSerial;
static BOOL sSidebarKnown;
static BOOL sSidebarVisible;
static dispatch_source_t sUITimer;

static IMP sOrigWillAppear;
static IMP sOrigDidAppear;
static IMP sOrigWillDisappear;
static IMP sOrigDidDisappear;

static void SBDLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void SBDLog(NSString *format, ...) {
    if (!format) return;
    va_list args;
    va_start(args,format);
    NSString *message=[[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    struct timeval tv={0};
    gettimeofday(&tv,NULL);
    struct tm local={0};
    localtime_r(&tv.tv_sec,&local);
    char stamp[64]={0};
    strftime(stamp,sizeof(stamp),"%Y-%m-%d %H:%M:%S",&local);

    [sLogLock lock];
    if (sLogFile) {
        fprintf(sLogFile,"%s.%03d %s\n",stamp,(int)(tv.tv_usec/1000),message.UTF8String ?: "");
        fflush(sLogFile);
    }
    [sLogLock unlock];
}

static NSString *SBDDocumentsPath(void) {
    NSArray *paths=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES);
    return paths.firstObject ?: NSTemporaryDirectory();
}

static double SBDResidentMB(void) {
    mach_task_basic_info_data_t info={0};
    mach_msg_type_number_t count=MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t kr=task_info(mach_task_self(),MACH_TASK_BASIC_INFO,
                               (task_info_t)&info,&count);
    if (kr!=KERN_SUCCESS) return -1;
    return (double)info.resident_size/(1024.0*1024.0);
}

static NSString *SBDClass(id object) {
    return object?NSStringFromClass([object class]):@"-";
}

static BOOL SBDRelevantRequest(NSURLRequest *request) {
    NSURL *url=request.URL;
    if (!url) return NO;
    NSString *path=url.path ?: @"";
    if (![path containsString:@"/backend-api/"]) return NO;
    return [path containsString:@"conversation"] || [path containsString:@"pins"];
}

static NSString *SBDRequestKind(NSURLRequest *request) {
    NSString *path=request.URL.path ?: @"";
    if ([path hasPrefix:@"/backend-api/conversation/"] &&
        ![path hasPrefix:@"/backend-api/conversations"]) return @"DETAIL";
    if ([path isEqualToString:@"/backend-api/conversations"] ||
        [path isEqualToString:@"/backend-api/conversations/"]) return @"HISTORY";
    if ([path containsString:@"/backend-api/pins"]) return @"PINS";
    return @"BACKEND";
}

static NSString *SBDDetailID(NSURLRequest *request) {
    if (![[SBDRequestKind(request) uppercaseString] isEqualToString:@"DETAIL"]) return nil;
    NSString *cid=request.URL.lastPathComponent;
    return [[NSUUID alloc] initWithUUIDString:cid]?cid:nil;
}

static NSInteger SBDStatus(NSURLResponse *response) {
    return [response isKindOfClass:NSHTTPURLResponse.class]
        ? ((NSHTTPURLResponse *)response).statusCode : 0;
}

static void SBDLogJSONSummary(uint64_t serial, NSString *kind, NSData *data) {
    if (!data.length || data.length>20*1024*1024) return;
    NSError *error=nil;
    id root=[NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![root isKindOfClass:NSDictionary.class]) {
        SBDLog(@"NET[%llu] JSON_PARSE kind=%@ error=%@/%ld",
               serial,kind,error.domain ?: @"-",(long)error.code);
        return;
    }
    NSDictionary *dict=(NSDictionary *)root;
    if ([kind isEqualToString:@"DETAIL"]) {
        NSDictionary *mapping=[dict[@"mapping"] isKindOfClass:NSDictionary.class]?dict[@"mapping"]:nil;
        NSString *current=[dict[@"current_node"] isKindOfClass:NSString.class]?dict[@"current_node"]:nil;
        NSUInteger messages=0,parts=0;
        for (id value in mapping.allValues) {
            if (![value isKindOfClass:NSDictionary.class]) continue;
            id message=((NSDictionary *)value)[@"message"];
            if (![message isKindOfClass:NSDictionary.class]) continue;
            messages++;
            id content=((NSDictionary *)message)[@"content"];
            id p=[content isKindOfClass:NSDictionary.class]?((NSDictionary *)content)[@"parts"]:nil;
            if ([p isKindOfClass:NSArray.class]) parts += [(NSArray *)p count];
        }
        NSString *cid=[dict[@"conversation_id"] isKindOfClass:NSString.class]?dict[@"conversation_id"]:@"-";
        NSString *title=[dict[@"title"] isKindOfClass:NSString.class]?dict[@"title"]:@"-";
        BOOL present=current.length && [mapping[current] isKindOfClass:NSDictionary.class];
        SBDLog(@"NET[%llu] DETAIL_JSON id=%@ title=%@ mapping=%lu messages=%lu parts=%lu current=%@ currentPresent=%d",
               serial,cid,title,(unsigned long)mapping.count,(unsigned long)messages,
               (unsigned long)parts,current ?: @"-",present);
    } else if ([kind isEqualToString:@"HISTORY"]) {
        NSArray *items=[dict[@"items"] isKindOfClass:NSArray.class]?dict[@"items"]:nil;
        NSNumber *total=[dict[@"total"] isKindOfClass:NSNumber.class]?dict[@"total"]:nil;
        SBDLog(@"NET[%llu] HISTORY_JSON items=%lu total=%@",
               serial,(unsigned long)items.count,total ?: @"-");
    }
}

static void SBDPollTask(NSURLSessionTask *task, uint64_t serial, NSTimeInterval delay) {
    __weak NSURLSessionTask *weakTask=task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSURLSessionTask *t=weakTask;
        if (!t) {
            SBDLog(@"NET[%llu] POLL %.2fs task=deallocated",serial,delay);
            return;
        }
        NSInteger status=SBDStatus(t.response);
        SBDLog(@"NET[%llu] POLL %.2fs state=%ld status=%ld recv=%lld sent=%lld error=%@/%ld current=%@",
               serial,delay,(long)t.state,(long)status,
               t.countOfBytesReceived,t.countOfBytesSent,
               t.error.domain ?: @"-",(long)t.error.code,
               t.currentRequest.URL.absoluteString ?: @"-");
    });
}

@interface NSURLSession (SBDNetwork)
- (NSURLSessionDataTask *)sbd_dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)sbd_dataTaskWithRequest:(NSURLRequest *)request
                               completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion;
@end

@implementation NSURLSession (SBDNetwork)
- (NSURLSessionDataTask *)sbd_dataTaskWithRequest:(NSURLRequest *)request {
    if (!SBDRelevantRequest(request))
        return [self sbd_dataTaskWithRequest:request];

    uint64_t serial=__sync_add_and_fetch(&sRequestSerial,1);
    NSString *kind=SBDRequestKind(request);
    NSString *cid=SBDDetailID(request);
    if (cid) {
        sLastDetailID=[cid copy];
        sLastDetailRequestSerial=serial;
    }
    SBDLog(@"NET[%llu] CREATE noCompletion kind=%@ method=%@ url=%@",
           serial,kind,request.HTTPMethod ?: @"GET",request.URL.absoluteString ?: @"-");
    NSURLSessionDataTask *task=[self sbd_dataTaskWithRequest:request];
    SBDLog(@"NET[%llu] TASK id=%lu class=%@ state=%ld",
           serial,(unsigned long)task.taskIdentifier,SBDClass(task),(long)task.state);
    SBDPollTask(task,serial,0.25);
    SBDPollTask(task,serial,1.0);
    SBDPollTask(task,serial,3.0);
    SBDPollTask(task,serial,10.0);
    return task;
}

- (NSURLSessionDataTask *)sbd_dataTaskWithRequest:(NSURLRequest *)request
                               completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion {
    if (!SBDRelevantRequest(request))
        return [self sbd_dataTaskWithRequest:request completionHandler:completion];

    uint64_t serial=__sync_add_and_fetch(&sRequestSerial,1);
    NSString *kind=SBDRequestKind(request);
    NSString *cid=SBDDetailID(request);
    if (cid) {
        sLastDetailID=[cid copy];
        sLastDetailRequestSerial=serial;
    }
    SBDLog(@"NET[%llu] CREATE completion kind=%@ method=%@ url=%@",
           serial,kind,request.HTTPMethod ?: @"GET",request.URL.absoluteString ?: @"-");

    void (^wrapped)(NSData *,NSURLResponse *,NSError *)=^(NSData *data,NSURLResponse *response,NSError *error) {
        SBDLog(@"NET[%llu] COMPLETE kind=%@ status=%ld bytes=%lu error=%@/%ld responseURL=%@",
               serial,kind,(long)SBDStatus(response),(unsigned long)data.length,
               error.domain ?: @"-",(long)error.code,
               response.URL.absoluteString ?: @"-");
        if (!error && data.length) SBDLogJSONSummary(serial,kind,data);
        if (completion) completion(data,response,error);
    };
    NSURLSessionDataTask *task=[self sbd_dataTaskWithRequest:request completionHandler:wrapped];
    SBDLog(@"NET[%llu] TASK id=%lu class=%@ state=%ld",
           serial,(unsigned long)task.taskIdentifier,SBDClass(task),(long)task.state);
    SBDPollTask(task,serial,0.25);
    SBDPollTask(task,serial,1.0);
    SBDPollTask(task,serial,3.0);
    SBDPollTask(task,serial,10.0);
    return task;
}
@end

static UICollectionView *SBDFindCollection(UIView *view) {
    if ([view isKindOfClass:UICollectionView.class]) return (UICollectionView *)view;
    for (UIView *sub in view.subviews) {
        UICollectionView *found=SBDFindCollection(sub);
        if (found) return found;
    }
    return nil;
}

static UIViewController *SBDFindHistoryControllerIn(UIViewController *vc) {
    if (!vc) return nil;
    if ([NSStringFromClass(vc.class) containsString:@"HistoryViewController"]) return vc;
    if (vc.presentedViewController) {
        UIViewController *found=SBDFindHistoryControllerIn(vc.presentedViewController);
        if (found) return found;
    }
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *found=SBDFindHistoryControllerIn(child);
        if (found) return found;
    }
    if ([vc isKindOfClass:UINavigationController.class]) {
        UIViewController *found=SBDFindHistoryControllerIn(((UINavigationController *)vc).visibleViewController);
        if (found) return found;
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        UIViewController *found=SBDFindHistoryControllerIn(((UITabBarController *)vc).selectedViewController);
        if (found) return found;
    }
    return nil;
}

static UIViewController *SBDFindHistoryController(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        UIViewController *found=SBDFindHistoryControllerIn(window.rootViewController);
        if (found) return found;
    }
    Class cls=objc_getClass("_TtC14ChatGPTHistory21HistoryViewController");
    if (cls) {
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            NSMutableArray *stack=[NSMutableArray array];
            if (window.rootViewController) [stack addObject:window.rootViewController];
            while (stack.count) {
                UIViewController *vc=stack.lastObject;
                [stack removeLastObject];
                if ([vc isKindOfClass:cls]) return vc;
                [stack addObjectsFromArray:vc.childViewControllers];
                if (vc.presentedViewController) [stack addObject:vc.presentedViewController];
            }
        }
    }
    return nil;
}

static BOOL SBDDescendsFrom(UIView *view, UIView *ancestor) {
    for (UIView *cursor=view;cursor;cursor=cursor.superview)
        if (cursor==ancestor) return YES;
    return NO;
}

static BOOL SBDHistoryListTopmost(UIViewController *history, NSString **detail) {
    UICollectionView *list=history?SBDFindCollection(history.view):nil;
    UIWindow *window=list.window ?: history.view.window;
    if (!history || !list || !window || list.hidden || list.alpha<0.01) {
        if (detail) *detail=[NSString stringWithFormat:@"history=%@ list=%@ window=%@ hidden=%d alpha=%.2f",
                             SBDClass(history),SBDClass(list),SBDClass(window),list.hidden,list.alpha];
        return NO;
    }

    CGRect rect=[list convertRect:list.bounds toView:window];
    CGRect visible=CGRectIntersection(rect,window.bounds);
    if (CGRectIsNull(visible) || CGRectIsEmpty(visible) ||
        visible.size.width<60 || visible.size.height<100) {
        if (detail) *detail=[NSString stringWithFormat:@"rect=%@ visible=%@",
                             NSStringFromCGRect(rect),NSStringFromCGRect(visible)];
        return NO;
    }

    const CGFloat fractions[]={0.20,0.50,0.80};
    NSMutableArray *hits=[NSMutableArray array];
    BOOL topmost=NO;
    for (NSUInteger i=0;i<3;i++) {
        CGPoint point=CGPointMake(CGRectGetMidX(visible),
                                  CGRectGetMinY(visible)+visible.size.height*fractions[i]);
        UIView *hit=[window hitTest:point withEvent:nil];
        [hits addObject:SBDClass(hit)];
        if (SBDDescendsFrom(hit,list)) topmost=YES;
    }
    if (detail) *detail=[NSString stringWithFormat:
        @"historyViewWindow=%d historyHidden=%d historyAlpha=%.2f listFrame=%@ visible=%@ listHidden=%d listAlpha=%.2f hits=%@",
        history.view.window!=nil,history.view.hidden,history.view.alpha,
        NSStringFromCGRect(rect),NSStringFromCGRect(visible),list.hidden,list.alpha,
        [hits componentsJoinedByString:@","]];
    return topmost;
}

static void SBDLogControllerTree(UIViewController *vc, NSUInteger depth) {
    if (!vc || depth>8) return;
    NSMutableString *indent=[NSMutableString string];
    for (NSUInteger i=0;i<depth;i++) [indent appendString:@"  "];
    UIView *v=vc.isViewLoaded?vc.view:nil;
    SBDLog(@"UI VC %@%@ window=%d hidden=%d alpha=%.2f frame=%@ children=%lu presented=%@",
           indent,SBDClass(vc),v.window!=nil,v.hidden,v.alpha,
           v?NSStringFromCGRect(v.frame):@"-",(unsigned long)vc.childViewControllers.count,
           SBDClass(vc.presentedViewController));
    for (UIViewController *child in vc.childViewControllers)
        SBDLogControllerTree(child,depth+1);
    if (vc.presentedViewController)
        SBDLogControllerTree(vc.presentedViewController,depth+1);
}

static void SBDLogScrollViews(UIView *view, UIWindow *window, NSUInteger *count) {
    if (!view || *count>=40) return;
    if ([view isKindOfClass:UIScrollView.class] && view.window) {
        (*count)++;
        UIScrollView *scroll=(UIScrollView *)view;
        CGRect frame=[view convertRect:view.bounds toView:window];
        NSInteger visibleCells=-1,sections=-1;
        if ([scroll isKindOfClass:UICollectionView.class]) {
            UICollectionView *cv=(UICollectionView *)scroll;
            visibleCells=(NSInteger)cv.visibleCells.count;
            sections=cv.numberOfSections;
        } else if ([scroll isKindOfClass:UITableView.class]) {
            UITableView *tv=(UITableView *)scroll;
            visibleCells=(NSInteger)tv.visibleCells.count;
            sections=tv.numberOfSections;
        }
        SBDLog(@"UI SCROLL class=%@ frame=%@ hidden=%d alpha=%.2f content=%@ offset=%@ subviews=%lu visibleCells=%ld sections=%ld",
               SBDClass(scroll),NSStringFromCGRect(frame),scroll.hidden,scroll.alpha,
               NSStringFromCGSize(scroll.contentSize),NSStringFromCGPoint(scroll.contentOffset),
               (unsigned long)scroll.subviews.count,(long)visibleCells,(long)sections);
    }
    for (UIView *sub in view.subviews)
        SBDLogScrollViews(sub,window,count);
}

static void SBDSnapshot(NSString *reason) {
    SBDLog(@"=== SNAPSHOT %@ resident=%.1fMB lastDetail=%@ lastDetailReq=%llu ===",
           reason,SBDResidentMB(),sLastDetailID ?: @"-",sLastDetailRequestSerial);
    NSUInteger windowIndex=0;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        SBDLog(@"UI WINDOW #%lu class=%@ key=%d hidden=%d alpha=%.2f frame=%@ root=%@",
               (unsigned long)windowIndex++,SBDClass(window),window.isKeyWindow,
               window.hidden,window.alpha,NSStringFromCGRect(window.frame),
               SBDClass(window.rootViewController));
        SBDLogControllerTree(window.rootViewController,0);
        NSUInteger count=0;
        SBDLogScrollViews(window,window,&count);
    }
    SBDLog(@"=== END SNAPSHOT %@ ===",reason);
}

static void SBDScheduleSnapshots(NSString *base) {
    NSArray<NSNumber *> *delays=@[@0.20,@0.60,@1.20,@2.50];
    for (NSNumber *n in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(n.doubleValue*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            SBDSnapshot([NSString stringWithFormat:@"%@ +%.2fs",base,n.doubleValue]);
        });
    }
}

static void SBDUITick(void) {
    UIViewController *history=SBDFindHistoryController();
    NSString *detail=nil;
    BOOL visible=SBDHistoryListTopmost(history,&detail);
    if (!sSidebarKnown) {
        sSidebarKnown=YES;
        sSidebarVisible=visible;
        SBDLog(@"UI SIDEBAR initial visible=%d %@",visible,detail ?: @"-");
        return;
    }
    if (visible==sSidebarVisible) return;
    sSidebarVisible=visible;
    SBDLog(@"UI SIDEBAR TRANSITION visible=%d resident=%.1fMB lastDetail=%@ reqSerial=%llu %@",
           visible,SBDResidentMB(),sLastDetailID ?: @"-",sLastDetailRequestSerial,
           detail ?: @"-");
    NSString *reason=visible?@"SIDEBAR_OPEN":@"SIDEBAR_CLOSE";
    SBDSnapshot(reason);
    SBDScheduleSnapshots(reason);
}

static void SBDHistoryWillAppear(id self, SEL cmd, BOOL animated) {
    SBDLog(@"LIFE History viewWillAppear:%d class=%@ window=%d",animated,SBDClass(self),
           [self isViewLoaded] && [self view].window!=nil);
    if (sOrigWillAppear) ((void(*)(id,SEL,BOOL))sOrigWillAppear)(self,cmd,animated);
}
static void SBDHistoryDidAppear(id self, SEL cmd, BOOL animated) {
    if (sOrigDidAppear) ((void(*)(id,SEL,BOOL))sOrigDidAppear)(self,cmd,animated);
    SBDLog(@"LIFE History viewDidAppear:%d class=%@ window=%d",animated,SBDClass(self),
           [self isViewLoaded] && [self view].window!=nil);
}
static void SBDHistoryWillDisappear(id self, SEL cmd, BOOL animated) {
    SBDLog(@"LIFE History viewWillDisappear:%d class=%@ window=%d",animated,SBDClass(self),
           [self isViewLoaded] && [self view].window!=nil);
    if (sOrigWillDisappear) ((void(*)(id,SEL,BOOL))sOrigWillDisappear)(self,cmd,animated);
}
static void SBDHistoryDidDisappear(id self, SEL cmd, BOOL animated) {
    if (sOrigDidDisappear) ((void(*)(id,SEL,BOOL))sOrigDidDisappear)(self,cmd,animated);
    SBDLog(@"LIFE History viewDidDisappear:%d class=%@ window=%d",animated,SBDClass(self),
           [self isViewLoaded] && [self view].window!=nil);
}

static void SBDHookHistoryController(void) {
    if (sHistoryHooked) return;
    Class cls=objc_getClass("_TtC14ChatGPTHistory21HistoryViewController");
    if (!cls) return;
    struct Hook { SEL sel; IMP replacement; IMP *original; } hooks[]={
        {@selector(viewWillAppear:),(IMP)SBDHistoryWillAppear,&sOrigWillAppear},
        {@selector(viewDidAppear:),(IMP)SBDHistoryDidAppear,&sOrigDidAppear},
        {@selector(viewWillDisappear:),(IMP)SBDHistoryWillDisappear,&sOrigWillDisappear},
        {@selector(viewDidDisappear:),(IMP)SBDHistoryDidDisappear,&sOrigDidDisappear},
    };
    for (NSUInteger i=0;i<sizeof(hooks)/sizeof(hooks[0]);i++) {
        Method method=class_getInstanceMethod(cls,hooks[i].sel);
        if (!method) continue;
        *hooks[i].original=method_getImplementation(method);
        class_replaceMethod(cls,hooks[i].sel,hooks[i].replacement,method_getTypeEncoding(method));
    }
    sHistoryHooked=YES;
    SBDLog(@"HOOK HistoryViewController lifecycle installed class=%@",NSStringFromClass(cls));
}

static void SBDHookNetwork(void) {
    if (sNetworkHooked) return;
    Method a=class_getInstanceMethod(NSURLSession.class,@selector(dataTaskWithRequest:));
    Method b=class_getInstanceMethod(NSURLSession.class,@selector(sbd_dataTaskWithRequest:));
    Method c=class_getInstanceMethod(NSURLSession.class,@selector(dataTaskWithRequest:completionHandler:));
    Method d=class_getInstanceMethod(NSURLSession.class,@selector(sbd_dataTaskWithRequest:completionHandler:));
    if (a && b) method_exchangeImplementations(a,b);
    if (c && d) method_exchangeImplementations(c,d);
    sNetworkHooked=(a&&b&&c&&d);
    SBDLog(@"HOOK NSURLSession installed=%d",sNetworkHooked);
}

static void SBDLogLoadedImages(void) {
    for (uint32_t i=0;i<_dyld_image_count();i++) {
        const char *name=_dyld_get_image_name(i);
        if (!name) continue;
        if (strstr(name,"ChatGPTRepair") || strstr(name,"ChatGPTDownload") ||
            strstr(name,"ChatGPTLink") || strstr(name,"BlankDiag") ||
            strstr(name,"SidebarBlankDiag")) {
            SBDLog(@"IMAGE %s",name);
        }
    }
}

static void SBDStartUITimer(void) {
    if (sUITimer) return;
    sUITimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(sUITimer,
        dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.15*NSEC_PER_SEC)),
        (uint64_t)(0.15*NSEC_PER_SEC),(uint64_t)(0.03*NSEC_PER_SEC));
    dispatch_source_set_event_handler(sUITimer,^{
        SBDHookHistoryController();
        SBDUITick();
    });
    dispatch_resume(sUITimer);
}

__attribute__((constructor)) static void SBDInit(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
        sLogLock=[NSLock new];
        sLogPath=[SBDDocumentsPath() stringByAppendingPathComponent:@"ChatGPTSidebarBlankDiag.log"];
        [[NSFileManager defaultManager] removeItemAtPath:sLogPath error:nil];
        [[NSFileManager defaultManager] createFileAtPath:sLogPath contents:nil attributes:nil];
        sLogFile=fopen(sLogPath.fileSystemRepresentation,"a");

        NSDictionary *info=NSBundle.mainBundle.infoDictionary;
        SBDLog(@"=== ChatGPT Sidebar Blank Diagnostic v1.0 launch ===");
        SBDLog(@"bundle=%@ shortVersion=%@ build=%@ os=%@",
               NSBundle.mainBundle.bundleIdentifier ?: @"-",
               info[@"CFBundleShortVersionString"] ?: @"-",
               info[@"CFBundleVersion"] ?: @"-",
               UIDevice.currentDevice.systemVersion ?: @"-");
        SBDLog(@"logPath=%@",sLogPath);
        SBDLog(@"resident=%.1fMB",SBDResidentMB());
        SBDLogLoadedImages();

        NSNotificationCenter *nc=NSNotificationCenter.defaultCenter;
        [nc addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil
                         queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            SBDLog(@"APP MEMORY_WARNING resident=%.1fMB",SBDResidentMB());
            SBDSnapshot(@"MEMORY_WARNING");
        }];
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                         queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            SBDLog(@"APP didBecomeActive resident=%.1fMB",SBDResidentMB());
        }];
        [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil
                         queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            SBDLog(@"APP willResignActive");
        }];
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
                         queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            SBDLog(@"APP didEnterBackground");
        }];
        [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil
                         queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            SBDLog(@"APP willEnterForeground");
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            SBDHookNetwork();
            SBDHookHistoryController();
            SBDStartUITimer();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                SBDHookHistoryController();
                SBDLogLoadedImages();
                SBDSnapshot(@"LAUNCH_READY");
            });
        });
    }
}
