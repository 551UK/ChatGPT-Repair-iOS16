// PinnedLayoutShim.m — 551UK / GPL-3.0
// Add a native layout gap without touching any UICollectionViewCell frame,
// transform, font or subview. Only the history list's layout is affected.
#import "PinnedLayoutShim.h"
#import <objc/runtime.h>
#import <math.h>

static char kPinGap, kPinFrom;
static IMP sOriginalElements=NULL, sOriginalItem=NULL;
static IMP sOriginalSupplementary=NULL, sOriginalSize=NULL;
static Class sHookedLayoutClass=Nil;

static CGFloat CGGap(UICollectionViewLayout *layout) {
    NSNumber *n=objc_getAssociatedObject(layout,&kPinGap);
    return n?n.doubleValue:0;
}
static CGFloat CGAnchor(UICollectionViewLayout *layout) {
    NSNumber *n=objc_getAssociatedObject(layout,&kPinFrom);
    return n?n.doubleValue:0;
}
static UICollectionViewLayoutAttributes *CGShiftAttr(UICollectionViewLayoutAttributes *attr,
                                               CGFloat from, CGFloat gap) {
    if (!attr) return nil;
    UICollectionViewLayoutAttributes *copy=[attr copy];
    if (gap>0 && CGRectGetMinY(copy.frame)>=from-0.5) {
        CGRect r=copy.frame;
        r.origin.y+=gap;
        copy.frame=r;
    }
    return copy;
}
static NSArray<UICollectionViewLayoutAttributes *> *
CGPinnedElements(UICollectionViewLayout *layout, SEL sel, CGRect rect) {
    NSArray *(*original)(id,SEL,CGRect)=(void *)sOriginalElements;
    if (!original) return @[];
    CGFloat gap=CGGap(layout);
    if (gap<1) return original(layout,sel,rect);
    CGFloat from=CGAnchor(layout);
    NSArray *normal=original(layout,sel,rect) ?: @[];
    NSArray *shifted=original(layout,sel,CGRectOffset(rect,0,-gap)) ?: @[];
    NSMutableArray *result=[NSMutableArray array];
    NSMutableSet *seen=[NSMutableSet set];
    for (NSArray *group in @[normal,shifted]) for (UICollectionViewLayoutAttributes *attr in group) {
        if (![attr isKindOfClass:UICollectionViewLayoutAttributes.class]) continue;
        UICollectionViewLayoutAttributes *copy=CGShiftAttr(attr,from,gap);
        if (!CGRectIntersectsRect(copy.frame,rect)) continue;
        NSString *key=[NSString stringWithFormat:@"%ld:%@:%@",
            (long)copy.representedElementCategory,copy.representedElementKind?:@"",
            copy.indexPath?:[NSIndexPath indexPathForItem:0 inSection:0]];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        [result addObject:copy];
    }
    return result;
}
static UICollectionViewLayoutAttributes *
CGPinnedItem(UICollectionViewLayout *layout,SEL sel,NSIndexPath *index) {
    UICollectionViewLayoutAttributes *(*original)(id,SEL,id)=(void *)sOriginalItem;
    return original?CGShiftAttr(original(layout,sel,index),CGAnchor(layout),CGGap(layout)):nil;
}
static UICollectionViewLayoutAttributes *
CGPinnedSupplementary(UICollectionViewLayout *layout,SEL sel,NSString *kind,NSIndexPath *index) {
    UICollectionViewLayoutAttributes *(*original)(id,SEL,id,id)=(void *)sOriginalSupplementary;
    return original?CGShiftAttr(original(layout,sel,kind,index),CGAnchor(layout),CGGap(layout)):nil;
}
static CGSize CGPinnedContentSize(UICollectionViewLayout *layout,SEL sel) {
    CGSize (*original)(id,SEL)=(void *)sOriginalSize;
    CGSize size=original?original(layout,sel):CGSizeZero;
    size.height+=CGGap(layout);
    return size;
}
static BOOL CGHookLayoutClass(Class cls,SEL selector,IMP newIMP,IMP *original) {
    Method old=class_getInstanceMethod(cls,selector);
    if (!old) return NO;
    *original=method_getImplementation(old);
    if (!*original || *original==newIMP) return NO;
    class_replaceMethod(cls,selector,newIMP,method_getTypeEncoding(old));
    return YES;
}
BOOL CGPinSetLayoutSpace(UICollectionView *collection,CGFloat anchor,CGFloat height) {
    UICollectionViewLayout *layout=collection.collectionViewLayout;
    if (!layout) return NO;
    Class cls=object_getClass(layout);
    if (!sHookedLayoutClass) {
        // Hook this concrete layout class once. Other instances are unchanged
        // because the callbacks test our per-instance associated gap.
        if (!CGHookLayoutClass(cls,@selector(layoutAttributesForElementsInRect:),
                               (IMP)CGPinnedElements,&sOriginalElements) ||
            !CGHookLayoutClass(cls,@selector(collectionViewContentSize),
                               (IMP)CGPinnedContentSize,&sOriginalSize))
            return NO;
        // These methods may be inherited/optional depending on layout type.
        CGHookLayoutClass(cls,@selector(layoutAttributesForItemAtIndexPath:),
                          (IMP)CGPinnedItem,&sOriginalItem);
        CGHookLayoutClass(cls,@selector(layoutAttributesForSupplementaryViewOfKind:atIndexPath:),
                          (IMP)CGPinnedSupplementary,&sOriginalSupplementary);
        sHookedLayoutClass=cls;
    }
    if (cls!=sHookedLayoutClass) return NO;
    NSNumber *oldGap=objc_getAssociatedObject(layout,&kPinGap);
    NSNumber *oldFrom=objc_getAssociatedObject(layout,&kPinFrom);
    CGFloat newGap=MAX(0,height);
    if (oldGap && oldFrom && fabs(oldGap.doubleValue-newGap)<0.5 &&
        fabs(oldFrom.doubleValue-anchor)<0.5) return YES;
    objc_setAssociatedObject(layout,&kPinGap,@(newGap),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(layout,&kPinFrom,@(anchor),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [layout invalidateLayout];
    return YES;
}
