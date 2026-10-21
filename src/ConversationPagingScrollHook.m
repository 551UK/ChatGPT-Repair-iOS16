#import "ConversationPagingCompat.h"
#import <objc/runtime.h>

static char kPagingOriginalScrollIMP;
static IMP sOriginalCollectionSetDelegate=NULL;
static BOOL sDelegateHookInstalled=NO;

static BOOL CGPagingMessageDelegateClass(Class cls) {
    if (!cls) return NO;
    NSString *name=NSStringFromClass(cls);
    return [name containsString:@"BottomAlignedCollectionViewController"];
}

static void CGPagingMessageDidScroll(id object, SEL command, UIScrollView *scrollView) {
    Class cls=object_getClass(object);
    NSValue *stored=cls?objc_getAssociatedObject((id)cls,&kPagingOriginalScrollIMP):nil;
    IMP original=stored.pointerValue;
    if (original && original!=(IMP)CGPagingMessageDidScroll)
        ((void(*)(id,SEL,UIScrollView *))original)(object,command,scrollView);
    CGConversationPagingHandleMessageScroll(scrollView);
}

static void CGPagingInstallDelegateClass(Class cls) {
    if (!CGPagingMessageDelegateClass(cls)) return;
    SEL selector=@selector(scrollViewDidScroll:);
    Method method=class_getInstanceMethod(cls,selector);
    if (!method) return;
    IMP current=method_getImplementation(method);
    if (current==(IMP)CGPagingMessageDidScroll) return;

    objc_setAssociatedObject((id)cls,&kPagingOriginalScrollIMP,
                             [NSValue valueWithPointer:current],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    class_replaceMethod(cls,selector,(IMP)CGPagingMessageDidScroll,
                        method_getTypeEncoding(method));
}

static void CGPagingCollectionSetDelegate(UICollectionView *collection,
                                          SEL command,
                                          id<UIScrollViewDelegate> delegate) {
    if (sOriginalCollectionSetDelegate)
        ((void(*)(id,SEL,id))sOriginalCollectionSetDelegate)(collection,command,delegate);
    CGPagingInstallDelegateClass(object_getClass(delegate));
}

static void CGPagingScanView(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:UICollectionView.class]) {
        id delegate=((UICollectionView *)view).delegate;
        CGPagingInstallDelegateClass(object_getClass(delegate));
    }
    for (UIView *child in view.subviews) CGPagingScanView(child);
}

static void CGPagingScanExistingCollections(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows)
        CGPagingScanView(window);
}

void CGConversationPagingInstallScrollHook(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(),^{ CGConversationPagingInstallScrollHook(); });
        return;
    }

    if (!sDelegateHookInstalled) {
        Class cls=UICollectionView.class;
        SEL selector=@selector(setDelegate:);
        Method method=class_getInstanceMethod(cls,selector);
        if (method) {
            IMP current=method_getImplementation(method);
            if (current!=(IMP)CGPagingCollectionSetDelegate) {
                sOriginalCollectionSetDelegate=current;
                class_replaceMethod(cls,selector,(IMP)CGPagingCollectionSetDelegate,
                                    method_getTypeEncoding(method));
            }
            sDelegateHookInstalled=YES;
        }
    }

    // The message collection may already exist by the time the paging
    // response arrives. Find its real Swift generic delegate class and hook
    // that concrete specialization rather than guessing an objc_getClass()
    // name for BottomAlignedCollectionViewController.
    CGPagingScanExistingCollections();
}
