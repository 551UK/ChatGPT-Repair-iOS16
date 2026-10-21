// ChatGPTRepair: make legacy ChatGPT links and download labels tappable.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static const void *kCGRLinkTapKey = &kCGRLinkTapKey;
static const void *kCGRProcessingKey = &kCGRProcessingKey;

@interface UILabel (CGRLinkFix)
- (void)cgr_linkfix_setText:(NSString *)text;
- (void)cgr_linkfix_setAttributedText:(NSAttributedString *)text;
@end

@interface UITextView (CGRLinkFix)
- (void)cgr_linkfix_setText:(NSString *)text;
- (void)cgr_linkfix_setAttributedText:(NSAttributedString *)text;
@end

static BOOL CGRIsProcessing(id obj) {
    return [objc_getAssociatedObject(obj, kCGRProcessingKey) boolValue];
}

static void CGRSetProcessing(id obj, BOOL value) {
    objc_setAssociatedObject(obj, kCGRProcessingKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSURL *CGRURLFromLinkValue(id value) {
    if ([value isKindOfClass:[NSURL class]]) return value;
    if ([value isKindOfClass:[NSString class]]) return [NSURL URLWithString:value];
    return nil;
}

static NSMutableAttributedString *CGRLinkifyAttributedString(NSAttributedString *input, BOOL *changedOut, BOOL *hasLinksOut) {
    if (!input) {
        if (changedOut) *changedOut = NO;
        if (hasLinksOut) *hasLinksOut = NO;
        return nil;
    }

    NSMutableAttributedString *result = [input mutableCopy];
    BOOL changed = NO;
    __block BOOL hasLinks = NO;

    NSString *richPattern = @"\uE200url\uE202(.*?)\uE202(https?://[^\uE201]+)\uE201";
    NSRegularExpression *richRegex = [NSRegularExpression regularExpressionWithPattern:richPattern
                                                                               options:NSRegularExpressionDotMatchesLineSeparators
                                                                                 error:nil];
    NSArray<NSTextCheckingResult *> *richMatches =
        [richRegex matchesInString:result.string options:0 range:NSMakeRange(0, result.length)];

    for (NSTextCheckingResult *match in [richMatches reverseObjectEnumerator]) {
        if (match.numberOfRanges < 3) continue;

        NSRange whole = [match rangeAtIndex:0];
        NSRange labelRange = [match rangeAtIndex:1];
        NSRange urlRange = [match rangeAtIndex:2];
        if (whole.location == NSNotFound || urlRange.location == NSNotFound) continue;

        NSString *label = labelRange.location != NSNotFound ? [result.string substringWithRange:labelRange] : @"";
        NSString *urlString = [result.string substringWithRange:urlRange];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) continue;
        if (label.length == 0) label = urlString;

        NSDictionary *baseAttributes = @{};
        if (whole.location < result.length) {
            baseAttributes = [result attributesAtIndex:whole.location effectiveRange:NULL] ?: @{};
        }

        NSMutableDictionary *attrs = [baseAttributes mutableCopy];
        attrs[NSLinkAttributeName] = url;
        NSAttributedString *replacement = [[NSAttributedString alloc] initWithString:label attributes:attrs];
        [result replaceCharactersInRange:whole withAttributedString:replacement];
        changed = YES;
        hasLinks = YES;
    }

    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
    NSArray<NSTextCheckingResult *> *matches =
        [detector matchesInString:result.string options:0 range:NSMakeRange(0, result.length)];
    for (NSTextCheckingResult *match in matches) {
        if (match.resultType != NSTextCheckingTypeLink || !match.URL) continue;
        if (match.range.location == NSNotFound || NSMaxRange(match.range) > result.length) continue;
        [result addAttribute:NSLinkAttributeName value:match.URL range:match.range];
        hasLinks = YES;
        changed = YES;
    }

    [result enumerateAttribute:NSLinkAttributeName
                       inRange:NSMakeRange(0, result.length)
                       options:0
                    usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value) hasLinks = YES;
    }];

    if (changedOut) *changedOut = changed;
    if (hasLinksOut) *hasLinksOut = hasLinks;
    return result;
}

static NSUInteger CGRCharacterIndexForLabelTap(UILabel *label, CGPoint point) {
    NSAttributedString *attributedText = label.attributedText;
    if (attributedText.length == 0) return NSNotFound;

    NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:attributedText];
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithSize:label.bounds.size];

    textContainer.lineFragmentPadding = 0.0;
    textContainer.maximumNumberOfLines = label.numberOfLines;
    textContainer.lineBreakMode = label.lineBreakMode;

    [layoutManager addTextContainer:textContainer];
    [textStorage addLayoutManager:layoutManager];

    NSRange glyphRange = [layoutManager glyphRangeForTextContainer:textContainer];
    CGRect usedRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:textContainer];

    CGFloat xOffset = 0.0;
    switch (label.textAlignment) {
        case NSTextAlignmentCenter:
            xOffset = (label.bounds.size.width - usedRect.size.width) * 0.5 - usedRect.origin.x;
            break;
        case NSTextAlignmentRight:
            xOffset = label.bounds.size.width - usedRect.size.width - usedRect.origin.x;
            break;
        default:
            xOffset = -usedRect.origin.x;
            break;
    }

    CGFloat yOffset = (label.bounds.size.height - usedRect.size.height) * 0.5 - usedRect.origin.y;
    CGPoint containerPoint = CGPointMake(point.x - xOffset, point.y - yOffset);

    CGFloat fraction = 0.0;
    NSUInteger glyphIndex = [layoutManager glyphIndexForPoint:containerPoint
                                             inTextContainer:textContainer
                              fractionOfDistanceThroughGlyph:&fraction];
    if (glyphIndex >= layoutManager.numberOfGlyphs) return NSNotFound;

    NSUInteger charIndex = [layoutManager characterIndexForGlyphAtIndex:glyphIndex];
    if (charIndex >= attributedText.length) return NSNotFound;
    return charIndex;
}

static void CGROpenLink(NSURL *url) {
    if (!url) return;
    NSString *scheme = [url.scheme lowercaseString];
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return;

    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [app openURL:url options:@{} completionHandler:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [app openURL:url];
#pragma clang diagnostic pop
    }
}

@interface CGRLabelLinkTapTarget : NSObject
@end

@implementation CGRLabelLinkTapTarget
- (void)cgr_handleLabelLinkTap:(UITapGestureRecognizer *)gesture {
    UILabel *label = (UILabel *)gesture.view;
    if (![label isKindOfClass:[UILabel class]]) return;

    NSUInteger index = CGRCharacterIndexForLabelTap(label, [gesture locationInView:label]);
    if (index == NSNotFound || index >= label.attributedText.length) return;

    id value = [label.attributedText attribute:NSLinkAttributeName atIndex:index effectiveRange:NULL];
    CGROpenLink(CGRURLFromLinkValue(value));
}
@end

static CGRLabelLinkTapTarget *CGRSharedTapTarget(void) {
    static CGRLabelLinkTapTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [CGRLabelLinkTapTarget new];
    });
    return target;
}

static void CGRConfigureLabel(UILabel *label) {
    if (!label || CGRIsProcessing(label)) return;
    NSAttributedString *current = label.attributedText;
    if (current.length == 0) return;

    BOOL changed = NO;
    BOOL hasLinks = NO;
    NSMutableAttributedString *linked = CGRLinkifyAttributedString(current, &changed, &hasLinks);
    if (!hasLinks) return;

    CGRSetProcessing(label, YES);
    if (changed) {
        [label cgr_linkfix_setAttributedText:linked];
    }
    label.userInteractionEnabled = YES;

    UITapGestureRecognizer *tap = objc_getAssociatedObject(label, kCGRLinkTapKey);
    if (!tap) {
        tap = [[UITapGestureRecognizer alloc] initWithTarget:CGRSharedTapTarget()
                                                     action:@selector(cgr_handleLabelLinkTap:)];
        tap.cancelsTouchesInView = NO;
        [label addGestureRecognizer:tap];
        objc_setAssociatedObject(label, kCGRLinkTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRSetProcessing(label, NO);
}

static void CGRConfigureTextView(UITextView *textView) {
    if (!textView || textView.editable || CGRIsProcessing(textView)) return;
    NSAttributedString *current = textView.attributedText;
    if (current.length == 0) return;

    BOOL changed = NO;
    BOOL hasLinks = NO;
    NSMutableAttributedString *linked = CGRLinkifyAttributedString(current, &changed, &hasLinks);
    if (!hasLinks) return;

    CGRSetProcessing(textView, YES);
    if (changed) {
        [textView cgr_linkfix_setAttributedText:linked];
    }
    textView.selectable = YES;
    CGRSetProcessing(textView, NO);
}

@implementation UILabel (CGRLinkFix)
- (void)cgr_linkfix_setText:(NSString *)text {
    [self cgr_linkfix_setText:text];
    CGRConfigureLabel(self);
}
- (void)cgr_linkfix_setAttributedText:(NSAttributedString *)text {
    [self cgr_linkfix_setAttributedText:text];
    CGRConfigureLabel(self);
}
@end

@implementation UITextView (CGRLinkFix)
- (void)cgr_linkfix_setText:(NSString *)text {
    [self cgr_linkfix_setText:text];
    CGRConfigureTextView(self);
}
- (void)cgr_linkfix_setAttributedText:(NSAttributedString *)text {
    [self cgr_linkfix_setAttributedText:text];
    CGRConfigureTextView(self);
}
@end

static void CGRSwizzle(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor))
static void CGRLinkFixInit(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;

        CGRSwizzle([UILabel class], @selector(setText:), @selector(cgr_linkfix_setText:));
        CGRSwizzle([UILabel class], @selector(setAttributedText:), @selector(cgr_linkfix_setAttributedText:));

        CGRSwizzle([UITextView class], @selector(setText:), @selector(cgr_linkfix_setText:));
        CGRSwizzle([UITextView class], @selector(setAttributedText:), @selector(cgr_linkfix_setAttributedText:));
    }
}
