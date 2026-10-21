// ChatGPTRepair: Prevent unrendered citation tokens appearing inside chat messages.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "CitationCompat.h"

static BOOL CGRIsMarkdownTextView(UITextView *view) {
    if (!view) return NO;
    NSString *name=NSStringFromClass(view.class);
    return [name containsString:@"OAIMarkdown"] ||
           [name containsString:@"CustomCopyingTextView"];
}

static BOOL CGRReplaceMarker(NSMutableString *text,
                             NSString *prefix,
                             NSString *fallback) {
    BOOL changed=NO;
    while (YES) {
        NSRange start=[text rangeOfString:prefix];
        if (start.location==NSNotFound) break;
        NSUInteger after=NSMaxRange(start);
        if (after>=text.length) break;
        NSRange end=[text rangeOfString:@"" options:0
                                 range:NSMakeRange(after,text.length-after)];
        if (end.location==NSNotFound) break;
        NSRange whole=NSMakeRange(start.location,NSMaxRange(end)-start.location);
        [text replaceCharactersInRange:whole withString:fallback];
        changed=YES;
    }
    return changed;
}

static NSString *CGRSanitizeRenderedCitationString(NSString *input) {
    if (![input isKindOfClass:NSString.class] || !input.length) return input;
    if ([input rangeOfString:@"cite"].location==NSNotFound &&
        [input rangeOfString:@"filecite"].location==NSNotFound)
        return input;

    NSMutableString *output=[input mutableCopy];
    CGRReplaceMarker(output,@"filecite",@"[file]");
    CGRReplaceMarker(output,@"cite",@"[source]");
    return output;
}

static NSURL *CGRURLFromAttributes(NSDictionary<NSAttributedStringKey,id> *attrs) {
    id direct=attrs[NSLinkAttributeName];
    if ([direct isKindOfClass:NSURL.class]) return direct;
    if ([direct isKindOfClass:NSString.class]) {
        NSURL *url=[NSURL URLWithString:direct];
        NSString *scheme=url.scheme.lowercaseString;
        if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) return url;
    }
    for (id value in attrs.allValues) {
        if ([value isKindOfClass:NSURL.class]) {
            NSURL *url=value;
            NSString *scheme=url.scheme.lowercaseString;
            if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) return url;
        }
        if ([value isKindOfClass:NSString.class] &&
            ([(NSString *)value hasPrefix:@"https://"] || [(NSString *)value hasPrefix:@"http://"]))
            return [NSURL URLWithString:value];
    }
    return nil;
}

static NSAttributedString *CGRSanitizeRenderedCitationAttributedString(NSAttributedString *input) {
    if (![input isKindOfClass:NSAttributedString.class] || !input.length) return input;
    NSString *plain=input.string;
    if ([plain rangeOfString:@"cite"].location==NSNotFound &&
        [plain rangeOfString:@"filecite"].location==NSNotFound)
        return input;

    NSMutableAttributedString *output=[input mutableCopy];
    NSArray<NSArray<NSString *> *> *rules=@[
        @[@"filecite",@"[file]"],
        @[@"cite",@"[source]"]
    ];
    for (NSArray<NSString *> *rule in rules) {
        NSString *prefix=rule[0], *fallback=rule[1];
        while (YES) {
            NSString *current=output.string;
            NSRange start=[current rangeOfString:prefix];
            if (start.location==NSNotFound) break;
            NSUInteger after=NSMaxRange(start);
            if (after>=current.length) break;
            NSRange end=[current rangeOfString:@"" options:0
                                         range:NSMakeRange(after,current.length-after)];
            if (end.location==NSNotFound) break;
            NSRange whole=NSMakeRange(start.location,NSMaxRange(end)-start.location);
            NSString *marker=[current substringWithRange:whole];

            NSDictionary *base=whole.location<output.length
                ?[output attributesAtIndex:whole.location effectiveRange:NULL]:@{};
            NSURL *url=CGRCitationPrimaryURLForMarker(marker) ?: CGRURLFromAttributes(base);
            NSMutableDictionary *attrs=[base mutableCopy] ?: [NSMutableDictionary dictionary];
            if (url) attrs[NSLinkAttributeName]=url;

            NSAttributedString *replacement=[[NSAttributedString alloc]
                initWithString:fallback attributes:attrs];
            [output replaceCharactersInRange:whole withAttributedString:replacement];
        }
    }
    return output;
}

@interface UITextView (CGRRendererCitationGuard)
- (void)cgr_guard_setText:(NSString *)text;
- (void)cgr_guard_setAttributedText:(NSAttributedString *)text;
@end

@implementation UITextView (CGRRendererCitationGuard)
- (void)cgr_guard_setText:(NSString *)text {
    if (CGRIsMarkdownTextView(self))
        text=CGRSanitizeRenderedCitationString(text);
    [self cgr_guard_setText:text];
}
- (void)cgr_guard_setAttributedText:(NSAttributedString *)text {
    if (CGRIsMarkdownTextView(self))
        text=CGRSanitizeRenderedCitationAttributedString(text);
    [self cgr_guard_setAttributedText:text];
}
@end

static void CGRGuardSwizzle(Class cls, SEL original, SEL replacement) {
    Method a=class_getInstanceMethod(cls,original);
    Method b=class_getInstanceMethod(cls,replacement);
    if (a && b) method_exchangeImplementations(a,b);
}

__attribute__((constructor)) static void CGRRendererCitationGuardBoot(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
        CGRGuardSwizzle(UITextView.class,@selector(setText:),@selector(cgr_guard_setText:));
        CGRGuardSwizzle(UITextView.class,@selector(setAttributedText:),@selector(cgr_guard_setAttributedText:));
    }
}
