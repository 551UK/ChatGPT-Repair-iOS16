// ChatGPTRepair: manual in-place conversation refresh.
// No background polling, timed refreshes, chat navigation, or floating preview.
#import "ConversationLiveSync.h"
#import "ConversationPagingState.h"
#import "NativeConversationRefresh.h"
#import <UIKit/UIKit.h>

static NSObject *CGManualLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock=[NSObject new]; });
    return lock;
}

static NSString *sSelectedConversation;
static BOOL sConversationLoaded;
static BOOL sHistoryVisible;
static BOOL sRefreshInProgress;
static NSUInteger sSelectionGeneration;
static UIButton *sRefreshButton;
static UIActivityIndicatorView *sRefreshSpinner;
static __weak UIWindow *sRefreshWindow;

static void CGManualLog(NSString *event) {
    @try {
        @synchronized([NSFileManager class]) {
            NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:
                @"Documents/ChatGPTRepairLiveSync.log"];
            NSFileManager *fm=[NSFileManager defaultManager];
            NSDictionary *attributes=[fm attributesOfItemAtPath:path error:NULL];
            if ([attributes[NSFileSize] unsignedLongLongValue]>262144)
                [fm removeItemAtPath:path error:NULL];
            if (![fm fileExistsAtPath:path])
                [fm createFileAtPath:path contents:[NSData data] attributes:nil];
            NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
            if (handle) {
                [handle seekToEndOfFile];
                NSString *line=[NSString stringWithFormat:
                    @"%@ event=%@\n",NSDate.date,event];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [handle closeFile];
            }
        }
    } @catch (__unused NSException *exception) {}
}
void CGChatSyncLogEvent(NSString *event) { CGManualLog(event); }

static void CGManualSetWorking(BOOL working) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ CGManualSetWorking(working); });
        return;
    }
    sRefreshButton.enabled=!working;
    sRefreshButton.imageView.hidden=working;
    sRefreshSpinner.hidden=!working;
    if (working) [sRefreshSpinner startAnimating];
    else [sRefreshSpinner stopAnimating];
}

@interface CGManualRefreshAction : NSObject
+ (instancetype)shared;
- (void)refresh:(id)sender;
@end

static void CGManualUpdateButton(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ CGManualUpdateButton(); });
        return;
    }
    BOOL ready=NO;
    @synchronized(CGManualLock()) {
        ready=sSelectedConversation.length && sConversationLoaded &&
              !sHistoryVisible;
    }
    if (!ready || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) {
        sRefreshButton.hidden=YES;
        return;
    }

    UIWindow *window=UIApplication.sharedApplication.keyWindow;
    if (!window) window=UIApplication.sharedApplication.windows.firstObject;
    if (!window) { sRefreshButton.hidden=YES; return; }
    if (!sRefreshButton || sRefreshWindow!=window) {
        [sRefreshButton removeFromSuperview];
        UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];
        button.translatesAutoresizingMaskIntoConstraints=NO;
        button.backgroundColor=UIColor.clearColor;
        button.accessibilityLabel=@"Refresh conversation";
        button.accessibilityHint=@"Fetch new messages in the current chat";
        button.accessibilityTraits=UIAccessibilityTraitButton;
        // User-supplied refresh-arrow icon, cropped to its transparent silhouette.
        NSData *asset=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAABgAAAAZCAYAAAArK+5dAAABjklEQVR42rVWPUsDQRB9ZxQsxMYiVhZahiiBQGy0CClEkUA6G63sxMpGqyhim8ZGBAv1B1gIKS0ESyGVHymiRYIgiEEbBX02czA5du/D3A0sw968ebO7czuzDkkkKQNIWAZD4jIAcgAmZX4P4ArAqwWfBdAC8AmStjFC8oj+8kJyh+Sw8quIbZ8kbORlA1mD5CnJc5J3BnuB5KKa12wBthTojeQqyZRlISWSHcvujAHmFODQ5/i8ox4mwBDJHzFWI5BXwu7gQAw3EciLPj9AjWTPPdgWvR7hN1/wsbUAwHv2nQirDzXcHRREXyRVKsZEPyUV4CvG2lQCQADLmvBZ9EQMAdZEj+skT0mS2zEk9kO4pr33wDXk+iCfF45v95upBt32EeBBOHZNARySXQHs/YO8Kr5dXRy9oLy66psRyI+V34y2mcAbCnxGMu1DPEuyqfBlL8axNP0lAJdq3gBQF50CkAewAiCtMEVpo70S0DJPAlrmu+Rr1MbjhHy2ZFXT/wXwCOAaQDvI0Un6XfQHl3x0gBJvwFIAAAAASUVORK5CYII="
                                                          options:0];
        UIImage *icon=[[UIImage imageWithData:asset]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        if (!icon) icon=[UIImage systemImageNamed:@"arrow.clockwise"];
        [button setImage:icon forState:UIControlStateNormal];
        button.tintColor=[UIColor colorWithWhite:0.94 alpha:1];
        button.imageView.contentMode=UIViewContentModeScaleAspectFit;
        button.imageEdgeInsets=UIEdgeInsetsMake(9,9,9,9);
        [button addTarget:[CGManualRefreshAction shared]
                  action:@selector(refresh:)
        forControlEvents:UIControlEventTouchUpInside];

        UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.translatesAutoresizingMaskIntoConstraints=NO;
        spinner.hidesWhenStopped=YES;
        spinner.color=UIColor.whiteColor;
        spinner.userInteractionEnabled=NO;
        [button addSubview:spinner];
        [window addSubview:button];
        // Place directly to the left of the original New Chat control.
        [NSLayoutConstraint activateConstraints:@[
            [button.widthAnchor constraintEqualToConstant:44],
            [button.heightAnchor constraintEqualToConstant:44],
            [button.trailingAnchor constraintEqualToAnchor:window.trailingAnchor constant:-56],
            [button.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:-10],
            [spinner.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
            [spinner.centerYAnchor constraintEqualToAnchor:button.centerYAnchor]
        ]];
        sRefreshButton=button;
        sRefreshSpinner=spinner;
        sRefreshWindow=window;
        CGManualSetWorking(sRefreshInProgress);
    }
    sRefreshButton.hidden=NO;
    [window bringSubviewToFront:sRefreshButton];
}

@implementation CGManualRefreshAction
+ (instancetype)shared {
    static CGManualRefreshAction *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance=[CGManualRefreshAction new]; });
    return instance;
}
- (void)refresh:(id)sender {
    (void)sender;
    if (!NSThread.isMainThread) return;
    NSString *identifier=nil;
    NSUInteger generation=0;
    @synchronized(CGManualLock()) {
        if (sRefreshInProgress || !sConversationLoaded ||
            sHistoryVisible || !sSelectedConversation.length) return;
        sRefreshInProgress=YES;
        identifier=[sSelectedConversation copy];
        generation=sSelectionGeneration;
    }
    CGManualLog(@"MANUAL_REFRESH_TAPPED");
    CGManualSetWorking(YES);
    BOOL started=CGNativeRefreshConversation(identifier,^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL stillSelected=NO;
            @synchronized(CGManualLock()) {
                stillSelected=generation==sSelectionGeneration;
                sRefreshInProgress=NO;
            }
            CGManualLog(success?@"MANUAL_REFRESH_COMPLETED":
                              @"MANUAL_REFRESH_FAILED");
            CGManualSetWorking(NO);
            if (stillSelected) CGManualUpdateButton();
        });
    });
    if (!started) {
        CGManualLog(@"MANUAL_REFRESH_UNAVAILABLE");
        @synchronized(CGManualLock()) { sRefreshInProgress=NO; }
        CGManualSetWorking(NO);
    } else {
        CGManualLog(@"MANUAL_REFRESH_STARTED");
    }
}
@end

void CGChatManualSetHistoryVisible(BOOL visible) {
    @synchronized(CGManualLock()) { sHistoryVisible=visible; }
    CGManualUpdateButton();
}

void CGChatSyncTrackDetail(NSURLRequest *request,
                           NSURLSessionConfiguration *configuration) {
    (void)configuration;
    NSString *cid=CGPagingConversationID(request);
    if (!cid.length) return;
    @synchronized(CGManualLock()) {
        if ([sSelectedConversation isEqualToString:cid]) return;
        sSelectedConversation=[cid copy];
        sSelectionGeneration++;
        sConversationLoaded=NO;
        sRefreshInProgress=NO;
    }
    CGManualLog(@"MANUAL_CHAT_SELECTED");
    CGManualUpdateButton();
}

void CGChatSyncMarkDelivered(NSURLRequest *request, NSDictionary *root) {
    (void)root;
    NSString *cid=CGPagingConversationID(request);
    if (!cid.length) return;
    @synchronized(CGManualLock()) {
        if (![sSelectedConversation isEqualToString:cid]) return;
        sConversationLoaded=YES;
    }
    CGManualUpdateButton();
}

__attribute__((constructor)) static void CGManualInstall(void) {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"])
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) {
                CGManualUpdateButton();  // UI only; never refresh automatically.
            }];
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationWillResignActiveNotification
            object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) {
                sRefreshButton.hidden=YES;
            }];
    });
}
