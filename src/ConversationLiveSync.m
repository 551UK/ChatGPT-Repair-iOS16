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
static BOOL sRefreshInProgress;
static NSUInteger sSelectionGeneration;
static NSUInteger sAutoHydratedGeneration=NSUIntegerMax;
static UIButton *sRefreshButton;
static UIActivityIndicatorView *sRefreshSpinner;

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

static CGRect CGManualSpinnerFrame(UIView *host) {
    const CGFloat side=20.0;
    CGRect bounds=host.bounds;
    return CGRectMake(floor((CGRectGetWidth(bounds)-side)/2.0),
                      floor((CGRectGetHeight(bounds)-side)/2.0),
                      side,side);
}

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


// Fixed, tested header coordinates. Avoid querying SwiftUI accessibility
// while the ChatGPT conversation renderer is constructing a large chat.
static CGRect CGManualButtonFrame(UIView *host, UIWindow *window) {
    CGFloat safe=window.safeAreaInsets.top;
    CGRect rect=CGRectMake(CGRectGetWidth(window.bounds)-90,safe-2,44,44);
    return [host convertRect:rect fromView:window];
}

static void CGManualUpdateButton(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ CGManualUpdateButton(); });
        return;
    }
    BOOL ready=NO;
    @synchronized(CGManualLock()) {
        ready=sSelectedConversation.length && sConversationLoaded;
    }
    if (!ready || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) {
        sRefreshButton.hidden=YES;
        sRefreshSpinner.hidden=YES;
        return;
    }

    UIWindow *window=UIApplication.sharedApplication.keyWindow;
    if (!window) window=UIApplication.sharedApplication.windows.firstObject;
    if (!window) {
        sRefreshButton.hidden=YES;
        sRefreshSpinner.hidden=YES;
        return;
    }
    UIView *host=window.rootViewController.view ?: window;
    if (!sRefreshButton || sRefreshButton.superview!=host) {
        [sRefreshButton removeFromSuperview];
        [sRefreshSpinner removeFromSuperview];
        UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];
        button.translatesAutoresizingMaskIntoConstraints=YES;
        button.backgroundColor=UIColor.clearColor;
        button.accessibilityLabel=@"Refresh conversation";
        button.accessibilityHint=@"Fetch new messages in the current chat";
        button.accessibilityTraits=UIAccessibilityTraitButton;
        // User-supplied refresh-arrow icon, cropped to its transparent silhouette.
        NSData *asset=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAABgAAAAZCAYAAAArK+5dAAABjklEQVR42rVWPUsDQRB9ZxQsxMYiVhZahiiBQGy0CClEkUA6G63sxMpGqyhim8ZGBAv1B1gIKS0ESyGVHymiRYIgiEEbBX02czA5du/D3A0sw968ebO7czuzDkkkKQNIWAZD4jIAcgAmZX4P4ArAqwWfBdAC8AmStjFC8oj+8kJyh+Sw8quIbZ8kbORlA1mD5CnJc5J3BnuB5KKa12wBthTojeQqyZRlISWSHcvujAHmFODQ5/i8ox4mwBDJHzFWI5BXwu7gQAw3EciLPj9AjWTPPdgWvR7hN1/wsbUAwHv2nQirDzXcHRREXyRVKsZEPyUV4CvG2lQCQADLmvBZ9EQMAdZEj+skT0mS2zEk9kO4pr33wDXk+iCfF45v95upBt32EeBBOHZNARySXQHs/YO8Kr5dXRy9oLy66psRyI+V34y2mcAbCnxGMu1DPEuyqfBlL8axNP0lAJdq3gBQF50CkAewAiCtMEVpo70S0DJPAlrmu+Rr1MbjhHy2ZFXT/wXwCOAaQDvI0Un6XfQHl3x0gBJvwFIAAAAASUVORK5CYII="
                                                          options:0];
        UIImage *icon=[UIImage imageWithData:asset];
        if (!icon) icon=[UIImage systemImageNamed:@"arrow.clockwise"];
        // Render the original refresh symbol at 20pt rather than its 24pt
        // source size; this matches the adjacent New Chat icon better.
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(20,20),NO,0);
        [icon drawInRect:CGRectMake(0,0,20,20)];
        UIImage *smallIcon=UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [button setImage:[(smallIcon ?: icon)
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                forState:UIControlStateNormal];
        button.tintColor=[UIColor colorWithWhite:0.94 alpha:1];
        button.imageView.contentMode=UIViewContentModeScaleAspectFit;
        // Lower only the artwork by 2pt; keep the full 44pt tap target
        // aligned to the native New Chat control.
        button.imageEdgeInsets=UIEdgeInsetsMake(11,9,7,9);
        [button addTarget:[CGManualRefreshAction shared]
                  action:@selector(refresh:)
        forControlEvents:UIControlEventTouchUpInside];

        UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.translatesAutoresizingMaskIntoConstraints=YES;
        // Keep the same 20pt spinner, but show it at the exact midpoint of
        // the visible chat/root view instead of inside the top-right button.
        spinner.frame=CGManualSpinnerFrame(host);
        spinner.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin |
            UIViewAutoresizingFlexibleRightMargin |
            UIViewAutoresizingFlexibleTopMargin |
            UIViewAutoresizingFlexibleBottomMargin;
        spinner.hidesWhenStopped=YES;
        spinner.color=UIColor.whiteColor;
        spinner.userInteractionEnabled=NO;
        [host addSubview:button];
        [host addSubview:spinner];
        sRefreshButton=button;
        sRefreshSpinner=spinner;
        CGManualSetWorking(sRefreshInProgress);
    }
    sRefreshButton.frame=CGManualButtonFrame(host,window);
    sRefreshSpinner.frame=CGManualSpinnerFrame(host);
    sRefreshButton.hidden=NO;
    CGManualSetWorking(sRefreshInProgress);
    [host bringSubviewToFront:sRefreshButton];
    if (sRefreshInProgress) [host bringSubviewToFront:sRefreshSpinner];
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
            !sSelectedConversation.length) return;
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

void CGChatSyncTrackDetail(NSURLRequest *request,
                           NSURLSessionConfiguration *configuration) {
    (void)configuration;
    NSString *cid=CGPagingConversationID(request);
    if (!cid.length) return;
    @synchronized(CGManualLock()) {
        if ([sSelectedConversation isEqualToString:cid]) return;
        sSelectedConversation=[cid copy];
        sSelectionGeneration++;
        sAutoHydratedGeneration=NSUIntegerMax;
        sConversationLoaded=NO;
        sRefreshInProgress=NO;
    }
    CGManualLog(@"MANUAL_CHAT_SELECTED");
    // Avoid touching UIKit while the original conversation request is opening.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sRefreshButton) sRefreshButton.hidden=YES;
        if (sRefreshSpinner) sRefreshSpinner.hidden=YES;
    });
}

void CGChatSyncMarkDelivered(NSURLRequest *request, NSDictionary *root) {
    (void)root;
    NSString *cid=CGPagingConversationID(request);
    if (!cid.length) return;
    @synchronized(CGManualLock()) {
        if (![sSelectedConversation isEqualToString:cid]) return;
        sConversationLoaded=YES;
    }
    // The button is added to the existing root view, not the UIWindow layout.
    // Never instantiate it during an in-flight paginated conversation request.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(5*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CGManualUpdateButton();
    });
}

// This is a one-off completion of the initial chat open, not a timer,
// streaming poll or change to the user-controlled refresh button.
void CGChatSyncHydrateBackgroundHistory(NSURLRequest *request) {
    NSString *cid=CGPagingConversationID(request);
    if (!cid.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL selected=NO;
        @synchronized(CGManualLock()) {
            selected=[sSelectedConversation isEqualToString:cid] &&
                sConversationLoaded && !sRefreshInProgress &&
                sAutoHydratedGeneration!=sSelectionGeneration;
            if (selected) sAutoHydratedGeneration=sSelectionGeneration;
        }
        if (!selected || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) {
            CGManualLog(@"BACKGROUND_HISTORY_REFRESH_SKIPPED");
            return;
        }
        BOOL started=CGNativeRefreshConversation(cid,^(BOOL success) {
            CGManualLog(success?@"BACKGROUND_HISTORY_REFRESH_COMPLETED":
                                  @"BACKGROUND_HISTORY_REFRESH_FAILED");
        });
        CGManualLog(started?@"BACKGROUND_HISTORY_REFRESH_STARTED":
                            @"BACKGROUND_HISTORY_REFRESH_UNAVAILABLE");
    });
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
                sRefreshSpinner.hidden=YES;
            }];
    });
}
