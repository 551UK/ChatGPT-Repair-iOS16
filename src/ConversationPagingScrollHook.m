#import "ConversationPagingCompat.h"
#import <objc/runtime.h>

static IMP sOriginalMessageScroll=NULL;
static BOOL sScrollHookInstalled=NO;

static void CGPagingMessageDidScroll(id object, SEL command, UIScrollView *scrollView) {
    if (sOriginalMessageScroll)
        ((void(*)(id,SEL,UIScrollView *))sOriginalMessageScroll)(object,command,scrollView);
    CGConversationPagingHandleMessageScroll(scrollView);
}

void CGConversationPagingInstallScrollHook(void) {
    if (sScrollHookInstalled) return;
    Class cls=objc_getClass("_TtC15ChatGPTMessages37BottomAlignedCollectionViewController");
    if (!cls) return;
    SEL selector=@selector(scrollViewDidScroll:);
    Method method=class_getInstanceMethod(cls,selector);
    if (!method) return;
    IMP original=method_getImplementation(method);
    if (original==(IMP)CGPagingMessageDidScroll) { sScrollHookInstalled=YES; return; }
    sOriginalMessageScroll=original;
    class_replaceMethod(cls,selector,(IMP)CGPagingMessageDidScroll,method_getTypeEncoding(method));
    sScrollHookInstalled=YES;
}
