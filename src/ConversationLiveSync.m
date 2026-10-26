// ChatGPTRepair: safe foreground change detection for the existing conversation.
// Never navigates, never creates a chat, and never overlays reply text.
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
static NSString *sConversationID;
static NSURLRequest *sConversationRequest;
static NSURLSessionConfiguration *sConfiguration;
static NSUInteger sGeneration;
static BOOL sPollActive;
static BOOL sDelivered;
static BOOL sHasDeliveredHash;
static NSUInteger sDeliveredHash;
static BOOL sBusy;
static NSTimeInterval sLastRefreshAttempt;
static UIView *sIndicator;
static UIActivityIndicatorView *sSpinner;
static UILabel *sIndicatorLabel;

static void CGSyncLog(NSString *event, NSInteger status, NSUInteger count) {
    @try {
        @synchronized([NSFileManager class]) {
            NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:
                @"Documents/ChatGPTRepairLiveSync.log"];
            NSFileManager *fm=[NSFileManager defaultManager];
            NSDictionary *attributes=[fm attributesOfItemAtPath:path error:nil];
            if ([attributes[NSFileSize] unsignedLongLongValue]>262144)
                [fm removeItemAtPath:path error:nil];
            if (![fm fileExistsAtPath:path])
                [fm createFileAtPath:path contents:[NSData data] attributes:nil];
            NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
            if (handle) {
                [handle seekToEndOfFile];
                NSString *line=[NSString stringWithFormat:
                    @"%@ event=%@ status=%ld value=%lu\n",
                    NSDate.date,event,(long)status,(unsigned long)count];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [handle closeFile];
            }
        }
    } @catch (__unused NSException *exception) {}
}

static BOOL CGSyncForeground(void) {
    return UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
}

static void CGSyncStatus(NSString *state, BOOL visible) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window=UIApplication.sharedApplication.keyWindow;
        if (!window) window=UIApplication.sharedApplication.windows.firstObject;
        if (!visible || !window || !CGSyncForeground()) {
            sIndicator.hidden=YES;
            [sSpinner stopAnimating];
            return;
        }
        if (!sIndicator || sIndicator.superview!=window) {
            [sIndicator removeFromSuperview];
            UIView *panel=[[UIView alloc] initWithFrame:CGRectMake(0,0,124,30)];
            panel.backgroundColor=[UIColor colorWithWhite:0.22 alpha:0.82];
            panel.userInteractionEnabled=NO;
            panel.layer.cornerRadius=15;
            UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            spinner.frame=CGRectMake(7,5,20,20);
            spinner.color=UIColor.whiteColor;
            [panel addSubview:spinner];
            UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(31,0,88,30)];
            label.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
            label.textColor=UIColor.whiteColor;
            label.adjustsFontSizeToFitWidth=YES;
            [panel addSubview:label];
            [window addSubview:panel];
            sIndicator=panel;
            sSpinner=spinner;
            sIndicatorLabel=label;
        }
        CGFloat safe=window.safeAreaInsets.top;
        CGFloat width=CGRectGetWidth(sIndicator.bounds);
        CGFloat centerX=(CGRectGetWidth(window.bounds)-width)*0.5;
        sIndicator.frame=CGRectMake(centerX,safe+56,width,30);
        sIndicatorLabel.text=state ?: @"Checking";
        sIndicator.hidden=NO;
        if ([state isEqualToString:@"Checking"])
            [sSpinner startAnimating];
        else
            [sSpinner stopAnimating];
    });
}

static BOOL CGSyncBusyValue(id raw) {
    if ([raw isKindOfClass:NSString.class]) {
        NSString *value=[(NSString *)raw lowercaseString];
        return [@[@"running",@"processing",@"pending",@"in_progress",
                 @"streaming",@"queued",@"generating",@"active"] containsObject:value];
    }
    if ([raw isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict=raw;
        return CGSyncBusyValue(dict[@"status"]) ||
               CGSyncBusyValue(dict[@"state"]) ||
               CGSyncBusyValue(dict[@"phase"]);
    }
    return NO;
}

static NSUInteger CGSyncSnapshotHash(NSDictionary *root, BOOL *busy) {
    NSArray *messages=CGConversationPagingMessages(root);
    NSDictionary *last=[messages.lastObject isKindOfClass:NSDictionary.class]
        ?messages.lastObject:nil;
    NSDictionary *message=[last[@"message"] isKindOfClass:NSDictionary.class]
        ?last[@"message"]:last;
    BOOL generating=CGSyncBusyValue(root[@"async_status"]) ||
        CGSyncBusyValue(root[@"status"]) || CGSyncBusyValue(message[@"status"]) ||
        CGSyncBusyValue(message[@"metadata"]);
    if ([root[@"is_generating"] respondsToSelector:@selector(boolValue)])
        generating=generating || [root[@"is_generating"] boolValue];
    if (busy) *busy=generating;
    NSArray *elements=@[
        [root[@"current_node"] isKindOfClass:NSString.class]
            ?root[@"current_node"]:@"-",
        root[@"async_status"] ?: [NSNull null],
        messages ?: @[]
    ];
    NSData *data=[NSJSONSerialization dataWithJSONObject:elements
        options:NSJSONWritingSortedKeys error:NULL];
    return data ? data.hash : 0;
}

// Only attempt a parameterless Objective-C refresh on a visible chat.
// Never invoke an unknown Swift ABI method or any navigation/reselection.
static BOOL CGSyncTryRefreshObject(id object) {
    if (!object) return NO;
    for (NSString *name in @[@"refreshConversation",@"reloadConversation"]) {
        SEL selector=NSSelectorFromString(name);
        if (![object respondsToSelector:selector]) continue;
        Method method=class_getInstanceMethod([object class],selector);
        if (!method || method_getNumberOfArguments(method)!=2) continue;
        char type[8]={0};
        method_getReturnType(method,type,sizeof(type));
        if (type[0]!='v') continue;
        @try {
            ((void(*)(id,SEL))objc_msgSend)(object,selector);
            CGSyncLog(@"IN_PLACE_REFRESH_DISPATCHED",0,0);
            return YES;
        } @catch (__unused NSException *exception) {
            CGSyncLog(@"IN_PLACE_REFRESH_EXCEPTION",0,0);
        }
    }
    return NO;
}

static BOOL CGSyncTryVisibleController(UIViewController *vc, NSMutableSet *seen) {
    if (!vc || [seen containsObject:vc]) return NO;
    [seen addObject:vc];
    BOOL visible=vc.isViewLoaded && vc.view.window!=nil;
    NSString *kind=NSStringFromClass(vc.class);
    BOOL candidate=([kind localizedCaseInsensitiveContainsString:@"Conversation"] ||
        [kind localizedCaseInsensitiveContainsString:@"Chat"] ||
        [kind localizedCaseInsensitiveContainsString:@"Message"]) &&
        ![kind localizedCaseInsensitiveContainsString:@"History"];
    if (visible && candidate) {
        if (CGSyncTryRefreshObject(vc)) return YES;
        for (NSString *key in @[@"viewModel",@"conversationViewModel"]) {
            @try {
                id model=[vc valueForKey:key];
                if (CGSyncTryRefreshObject(model)) return YES;
            } @catch (__unused NSException *exception) {}
        }
    }
    for (UIViewController *child in vc.childViewControllers)
        if (CGSyncTryVisibleController(child,seen)) return YES;
    if (vc.presentedViewController &&
        CGSyncTryVisibleController(vc.presentedViewController,seen))
        return YES;
    return NO;
}

static void CGSyncRefreshInPlace(NSUInteger generation) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!CGSyncForeground()) return;
        @synchronized(CGSyncLock()) {
            if (generation!=sGeneration) return;
        }
        BOOL invoked=NO;
        NSMutableSet *seen=[NSMutableSet set];
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (CGSyncTryVisibleController(window.rootViewController,seen)) {
                invoked=YES;
                break;
            }
        }
        if (!invoked) CGSyncLog(@"IN_PLACE_REFRESH_UNAVAILABLE",0,0);
    });
}

static void CGSyncPoll(NSUInteger generation);
static void CGSyncSchedule(NSUInteger generation, NSTimeInterval seconds) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        CGSyncPoll(generation);
    });
}

static void CGSyncPoll(NSUInteger generation) {
    NSURLRequest *request=nil;
    NSURLSessionConfiguration *configuration=nil;
    @synchronized(CGSyncLock()) {
        if (generation!=sGeneration || !sConversationID || sPollActive)
            return;
        if (!CGSyncForeground()) return;
        sPollActive=YES;
        request=[sConversationRequest copy];
        configuration=[sConfiguration copy];
    }
    if (!request) return;
    CGSyncStatus(@"Checking",YES);
    NSURLRequest *modern=CGPagingModernRequest(request,nil);
    NSURLSessionConfiguration *config=configuration ?:
        [NSURLSessionConfiguration defaultSessionConfiguration];
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
        NSUInteger hash=root?CGSyncSnapshotHash(root,&busy):0;
        BOOL changed=NO,tryRefresh=NO;
        @synchronized(CGSyncLock()) {
            if (generation!=sGeneration) return;
            sPollActive=NO;
            if (root) {
                sBusy=busy;
                changed=sDelivered && sHasDeliveredHash &&
                    sDeliveredHash!=hash;
                if (changed) {
                    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
                    if (now-sLastRefreshAttempt>30) {
                        tryRefresh=YES;
                        sLastRefreshAttempt=now;
                    }
                }
            }
        }
        CGSyncLog(root?@"POLL_OK":@"POLL_FAILED",status,
                  root?CGConversationPagingMessages(root).count:0);
        if (changed) {
            // This detects server changes; it does not claim the screen updated.
            CGSyncLog(@"REMOTE_CHANGE_DETECTED",status,busy?1:0);
            CGSyncStatus(@"New replies",YES);
            if (tryRefresh) CGSyncRefreshInPlace(generation);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                CGSyncStatus(@"New replies",NO);
            });
        } else {
            CGSyncStatus(@"Checking",busy);
        }
        CGSyncSchedule(generation,busy?8:15);
    }];
    if (task) [task resume];
    else {
        [session invalidateAndCancel]; session=nil;
        @synchronized(CGSyncLock()) {
            if (generation==sGeneration) sPollActive=NO;
        }
        CGSyncStatus(@"Checking",NO);
        CGSyncSchedule(generation,15);
    }
}

void CGChatSyncTrackDetail(NSURLRequest *request, NSURLSessionConfiguration *config) {
    NSString *cid=CGPagingConversationID(request);
    if (!cid.length || !request) return;
    @synchronized(CGSyncLock()) {
        if ([sConversationID isEqualToString:cid] && sConversationRequest)
            return;
        sConversationID=[cid copy];
        sConversationRequest=[request copy];
        sConfiguration=[config copy];
        sGeneration++;
        sPollActive=NO;
        sDelivered=NO;
        sHasDeliveredHash=NO;
        sBusy=NO;
        sLastRefreshAttempt=0;
    }
    CGSyncLog(@"TRACK_CONVERSATION",0,0);
}
void CGChatSyncMarkDelivered(NSURLRequest *request, NSDictionary *root) {
    NSString *cid=CGPagingConversationID(request);
    if (!cid.length) return;
    BOOL busy=NO;
    NSUInteger hash=CGSyncSnapshotHash(root,&busy);
    NSUInteger token=0;
    @synchronized(CGSyncLock()) {
        if (![sConversationID isEqualToString:cid]) return;
        BOOL first=!sDelivered;
        sDelivered=YES;
        sBusy=busy;
        sDeliveredHash=hash;
        sHasDeliveredHash=YES;
        if (first) token=sGeneration;
    }
    CGSyncLog(@"CONVERSATION_DELIVERED",0,busy?1:0);
    if (token) CGSyncSchedule(token,5);
}

__attribute__((constructor)) static void CGSyncInstall(void) {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"])
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) {
                NSUInteger generation=0;
                @synchronized(CGSyncLock()) {
                    if (sDelivered) generation=sGeneration;
                }
                if (generation) CGSyncSchedule(generation,1);
                CGSyncStatus(@"Checking",NO);
            }];
    });
}
