#import "ConversationPagingCompat.h"
#import "ConversationPagingState.h"
#import <UIKit/UIKit.h>

static NSTimer *sPagingWatchTimer;

static BOOL CGPagingResponderLooksLikeMessages(UICollectionView *list) {
    UIResponder *responder=list;
    BOOL sawConversation=NO;
    for (NSUInteger i=0;responder && i<16;i++,responder=responder.nextResponder) {
        NSString *name=NSStringFromClass(responder.class);
        if ([name containsString:@"History"] || [name containsString:@"SideMenu"]) return NO;
        if ([name containsString:@"BottomAlignedCollectionViewController"] ||
            [name containsString:@"ChatGPTConversation"] ||
            [name containsString:@"ConversationViewController"] ||
            [name containsString:@"Messages"])
            sawConversation=YES;
    }
    NSString *delegateName=NSStringFromClass([(id)list.delegate class]);
    if ([delegateName containsString:@"History"] || [delegateName containsString:@"SideMenu"]) return NO;
    if ([delegateName containsString:@"BottomAlignedCollectionViewController"] ||
        [delegateName containsString:@"ChatGPTMessages"]) sawConversation=YES;
    return sawConversation;
}

static CGFloat CGPagingVisibleArea(UICollectionView *list) {
    if (!list.window || list.hidden || list.alpha<0.01) return 0;
    CGRect rect=[list convertRect:list.bounds toView:list.window];
    CGRect clipped=CGRectIntersection(rect,list.window.bounds);
    if (CGRectIsNull(clipped) || CGRectIsEmpty(clipped)) return 0;
    return clipped.size.width*clipped.size.height;
}

static void CGPagingCollectCollections(UIView *view, NSMutableArray<UICollectionView *> *out) {
    if (!view || view.hidden || view.alpha<0.01) return;
    if ([view isKindOfClass:UICollectionView.class]) [out addObject:(UICollectionView *)view];
    for (UIView *child in view.subviews) CGPagingCollectCollections(child,out);
}

static UICollectionView *CGPagingFindMessageCollection(void) {
    NSMutableArray<UICollectionView *> *lists=[NSMutableArray array];
    for (UIWindow *window in UIApplication.sharedApplication.windows)
        if (!window.hidden && window.alpha>0.01) CGPagingCollectCollections(window,lists);

    UICollectionView *best=nil;
    CGFloat bestArea=0;
    for (UICollectionView *list in lists) {
        CGFloat area=CGPagingVisibleArea(list);
        if (area<60000) continue;
        if (!CGPagingResponderLooksLikeMessages(list)) continue;
        if (area>bestArea) { best=list; bestArea=area; }
    }
    if (best) return best;

    // Last-resort fallback: choose the largest visible collection that is not
    // clearly the sidebar/history list. This keeps paging usable if Swift's
    // specialized runtime class name changes again.
    for (UICollectionView *list in lists) {
        CGFloat area=CGPagingVisibleArea(list);
        if (area<60000) continue;
        NSString *delegateName=NSStringFromClass([(id)list.delegate class]);
        if ([delegateName containsString:@"History"] || [delegateName containsString:@"SideMenu"]) continue;
        if (area>bestArea) { best=list; bestArea=area; }
    }
    return best;
}

static void CGPagingWatchTick(__unused NSTimer *timer) {
    BOOL active=NO;
    @synchronized(CGPagingStateLock()) {
        active=CGPagingState && CGPagingState.hasPrevious;
    }
    if (!active) return;
    UICollectionView *list=CGPagingFindMessageCollection();
    if (list) CGConversationPagingHandleMessageScroll(list);
}

void CGConversationPagingInstallScrollHook(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(),^{ CGConversationPagingInstallScrollHook(); });
        return;
    }
    if (!sPagingWatchTimer) {
        NSTimer *timer=[NSTimer timerWithTimeInterval:0.20 repeats:YES
            block:^(NSTimer *t) { CGPagingWatchTick(t); }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        sPagingWatchTimer=timer;
    }
}
