#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *TraceLogPath(void) {
    NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ChatGPTSidebarTrace.log"];
}

static NSObject *TraceLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock=[NSObject new]; });
    return lock;
}

static void TraceWrite(NSString *message) {
    if (!message.length) return;
    @synchronized(TraceLock()) {
        static NSDateFormatter *fmt;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            fmt=[NSDateFormatter new];
            fmt.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            fmt.dateFormat=@"yyyy-MM-dd HH:mm:ss.SSS";
        });
        NSString *line=[NSString stringWithFormat:@"%@ %@\n",[fmt stringFromDate:NSDate.date],message];
        NSData *data=[line dataUsingEncoding:NSUTF8StringEncoding];
        NSString *path=TraceLogPath();
        if (![[NSFileManager defaultManager] fileExistsAtPath:path])
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:path];
        [h seekToEndOfFile];
        [h writeData:data];
        [h closeFile];
    }
}

static void TraceStack(NSString *tag) {
    NSArray<NSString *> *stack=[NSThread callStackSymbols];
    NSUInteger count=MIN((NSUInteger)45,stack.count);
    NSMutableString *out=[NSMutableString stringWithFormat:@"STACK %@ frames=%lu",tag,(unsigned long)count];
    for (NSUInteger i=0;i<count;i++)
        [out appendFormat:@"\n  #%02lu %@",(unsigned long)i,stack[i]];
    TraceWrite(out);
}

static BOOL TraceIsHistory(NSURLRequest *request) {
    NSString *path=request.URL.path ?: @"";
    if (![path isEqualToString:@"/backend-api/conversations"]) return NO;
    NSURLComponents *parts=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in parts.queryItems) {
        if ([item.name isEqualToString:@"offset"] && item.value.length)
            return item.value.integerValue==0;
    }
    return YES;
}

static BOOL TraceIsMessagesCollection(UICollectionView *view) {
    NSString *name=NSStringFromClass(view.class);
    return [name containsString:@"BottomAlignedCollectionViewController"] &&
           [name containsString:@"ChatGPTMessages"];
}

static char kTraceHadItems;
static char kTraceLastZeroAt;

static NSMutableDictionary<NSString *,NSValue *> *TraceDataSourceIMPs(void) {
    static NSMutableDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ map=[NSMutableDictionary dictionary]; });
    return map;
}
static NSMutableSet<NSString *> *TraceHookedDataSources(void) {
    static NSMutableSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set=[NSMutableSet set]; });
    return set;
}

static NSInteger TraceNumberOfItems(id self, SEL command, UICollectionView *collection, NSInteger section) {
    NSString *key=NSStringFromClass([self class]);
    NSValue *value=nil;
    @synchronized(TraceLock()) { value=TraceDataSourceIMPs()[key]; }
    IMP imp=value.pointerValue;
    NSInteger result=imp ? ((NSInteger(*)(id,SEL,UICollectionView *,NSInteger))imp)(self,command,collection,section) : 0;

    if (section==0 && TraceIsMessagesCollection(collection)) {
        if (result>0) {
            objc_setAssociatedObject(collection,&kTraceHadItems,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if ([objc_getAssociatedObject(collection,&kTraceHadItems) boolValue]) {
            NSTimeInterval now=NSDate.date.timeIntervalSince1970;
            NSNumber *last=objc_getAssociatedObject(collection,&kTraceLastZeroAt);
            if (!last || now-last.doubleValue>0.75) {
                objc_setAssociatedObject(collection,&kTraceLastZeroAt,@(now),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                TraceWrite([NSString stringWithFormat:
                    @"MESSAGES DATASOURCE returned ZERO after previously nonzero dataSource=%@ collection=%@ contentHeight=%.1f visible=%lu",
                    key,NSStringFromClass(collection.class),collection.contentSize.height,
                    (unsigned long)collection.visibleCells.count]);
                TraceStack(@"MESSAGES numberOfItems -> 0");
            }
        }
    }
    return result;
}

static void TraceInstallDataSourceHook(id dataSource) {
    if (!dataSource) return;
    Class cls=[dataSource class];
    NSString *key=NSStringFromClass(cls);
    SEL sel=@selector(collectionView:numberOfItemsInSection:);
    Method method=class_getInstanceMethod(cls,sel);
    if (!method) return;

    @synchronized(TraceLock()) {
        if ([TraceHookedDataSources() containsObject:key]) return;
        IMP original=method_getImplementation(method);
        const char *types=method_getTypeEncoding(method);
        TraceDataSourceIMPs()[key]=[NSValue valueWithPointer:original];
        BOOL added=class_addMethod(cls,sel,(IMP)TraceNumberOfItems,types);
        if (!added) class_replaceMethod(cls,sel,(IMP)TraceNumberOfItems,types);
        [TraceHookedDataSources() addObject:key];
    }
    TraceWrite([NSString stringWithFormat:@"HOOK dataSource class=%@ selector=collectionView:numberOfItemsInSection:",key]);
}

static void TraceInspectExistingCollections(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ TraceInspectExistingCollections(); });
        return;
    }
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:window];
        while (queue.count) {
            UIView *view=queue.lastObject; [queue removeLastObject];
            if ([view isKindOfClass:UICollectionView.class]) {
                UICollectionView *cv=(UICollectionView *)view;
                if (TraceIsMessagesCollection(cv)) {
                    TraceInstallDataSourceHook(cv.dataSource);
                    TraceWrite([NSString stringWithFormat:
                        @"FOUND messages collection=%@ dataSource=%@ contentHeight=%.1f visible=%lu",
                        NSStringFromClass(cv.class),NSStringFromClass([cv.dataSource class]),
                        cv.contentSize.height,(unsigned long)cv.visibleCells.count]);
                }
            }
            [queue addObjectsFromArray:view.subviews];
        }
    }
}

static void TraceDumpMethods(Class cls) {
    if (!cls) return;
    unsigned int count=0;
    Method *methods=class_copyMethodList(cls,&count);
    NSMutableArray<NSString *> *names=[NSMutableArray arrayWithCapacity:count];
    for (unsigned int i=0;i<count;i++)
        [names addObject:NSStringFromSelector(method_getName(methods[i]))];
    free(methods);
    [names sortUsingSelector:@selector(compare:)];
    TraceWrite([NSString stringWithFormat:@"METHODS class=%@ count=%u\n  %@",
        NSStringFromClass(cls),count,[names componentsJoinedByString:@"\n  "]]);
}

@implementation NSURLSession (ChatGPTSidebarTrace)
- (NSURLSessionDataTask *)cgs_trace_dataTaskWithRequest:(NSURLRequest *)request
                                      completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))completion {
    if (TraceIsHistory(request)) {
        TraceWrite([NSString stringWithFormat:@"HISTORY CREATE %@",request.URL.absoluteString ?: @"-"]);
        TraceStack(@"HISTORY request creation");
    }
    return [self cgs_trace_dataTaskWithRequest:request completionHandler:completion];
}
@end

@implementation UICollectionView (ChatGPTSidebarTrace)
- (void)cgs_trace_reloadData {
    BOOL target=TraceIsMessagesCollection(self);
    CGFloat before=self.contentSize.height;
    NSUInteger visible=self.visibleCells.count;
    NSArray *stack=target?[NSThread callStackSymbols]:nil;
    [self cgs_trace_reloadData];
    if (target) {
        TraceWrite([NSString stringWithFormat:@"MESSAGES reloadData beforeHeight=%.1f beforeVisible=%lu afterHeight=%.1f afterVisible=%lu",
            before,(unsigned long)visible,self.contentSize.height,(unsigned long)self.visibleCells.count]);
        if (before>1.0) {
            NSMutableString *out=[NSMutableString stringWithString:@"STACK MESSAGES reloadData"];
            NSUInteger count=MIN((NSUInteger)45,stack.count);
            for (NSUInteger i=0;i<count;i++) [out appendFormat:@"\n  #%02lu %@",(unsigned long)i,stack[i]];
            TraceWrite(out);
        }
    }
}
- (void)cgs_trace_setDataSource:(id<UICollectionViewDataSource>)dataSource {
    [self cgs_trace_setDataSource:dataSource];
    if (TraceIsMessagesCollection(self)) {
        TraceWrite([NSString stringWithFormat:@"MESSAGES setDataSource=%@",NSStringFromClass([(id)dataSource class])]);
        TraceInstallDataSourceHook(dataSource);
        TraceStack(@"MESSAGES setDataSource");
    }
}
- (void)cgs_trace_performBatchUpdates:(void (^)(void))updates completion:(void (^)(BOOL))completion {
    BOOL target=TraceIsMessagesCollection(self);
    CGFloat before=self.contentSize.height;
    NSArray *stack=target?[NSThread callStackSymbols]:nil;
    [self cgs_trace_performBatchUpdates:updates completion:^(BOOL finished) {
        if (target) {
            TraceWrite([NSString stringWithFormat:@"MESSAGES batchUpdates finished=%d beforeHeight=%.1f afterHeight=%.1f visible=%lu",
                finished,before,self.contentSize.height,(unsigned long)self.visibleCells.count]);
            if (before>1.0 && self.contentSize.height<=1.0) {
                NSMutableString *out=[NSMutableString stringWithString:@"STACK MESSAGES batch -> zero"];
                NSUInteger count=MIN((NSUInteger)45,stack.count);
                for (NSUInteger i=0;i<count;i++) [out appendFormat:@"\n  #%02lu %@",(unsigned long)i,stack[i]];
                TraceWrite(out);
            }
        }
        if (completion) completion(finished);
    }];
}
@end

static void TraceSwizzle(Class cls, SEL a, SEL b) {
    Method ma=class_getInstanceMethod(cls,a), mb=class_getInstanceMethod(cls,b);
    if (ma && mb) method_exchangeImplementations(ma,mb);
}

__attribute__((constructor)) static void TraceBoot(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
        TraceWrite(@"=== ChatGPT Sidebar Mutation Trace v1.0.0 launch ===");
        TraceWrite([NSString stringWithFormat:@"app=%@ build=%@ os=%@",
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"-",
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"-",
            UIDevice.currentDevice.systemVersion]);

        TraceSwizzle(NSURLSession.class,
            @selector(dataTaskWithRequest:completionHandler:),
            @selector(cgs_trace_dataTaskWithRequest:completionHandler:));
        TraceSwizzle(UICollectionView.class,@selector(reloadData),@selector(cgs_trace_reloadData));
        TraceSwizzle(UICollectionView.class,@selector(setDataSource:),@selector(cgs_trace_setDataSource:));
        TraceSwizzle(UICollectionView.class,@selector(performBatchUpdates:completion:),
            @selector(cgs_trace_performBatchUpdates:completion:));

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                TraceDumpMethods(objc_getClass("_TtC14ChatGPTHistory21HistoryViewController"));
                TraceDumpMethods(objc_getClass("_TtC15ChatGPTMessages22MessagesViewController"));
                TraceInspectExistingCollections();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ TraceInspectExistingCollections(); });
            }];
    }
}
