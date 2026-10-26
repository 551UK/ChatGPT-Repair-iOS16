// ChatGPTRepair: Recover updates generated on another device without changing chat data.
// Uses a small authenticated GET, not a second submission or a stream restart.
#import "ConversationLiveSync.h"
#import "ConversationPagingState.h"
#import "ConversationPagingCore.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface NSURLSession (CGSyncOriginal)
- (NSURLSessionDataTask *)cgp_dataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

static NSObject *CGSyncLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock=[NSObject new]; });
    return lock;
}
static NSString *sSyncID;
static NSString *sSyncTitle;
static NSURLRequest *sSyncRequest;
static NSURLSessionConfiguration *sSyncConfiguration;
static NSUInteger sSyncGeneration;
static NSUInteger sSyncPolls;
static UIView *sSyncOverlay;
static UIActivityIndicatorView *sSyncSpinner;
static UILabel *sSyncLabel;
static NSUInteger sSyncSignature;
static BOOL sSyncHasSignature;
static BOOL sSyncDelivered;
static BOOL sSyncRequestActive;
static BOOL sSyncBusy;
static NSTimeInterval sSyncLastUIRefresh;

static void CGSyncLog(NSString *event, NSInteger status, NSUInteger count) {
    @try {
        @synchronized([NSFileManager class]) {
            NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:
                @"Documents/ChatGPTRepairLiveSync.log"];
            NSFileManager *fm=[NSFileManager defaultManager];
            NSDictionary *attrs=[fm attributesOfItemAtPath:path error:NULL];
            if ([attrs[NSFileSize] unsignedLongLongValue]>262144)
                [fm removeItemAtPath:path error:NULL];
            if (![fm fileExistsAtPath:path])
                [fm createFileAtPath:path contents:[NSData data] attributes:nil];
            NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
            if (handle) {
                [handle seekToEndOfFile];
                NSString *line=[NSString stringWithFormat:
                    @"%@ event=%@ status=%ld value=%lu\n",
                    [NSDate date],event,(long)status,(unsigned long)count];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [handle closeFile];
            }
        }
    } @catch (__unused NSException *exception) {}
}

// Passive overlay sits below the chat navigation bar and never intercepts taps.
static void CGSyncIndicator(NSString *state, BOOL visible) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL show=visible &&
            UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
        UIWindow *window=UIApplication.sharedApplication.keyWindow;
        if (!window) window=UIApplication.sharedApplication.windows.firstObject;
        if (!show || !window) {
            sSyncOverlay.hidden=YES;
            [sSyncSpinner stopAnimating];
            return;
        }
        if (!sSyncOverlay || sSyncOverlay.superview!=window) {
            [sSyncOverlay removeFromSuperview];
            UIView *panel=[[UIView alloc] initWithFrame:CGRectMake(0,0,124,30)];
            panel.userInteractionEnabled=NO;
            panel.layer.cornerRadius=15;
            panel.backgroundColor=[UIColor colorWithWhite:0.22 alpha:0.82];
            UIActivityIndicatorView *indicator=[[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            indicator.frame=CGRectMake(7,5,20,20);
            indicator.color=UIColor.whiteColor;
            [panel addSubview:indicator];
            UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(31,0,88,30)];
            label.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
            label.textColor=UIColor.whiteColor;
            label.adjustsFontSizeToFitWidth=YES;
            [panel addSubview:label];
            [window addSubview:panel];
            sSyncOverlay=panel;
            sSyncSpinner=indicator;
            sSyncLabel=label;
        }
        CGFloat safe=window.safeAreaInsets.top;
        sSyncOverlay.frame=CGRectMake(window.bounds.size.width-140,safe+56,124,30);
        sSyncLabel.text=state ?: @"Syncing";
        sSyncOverlay.hidden=NO;
        [sSyncSpinner startAnimating];
    });
}

static UIViewController *CGSyncFindHistoryController(UIViewController *vc,
                                                    NSMutableSet *visited) {
    if (!vc || [visited containsObject:vc]) return nil;
    [visited addObject:vc];
    if ([NSStringFromClass(vc.class) containsString:@"HistoryViewController"])
        return vc;
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *hit=CGSyncFindHistoryController(child,visited);
        if (hit) return hit;
    }
    if (vc.presentedViewController) {
        UIViewController *hit=CGSyncFindHistoryController(vc.presentedViewController,visited);
        if (hit) return hit;
    }
    return nil;
}
extern BOOL CG46OpenPin(UIViewController *,NSString *,NSString *);
static BOOL CGSyncReopenCurrentConversation(NSString *identifier, NSString *title) {
    if (![[NSUUID alloc] initWithUUIDString:identifier]) return NO;
    NSMutableSet *visited=[NSMutableSet set];
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        UIViewController *history=CGSyncFindHistoryController(window.rootViewController,visited);
        if (!history) continue;
        @try {
            return CG46OpenPin(history,identifier,title.length?title:@"Chat");
        } @catch (__unused NSException *exception) {}
    }
    return NO;
}

static BOOL CGSyncStatusBusy(id raw) {
    if ([raw isKindOfClass:NSString.class]) {
        NSString *s=[(NSString *)raw lowercaseString];
        for (NSString *name in @[@"running",@"processing",@"pending",@"in_progress",
                                @"streaming",@"queued",@"generating",@"active"]) {
            if ([s isEqualToString:name]) return YES;
        }
    } else if ([raw isKindOfClass:NSDictionary.class]) {
        NSDictionary *d=raw;
        for (NSString *key in @[@"status",@"state",@"phase"]) {
            if (CGSyncStatusBusy(d[key])) return YES;
        }
    }
    return NO;
}

static NSUInteger CGSyncFingerprint(NSDictionary *root, BOOL *busyOut) {
    NSArray *messages=CGConversationPagingMessages(root);
    NSDictionary *last=[messages.lastObject isKindOfClass:NSDictionary.class]
        ?messages.lastObject:nil;
    NSDictionary *msg=[last[@"message"] isKindOfClass:NSDictionary.class]
        ?last[@"message"]:last;
    id async=root[@"async_status"];
    BOOL busy=CGSyncStatusBusy(async) || CGSyncStatusBusy(root[@"status"]) ||
        CGSyncStatusBusy(msg[@"status"]) || CGSyncStatusBusy(msg[@"metadata"]) ||
        ([root[@"is_generating"] respondsToSelector:@selector(boolValue)] &&
         [root[@"is_generating"] boolValue]);
    if (busyOut) *busyOut=busy;
    // Snapshot every message in the newest page, so edits and regenerations
    // of existing messages are detected, not just newly appended messages.
    NSArray *parts=@[
        [root[@"current_node"] isKindOfClass:NSString.class]?root[@"current_node"]:@"-",
        async ?: [NSNull null],
        messages ?: @[]
    ];
    NSData *encoded=[NSJSONSerialization dataWithJSONObject:parts
        options:NSJSONWritingSortedKeys error:NULL];
    return encoded ? encoded.hash : 0;
}

static BOOL CGSyncVisible(void) {
    UIApplication *app=UIApplication.sharedApplication;
    return app.applicationState==UIApplicationStateActive;
}

static BOOL CGSyncTryRefreshObject(id object) {
    if (!object) return NO;
    for (NSString *name in @[@"refreshConversation",@"reloadConversation"]) {
        SEL selector=NSSelectorFromString(name);
        if (![object respondsToSelector:selector]) continue;
        Method method=class_getInstanceMethod([object class],selector);
        if (!method || method_getNumberOfArguments(method)!=2) continue;
        char returnType[8]={0};
        method_getReturnType(method,returnType,sizeof(returnType));
        if (returnType[0]!='v') continue;
        @try {
            ((void(*)(id,SEL))objc_msgSend)(object,selector);
            return YES;
        } @catch (__unused NSException *exception) {}
    }
    return NO;
}

static BOOL CGSyncRefreshController(UIViewController *vc, NSMutableSet *seen) {
    if (!vc || [seen containsObject:vc]) return NO;
    [seen addObject:vc];
    // Skip sidebar/history and offscreen view controllers.
    if (!vc.isViewLoaded || !vc.view.window) return NO;
    NSString *type=NSStringFromClass(vc.class);
    BOOL candidate=([type localizedCaseInsensitiveContainsString:@"Conversation"] ||
        [type localizedCaseInsensitiveContainsString:@"Chat"] ||
        [type localizedCaseInsensitiveContainsString:@"Message"]) &&
        ![type localizedCaseInsensitiveContainsString:@"History"];
    if (candidate) {
        if (CGSyncTryRefreshObject(vc)) return YES;
        for (NSString *key in @[@"viewModel",@"conversationViewModel"]) {
            @try {
                id model=[vc valueForKey:key];
                if (CGSyncTryRefreshObject(model)) return YES;
            } @catch (__unused NSException *exception) {}
        }
    }
    for (UIViewController *child in vc.childViewControllers) {
        if (CGSyncRefreshController(child,seen)) return YES;
    }
    if (vc.presentedViewController &&
        CGSyncRefreshController(vc.presentedViewController,seen)) return YES;
    return NO;
}
static void CGSyncRequestUIRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!CGSyncVisible()) return;
        BOOL refreshed=NO;
        NSMutableSet *visited=[NSMutableSet set];
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (CGSyncRefreshController(window.rootViewController,visited)) {
                refreshed=YES; break;
            }
        }
        if (!refreshed) {
            NSString *cid=nil,*title=nil;
            @synchronized(CGSyncLock()) {
                cid=[sSyncID copy]; title=[sSyncTitle copy];
            }
            refreshed=CGSyncReopenCurrentConversation(cid,title);
            CGSyncLog(refreshed?@"NATIVE_RESELECT":@"NO_NATIVE_REFRESH",0,0);
        } else {
            CGSyncLog(@"NATIVE_REFRESH",0,0);
        }
    });
}

static void CGSyncPoll(NSUInteger generation);
static void CGSyncSchedule(NSUInteger generation, NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        CGSyncPoll(generation);
    });
}

static void CGSyncPoll(NSUInteger generation) {
    __block NSURLRequest *request=nil;
    __block NSURLSessionConfiguration *configuration=nil;
    @synchronized(CGSyncLock()) {
        if (generation!=sSyncGeneration || !sSyncID || sSyncRequestActive)
            return;
        if (!CGSyncVisible()) return; // Foreground notification restarts polling.
        // Stay subscribed while the app is foregrounded; no finite poll cap.
        sSyncRequestActive=YES;
        sSyncPolls++;
        request=[sSyncRequest copy];
        configuration=[sSyncConfiguration copy];
    }
    if (!request) return;
    CGSyncIndicator(@"Checking",YES);
    NSURLRequest *modern=CGPagingModernRequest(request,nil);
    NSURLSessionConfiguration *config=configuration ?: [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest=25;
    __block NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
    NSURLSessionDataTask *task=[session cgp_dataTaskWithRequest:modern
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [session finishTasksAndInvalidate]; session=nil;
        NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]
            ?((NSHTTPURLResponse *)response).statusCode:0;
        NSDictionary *root=(!error && status>=200 && status<300)
            ?CGConversationPagingJSONObject(data):nil;
        BOOL busy=NO;
        NSUInteger hash=root?CGSyncFingerprint(root,&busy):0;
        BOOL changed=NO, shouldRetry=NO;
        @synchronized(CGSyncLock()) {
            if (generation!=sSyncGeneration) return;
            sSyncRequestActive=NO;
            if (root) {
                if (sSyncHasSignature && sSyncSignature!=hash && sSyncDelivered)
                    changed=YES;
                sSyncSignature=hash;
                sSyncHasSignature=YES;
                sSyncBusy=busy;
            }
            shouldRetry=YES;
            if (changed) {
                NSTimeInterval now=NSDate.date.timeIntervalSince1970;
                if (now-sSyncLastUIRefresh<8) changed=NO;
                else sSyncLastUIRefresh=now;
            }
        }
        CGSyncLog(root?@"POLL_OK":@"POLL_FAILED",status,root?CGConversationPagingMessages(root).count:0);
        if (changed) {
            CGSyncLog(@"REMOTE_MESSAGE_CHANGED",status,busy?1:0);
            CGSyncIndicator(@"Updating",YES);
            CGSyncRequestUIRefresh();
        }
        if (changed) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3*NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                CGSyncIndicator(@"Updating",NO);
            });
        } else {
            CGSyncIndicator(@"Checking",busy);
        }
        if (shouldRetry) CGSyncSchedule(generation,busy?6:15);
    }];
    if (task) [task resume];
    else {
        [session invalidateAndCancel]; session=nil;
        @synchronized(CGSyncLock()) {
            if (generation==sSyncGeneration) sSyncRequestActive=NO;
        }
        CGSyncSchedule(generation,15);
    }
}

void CGChatSyncTrackDetail(NSURLRequest *request, NSURLSessionConfiguration *config) {
    NSString *cid=CGPagingConversationID(request);
    if (!cid.length || !request) return;
    NSUInteger generation=0;
    @synchronized(CGSyncLock()) {
        if ([sSyncID isEqualToString:cid] && sSyncRequest) return;
        sSyncID=[cid copy];
        sSyncTitle=nil;
        sSyncRequest=[request copy];
        sSyncConfiguration=[config copy];
        sSyncGeneration++;
        generation=sSyncGeneration;
        sSyncPolls=0;
        sSyncRequestActive=NO;
        sSyncHasSignature=NO;
        sSyncDelivered=NO;
        sSyncBusy=NO;
        sSyncLastUIRefresh=0;
    }
    CGSyncLog(@"TRACK_CONVERSATION",0,0);
    (void)generation; // The first conversation loads before background polling starts.
}
void CGChatSyncMarkDelivered(NSURLRequest *request, NSDictionary *root) {
    NSString *cid=CGPagingConversationID(request);
    if (!cid.length) return;
    BOOL busy=NO;
    NSUInteger signature=CGSyncFingerprint(root,&busy);
    NSUInteger token=0;
    @synchronized(CGSyncLock()) {
        if (![sSyncID isEqualToString:cid]) return;
        if ([root[@"title"] isKindOfClass:NSString.class])
            sSyncTitle=[root[@"title"] copy];
        if (!sSyncHasSignature) {
            sSyncSignature=signature;
            sSyncHasSignature=YES;
        }
        BOOL firstDelivery=!sSyncDelivered;
        sSyncDelivered=YES;
        if (busy) sSyncBusy=YES;
        if (firstDelivery) token=sSyncGeneration;
    }
    CGSyncLog(@"INITIAL_CONVERSATION_READY",0,busy?1:0);
    if (token) CGSyncSchedule(token,5);
}

__attribute__((constructor)) static void CGSyncBoot(void) {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                NSUInteger token=0;
                @synchronized(CGSyncLock()) {
                    if (!sSyncID.length) return;
                    sSyncPolls=0;  // Detect progress made while the app was elsewhere.
                    token=sSyncDelivered?sSyncGeneration:0;
                }
                if (token) CGSyncSchedule(token,1);
                CGSyncIndicator(@"Checking",NO);
            }];
    });
}
