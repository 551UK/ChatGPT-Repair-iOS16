#import "ConversationPagingCompat.h"
#import "ConversationPagingState.h"
#import "ConversationPagingCore.h"
#include <math.h>

static const CGFloat kLoadOlderDistance=700.0;
static __weak UIActivityIndicatorView *sPagingSpinner;

@interface NSURLSession (CGConversationPagingOriginal)
- (NSURLSessionDataTask *)cgp_dataTaskWithRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

static UIWindow *CGPagingFrontWindow(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator)
        if (!window.hidden && window.alpha>0.01 && window.windowLevel==UIWindowLevelNormal)
            return window;
    return UIApplication.sharedApplication.windows.firstObject;
}

static void CGPagingSetLoading(BOOL visible) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIActivityIndicatorView *spinner=sPagingSpinner;
        if (visible) {
            UIWindow *window=CGPagingFrontWindow();
            if (!window) return;
            if (!spinner || spinner.superview!=window) {
                [spinner removeFromSuperview];
                spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
                spinner.userInteractionEnabled=NO;
                spinner.hidesWhenStopped=YES;
                spinner.accessibilityLabel=@"Loading older messages";
                [window addSubview:spinner];
                sPagingSpinner=spinner;
            }
            CGFloat top=window.safeAreaInsets.top+54.0;
            spinner.center=CGPointMake(CGRectGetMidX(window.bounds),top);
            [window bringSubviewToFront:spinner];
            [spinner startAnimating];
        } else {
            [spinner stopAnimating];
        }
    });
}

static void CGPagingRestoreScroll(UIScrollView *scroll, CGSize oldSize, CGPoint oldOffset) {
    if (!scroll) return;
    __block BOOL adjusted=NO;
    for (NSNumber *delay in @[@0.12,@0.30,@0.70]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            if (adjusted || !scroll.window) return;
            CGFloat delta=scroll.contentSize.height-oldSize.height;
            if (!isfinite(delta) || delta<=1) return;
            CGFloat minimum=-scroll.adjustedContentInset.top;
            CGFloat maximum=MAX(minimum,scroll.contentSize.height-scroll.bounds.size.height+scroll.adjustedContentInset.bottom);
            [scroll setContentOffset:CGPointMake(oldOffset.x,MIN(maximum,MAX(minimum,oldOffset.y+delta))) animated:NO];
            adjusted=YES;
        });
    }
}

void CGPagingLoadOlder(void) {
    __block CGConversationPagingState *state=nil;
    __block NSString *cid=nil, *cursor=nil;
    __block NSUInteger generation=0;
    __block NSURLRequest *originalRequest=nil;
    __block NSURLSessionConfiguration *configuration=nil;
    @synchronized(CGPagingStateLock()) {
        state=CGPagingState;
        if (!state || state.loadingOlder || !state.hasPrevious || !state.startCursor.length ||
            NSDate.date.timeIntervalSince1970<state.retryNotBefore) return;
        state.loadingOlder=YES;
        cid=state.conversationID; generation=state.generation; cursor=state.startCursor;
        originalRequest=state.originalRequest; configuration=[state.configuration copy];
    }
    if (!cid.length || !originalRequest || !configuration) {
        @synchronized(CGPagingStateLock()) { if (CGPagingState==state) state.loadingOlder=NO; }
        return;
    }

    CGPagingSetLoading(YES);
    NSURLRequest *pageRequest=CGPagingModernRequest(originalRequest,cursor);
    NSURLSessionConfiguration *config=[configuration copy];
    config.timeoutIntervalForRequest=30;
    __block NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
    @try {
        NSURLSessionDataTask *task=[session cgp_dataTaskWithRequest:pageRequest completionHandler:
            ^(NSData *data, NSURLResponse *response, NSError *error) {
                [session finishTasksAndInvalidate]; session=nil;
                CGPagingSetLoading(NO);
                NSInteger status=CGPagingStatus(response);
                NSDictionary *page=nil; BOOL pageHasPrevious=NO; NSString *pageCursor=nil; BOOL fallback=NO;
                if (!error && status>=200 && status<300) {
                    page=CGConversationPagingJSONObject(data);
                    fallback=!page || !CGPagingValidPageRoot(page,&pageHasPrevious,&pageCursor) ||
                             CGConversationPagingHasVersionMarkers(page);
                }

                __block NSArray *merged=nil; __block NSDictionary *root=nil; __block NSString *current=nil;
                __block NSURLRequest *original=nil; __block NSURLResponse *template=nil;
                __block NSURLSessionConfiguration *savedConfig=nil;
                __block void (^forward)(NSData *,NSURLResponse *,NSError *)=nil;
                __block UIScrollView *scroll=nil;
                @synchronized(CGPagingStateLock()) {
                    if (CGPagingState!=state || ![CGPagingSelectedID isEqualToString:cid] || CGPagingGeneration!=generation) return;
                    state.loadingOlder=NO;
                    if (status==429 || CGPagingTransientFailure(status,error)) {
                        state.retryNotBefore=NSDate.date.timeIntervalSince1970+MIN(MAX(4.0,CGPagingRetryAfter(response)),120.0);
                        return;
                    }
                    if (fallback || CGPagingCompatibilityFailure(status)) {
                        state.hasPrevious=NO; original=state.originalRequest; forward=[state.completion copy]; savedConfig=[state.configuration copy];
                    } else if (error || status<200 || status>=300) return;
                    else {
                        merged=CGConversationPagingMergeMessages(CGConversationPagingMessages(page),state.messages);
                        if (!merged.count || (pageHasPrevious && (!pageCursor.length || [pageCursor isEqualToString:state.startCursor]))) {
                            state.hasPrevious=NO; return;
                        }
                        state.messages=merged; state.loadedOlder=YES; state.startCursor=pageCursor;
                        state.hasPrevious=pageHasPrevious;
                        state.retryNotBefore=NSDate.date.timeIntervalSince1970+0.8;
                        root=state.baseRoot; current=state.currentNode; original=state.originalRequest;
                        template=state.responseTemplate; forward=[state.completion copy]; scroll=state.scrollView;
                    }
                }
                if (fallback || CGPagingCompatibilityFailure(status)) {
                    if (original && forward) CGPagingFetchLegacy(savedConfig,original,cid,generation,forward);
                    return;
                }
                if (!merged.count || !root || !original || !forward) return;
                NSData *legacy=CGConversationPagingLegacyData(root,merged,current);
                if (!legacy.length) return;
                __block CGSize oldSize=CGSizeZero; __block CGPoint oldOffset=CGPointZero;
                if (scroll) {
                    void (^capture)(void)=^{ oldSize=scroll.contentSize; oldOffset=scroll.contentOffset; };
                    if (NSThread.isMainThread) capture(); else dispatch_sync(dispatch_get_main_queue(),capture);
                }
                // The 2024 repository's detail completion is intentionally
                // retained by the paging state and can accept refreshed
                // synthetic mapping data for the currently selected chat.
                forward(legacy,CGPagingLegacyResponse(template,original.URL,legacy.length),nil);
                if (scroll) CGPagingRestoreScroll(scroll,oldSize,oldOffset);
            }];
        if (task) [task resume];
        else {
            [session invalidateAndCancel]; session=nil; CGPagingSetLoading(NO);
            @synchronized(CGPagingStateLock()) { if (CGPagingState==state) state.loadingOlder=NO; }
        }
    } @catch (__unused NSException *exception) {
        [session invalidateAndCancel]; session=nil; CGPagingSetLoading(NO);
        @synchronized(CGPagingStateLock()) { if (CGPagingState==state) state.loadingOlder=NO; }
    }
}

void CGConversationPagingHandleMessageScroll(UIScrollView *scrollView) {
    if (!scrollView || !scrollView.window) return;
    @synchronized(CGPagingStateLock()) {
        if (!CGPagingState || !CGPagingState.hasPrevious) return;
        CGPagingState.scrollView=scrollView;
    }

    CGFloat minimum=-scrollView.adjustedContentInset.top;
    CGFloat maximum=MAX(minimum,scrollView.contentSize.height-scrollView.bounds.size.height+
                        scrollView.adjustedContentInset.bottom);
    CGFloat y=scrollView.contentOffset.y;
    CGFloat topDistance=fabs(y-minimum);
    CGFloat bottomDistance=fabs(maximum-y);
    BOOL contentFits=scrollView.contentSize.height<=scrollView.bounds.size.height+80.0;
    BOOL userMoving=scrollView.dragging || scrollView.decelerating || scrollView.tracking;

    // BottomAlignedCollectionViewController can report its conversation-start
    // edge differently depending on the active layout. Treat either visible
    // edge as a valid paging trigger once the user interacts. If the first page
    // is shorter than one screen, load older immediately because there is no
    // scroll gesture capable of reaching another edge.
    if (contentFits ||
        (userMoving && ((isfinite(topDistance) && topDistance<kLoadOlderDistance) ||
                        (isfinite(bottomDistance) && bottomDistance<kLoadOlderDistance)))) {
        CGPagingLoadOlder();
    }
}
