#import "ConversationPagingCompat.h"
#import "ConversationPagingState.h"
#import "ConversationPagingCore.h"
#include <math.h>

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

static void CGPagingRefreshVisibleList(UIScrollView *scroll) {
    if (![scroll isKindOfClass:UICollectionView.class]) return;
    UICollectionView *list=(UICollectionView *)scroll;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!list.window) return;
        [list reloadData];
        [list.collectionViewLayout invalidateLayout];
        [list setNeedsLayout];
        [list layoutIfNeeded];
    });
}

static void CGPagingScheduleNext(NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(MAX(0.15,delay)*NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        CGPagingLoadOlder();
    });
}

void CGPagingLoadOlder(void) {
    __block CGConversationPagingState *state=nil;
    __block NSString *cid=nil, *cursor=nil;
    __block NSUInteger generation=0;
    __block NSURLRequest *originalRequest=nil;
    __block NSURLSessionConfiguration *configuration=nil;
    @synchronized(CGPagingStateLock()) {
        state=CGPagingState;
        if (!state || state.loadingOlder || !state.hasPrevious || !state.startCursor.length) return;
        NSTimeInterval now=NSDate.date.timeIntervalSince1970;
        if (now<state.retryNotBefore) {
            CGPagingScheduleNext(state.retryNotBefore-now+0.10);
            return;
        }
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
                NSInteger status=CGPagingStatus(response);
                NSDictionary *page=nil;
                NSArray *pageMessages=@[];
                BOOL pageHasPrevious=NO;
                NSString *pageCursor=nil;
                BOOL fallback=NO;

                if (!error && status>=200 && status<300) {
                    page=CGConversationPagingJSONObject(data);
                    if (!page || CGConversationPagingHasVersionMarkers(page)) {
                        fallback=YES;
                    } else {
                        id rawMessages=page[@"messages"];
                        NSDictionary *pageInfo=[page[@"page_info"] isKindOfClass:NSDictionary.class]?page[@"page_info"]:nil;
                        if (![rawMessages isKindOfClass:NSArray.class] || !pageInfo) {
                            fallback=YES;
                        } else {
                            pageMessages=(NSArray *)rawMessages;
                            pageCursor=CGConversationPagingStartCursor(page,&pageHasPrevious);
                        }
                    }
                }

                __block NSArray *merged=nil; __block NSDictionary *root=nil; __block NSString *current=nil;
                __block NSURLRequest *original=nil; __block NSURLResponse *template=nil;
                __block NSURLSessionConfiguration *savedConfig=nil;
                __block void (^forward)(NSData *,NSURLResponse *,NSError *)=nil;
                __block UIScrollView *scroll=nil;
                __block BOOL loadAnother=NO;
                __block NSTimeInterval nextDelay=0.45;

                @synchronized(CGPagingStateLock()) {
                    if (CGPagingState!=state || ![CGPagingSelectedID isEqualToString:cid] || CGPagingGeneration!=generation) {
                        CGPagingSetLoading(NO);
                        return;
                    }
                    state.loadingOlder=NO;

                    if (status==429 || CGPagingTransientFailure(status,error)) {
                        NSTimeInterval delay=MIN(MAX(4.0,CGPagingRetryAfter(response)),120.0);
                        state.retryNotBefore=NSDate.date.timeIntervalSince1970+delay;
                        loadAnother=state.hasPrevious;
                        nextDelay=delay+0.15;
                    } else if (fallback || CGPagingCompatibilityFailure(status)) {
                        state.hasPrevious=NO;
                        original=state.originalRequest;
                        forward=[state.completion copy];
                        savedConfig=[state.configuration copy];
                    } else if (error || status<200 || status>=300) {
                        state.hasPrevious=NO;
                    } else if (!pageMessages.count) {
                        // Empty 200 page is a clean end-of-history signal.
                        state.hasPrevious=NO;
                    } else {
                        NSUInteger oldCount=state.messages.count;
                        merged=CGConversationPagingMergeMessages(pageMessages,state.messages);
                        BOOL advanced=merged.count>oldCount;
                        BOOL cursorAdvanced=pageCursor.length && ![pageCursor isEqualToString:state.startCursor];

                        if (!advanced) {
                            state.hasPrevious=NO;
                        } else {
                            state.messages=merged;
                            state.loadedOlder=YES;
                            if (pageCursor.length) state.startCursor=pageCursor;

                            // Some backend variants have omitted or misreported
                            // has_previous_page. A full page with an advancing
                            // cursor is safe to probe once more; an empty or
                            // duplicate page terminates the chain above.
                            BOOL inferredPrevious=pageHasPrevious ||
                                (pageMessages.count>=10 && cursorAdvanced);
                            state.hasPrevious=inferredPrevious;
                            state.retryNotBefore=NSDate.date.timeIntervalSince1970+0.35;

                            root=state.baseRoot;
                            current=state.currentNode;
                            original=state.originalRequest;
                            template=state.responseTemplate;
                            forward=[state.completion copy];
                            scroll=state.scrollView;
                            loadAnother=inferredPrevious;
                        }
                    }
                }

                if (fallback || CGPagingCompatibilityFailure(status)) {
                    CGPagingSetLoading(NO);
                    if (original && forward) {
                        CGPagingFetchLegacy(savedConfig,original,cid,generation,
                            ^(NSData *legacyData,NSURLResponse *legacyResponse,NSError *legacyError) {
                                if (legacyData.length && !legacyError) {
                                    forward(legacyData,legacyResponse,nil);
                                    CGPagingRefreshVisibleList(scroll);
                                } else {
                                    forward(legacyData,legacyResponse,legacyError);
                                }
                            });
                    }
                    return;
                }

                if (merged.count && root && original && forward) {
                    NSData *legacy=CGConversationPagingLegacyData(root,merged,current);
                    if (legacy.length) {
                        __block CGSize oldSize=CGSizeZero;
                        __block CGPoint oldOffset=CGPointZero;
                        if (scroll) {
                            void (^capture)(void)=^{ oldSize=scroll.contentSize; oldOffset=scroll.contentOffset; };
                            if (NSThread.isMainThread) capture(); else dispatch_sync(dispatch_get_main_queue(),capture);
                        }
                        forward(legacy,CGPagingLegacyResponse(template,original.URL,legacy.length),nil);
                        CGPagingRefreshVisibleList(scroll);
                        if (scroll) CGPagingRestoreScroll(scroll,oldSize,oldOffset);
                    }
                }

                if (loadAnother) {
                    // Continue filling the same open conversation until the
                    // backend reports the true beginning. The newest section
                    // was already shown, so this work happens progressively in
                    // the background without blocking initial chat display.
                    CGPagingScheduleNext(nextDelay);
                } else {
                    CGPagingSetLoading(NO);
                }
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
        if (!CGPagingState) return;
        CGPagingState.scrollView=scrollView;
    }
}
