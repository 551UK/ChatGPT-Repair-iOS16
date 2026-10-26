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


static UIView *CGManualNewChatControlIn(UIView *root, UIWindow *window,
                                       CGFloat safe, NSUInteger depth) {
    if (!root || !window || depth>35) return nil;
    NSMutableArray<UIView *> *candidates=[NSMutableArray array];
    NSMutableArray<NSNumber *> *scores=[NSMutableArray array];
    NSMutableArray<UIView *> *stack=[NSMutableArray arrayWithObject:root];
    NSUInteger visited=0;
    while (stack.count && visited++<3000) {
        UIView *view=stack.lastObject;
        [stack removeLastObject];
        if (view==sRefreshButton || view.hidden || view.alpha<0.05) continue;
        for (UIView *child in view.subviews) [stack addObject:child];
        CGRect bounds=[view convertRect:view.bounds toView:window];
        if (CGRectIsEmpty(bounds) || !isfinite(bounds.origin.x) ||
            !isfinite(bounds.origin.y) || bounds.size.width<14 ||
            bounds.size.height<14 || bounds.size.width>100 ||
            bounds.size.height>100) continue;
        CGFloat mx=CGRectGetMidX(bounds),my=CGRectGetMidY(bounds);
        if (mx<window.bounds.size.width*0.70 || mx>window.bounds.size.width-4 ||
            my<safe-22 || my>safe+82) continue;
        NSString *label=[view.accessibilityLabel ?: @"" lowercaseString];
        NSString *ident=[view.accessibilityIdentifier ?: @"" lowercaseString];
        NSString *value=[NSString stringWithFormat:@"%@ %@",label,ident];
        if ([view isKindOfClass:UIButton.class]) {
            NSString *title=[(UIButton *)view titleForState:UIControlStateNormal];
            if (title.length)
                value=[value stringByAppendingFormat:@" %@",title.lowercaseString];
        }
        if ([value containsString:@"refresh"]) continue;
        BOOL newChat=([value containsString:@"new chat"] ||
            [value containsString:@"new conversation"] ||
            [value containsString:@"compose"] ||
            [value containsString:@"start chat"]);
        BOOL interactive=[view isKindOfClass:UIControl.class] ||
            (view.accessibilityTraits & UIAccessibilityTraitButton)!=0;
        if (!newChat && !interactive) continue;
        CGFloat score=newChat?1000:0;
        score+=100.0-MIN(100.0,fabs(window.bounds.size.width-26-mx));
        score+=50.0-MIN(50.0,fabs(safe+21-my));
        if ([view isKindOfClass:UIButton.class]) score+=10;
        [candidates addObject:view];
        [scores addObject:@(score)];
    }
    NSUInteger best=NSNotFound;
    for (NSUInteger i=0;i<scores.count;i++) {
        if (best==NSNotFound || scores[i].doubleValue>scores[best].doubleValue)
            best=i;
    }
    return best==NSNotFound?nil:candidates[best];
}
static CGRect CGManualButtonFrame(UIView *host, UIWindow *window, BOOL *anchored) {
    CGFloat safe=window.safeAreaInsets.top;
    UIView *target=CGManualNewChatControlIn(window.rootViewController.view,window,safe,0);
    CGRect inWindow;
    if (target) {
        CGRect r=[target convertRect:target.bounds toView:window];
        // Adjacent 44pt touch areas, both vertically aligned.
        inWindow=CGRectMake(CGRectGetMidX(r)-66,CGRectGetMidY(r)-22,44,44);
    } else {
        // Fallback tracks the original New Chat position on this iOS 16 layout.
        inWindow=CGRectMake(CGRectGetWidth(window.bounds)-94,safe-2,44,44);
    }
    if (anchored) *anchored=target!=nil;
    return [host convertRect:inWindow fromView:window];
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
        return;
    }

    UIWindow *window=UIApplication.sharedApplication.keyWindow;
    if (!window) window=UIApplication.sharedApplication.windows.firstObject;
    if (!window) { sRefreshButton.hidden=YES; return; }
    UIView *host=window.rootViewController.view ?: window;
    if (!sRefreshButton || sRefreshButton.superview!=host) {
        [sRefreshButton removeFromSuperview];
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
        spinner.frame=CGRectMake(12,12,20,20);
        spinner.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin |
            UIViewAutoresizingFlexibleRightMargin;
        spinner.hidesWhenStopped=YES;
        spinner.color=UIColor.whiteColor;
        spinner.userInteractionEnabled=NO;
        [button addSubview:spinner];
        [host addSubview:button];
        sRefreshButton=button;
        sRefreshSpinner=spinner;
        CGManualSetWorking(sRefreshInProgress);
    }
    BOOL matched=NO;
    sRefreshButton.frame=CGManualButtonFrame(host,window,&matched);
    sRefreshButton.hidden=NO;
    [host bringSubviewToFront:sRefreshButton];
    // The app renders New Chat in SwiftUI. Log which positioning route worked.
    static NSInteger lastPlacement=-1;
    if (lastPlacement!=(NSInteger)matched) {
        CGManualLog(matched?@"MANUAL_BUTTON_ALIGNED":@"MANUAL_BUTTON_FALLBACK");
        lastPlacement=matched;
    }
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
        sConversationLoaded=NO;
        sRefreshInProgress=NO;
    }
    CGManualLog(@"MANUAL_CHAT_SELECTED");
    // Avoid touching UIKit while the original conversation request is opening.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sRefreshButton) sRefreshButton.hidden=YES;
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1500*NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        CGManualUpdateButton();
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
            }];
    });
}
