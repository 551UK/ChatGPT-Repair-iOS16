#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString * const CGRURLFixLogName = @"ChatGPTRepairURLFixTest.log";
static NSUInteger gCGRURLFixRewriteCount = 0;

static NSString *CGRURLFixLogPath(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject;
    if (!documents.length) return nil;
    return [documents stringByAppendingPathComponent:CGRURLFixLogName];
}

static void CGRURLFixLog(NSString *line) {
    if (!line.length) return;
    NSString *path = CGRURLFixLogPath();
    if (!path.length) return;
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    @synchronized([NSFileHandle class]) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [data writeToFile:path atomically:YES];
            return;
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) return;
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

static NSArray<NSDictionary *> *CGRURLTokenMatches(NSString *string) {
    if (!string.length) return @[];

    NSString *prefix = @"\uE200url\uE202";
    NSString *separator = @"\uE202";
    NSString *suffix = @"\uE201";

    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    NSUInteger cursor = 0;
    while (cursor < string.length) {
        NSRange search = NSMakeRange(cursor, string.length - cursor);
        NSRange start = [string rangeOfString:prefix options:0 range:search];
        if (start.location == NSNotFound) break;

        NSUInteger labelStart = NSMaxRange(start);
        if (labelStart >= string.length) break;

        NSRange separatorSearch = NSMakeRange(labelStart, string.length - labelStart);
        NSRange middle = [string rangeOfString:separator options:0 range:separatorSearch];
        if (middle.location == NSNotFound) break;

        NSUInteger urlStart = NSMaxRange(middle);
        if (urlStart >= string.length) break;

        NSRange suffixSearch = NSMakeRange(urlStart, string.length - urlStart);
        NSRange end = [string rangeOfString:suffix options:0 range:suffixSearch];
        if (end.location == NSNotFound) break;

        NSRange whole = NSMakeRange(start.location, NSMaxRange(end) - start.location);
        NSString *label = [string substringWithRange:NSMakeRange(labelStart, middle.location - labelStart)];
        NSString *urlString = [string substringWithRange:NSMakeRange(urlStart, end.location - urlStart)];
        NSURL *url = [NSURL URLWithString:urlString];

        BOOL valid = url &&
            ([[url.scheme lowercaseString] isEqualToString:@"https"] ||
             [[url.scheme lowercaseString] isEqualToString:@"http"]);

        if (valid) {
            [matches addObject:@{
                @"range": [NSValue valueWithRange:whole],
                @"label": label.length ? label : urlString,
                @"url": url
            }];
        }

        cursor = NSMaxRange(end);
    }
    return matches;
}

static NSString *CGRURLFixPlainString(NSString *input) {
    NSArray<NSDictionary *> *matches = CGRURLTokenMatches(input);
    if (!matches.count) return input;

    NSMutableString *out = [input mutableCopy];
    for (NSDictionary *match in [matches reverseObjectEnumerator]) {
        NSRange range = [match[@"range"] rangeValue];
        NSString *label = match[@"label"];
        NSURL *url = match[@"url"];
        NSString *replacement = [NSString stringWithFormat:@"%@ (%@)", label, url.absoluteString];
        [out replaceCharactersInRange:range withString:replacement];
    }

    gCGRURLFixRewriteCount += matches.count;
    CGRURLFixLog([NSString stringWithFormat:@"plain rewrite count=%lu total=%lu",
                  (unsigned long)matches.count, (unsigned long)gCGRURLFixRewriteCount]);
    return out;
}

static NSAttributedString *CGRURLFixAttributedString(NSAttributedString *input) {
    if (!input.length) return input;

    NSArray<NSDictionary *> *matches = CGRURLTokenMatches(input.string);
    if (!matches.count) return input;

    NSMutableAttributedString *out = [input mutableCopy];
    for (NSDictionary *match in [matches reverseObjectEnumerator]) {
        NSRange range = [match[@"range"] rangeValue];
        NSString *label = match[@"label"];
        NSURL *url = match[@"url"];

        NSDictionary *attrs = @{};
        if (range.location < out.length) {
            attrs = [out attributesAtIndex:range.location effectiveRange:NULL] ?: @{};
        }

        NSAttributedString *replacement =
            [[NSAttributedString alloc] initWithString:label attributes:attrs];

        [out replaceCharactersInRange:range withAttributedString:replacement];

        NSRange linkRange = NSMakeRange(range.location, label.length);
        if (NSMaxRange(linkRange) <= out.length) {
            [out addAttribute:NSLinkAttributeName value:url range:linkRange];
        }
    }

    gCGRURLFixRewriteCount += matches.count;
    CGRURLFixLog([NSString stringWithFormat:@"attributed rewrite count=%lu total=%lu",
                  (unsigned long)matches.count, (unsigned long)gCGRURLFixRewriteCount]);
    return out;
}

typedef void (*CGRSetAttributedTextIMP)(id, SEL, NSAttributedString *);
typedef void (*CGRSetTextIMP)(id, SEL, NSString *);

static CGRSetAttributedTextIMP gMarkdownOriginalSetAttributedText = NULL;
static CGRSetAttributedTextIMP gTextViewOriginalSetAttributedText = NULL;
static CGRSetTextIMP gTextViewOriginalSetText = NULL;
static CGRSetAttributedTextIMP gLabelOriginalSetAttributedText = NULL;
static CGRSetTextIMP gLabelOriginalSetText = NULL;

static void CGRMarkdownSetAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    NSAttributedString *fixed = CGRURLFixAttributedString(text);
    if (gMarkdownOriginalSetAttributedText) {
        gMarkdownOriginalSetAttributedText(self, _cmd, fixed);
    }
}

static void CGRTextViewSetAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    NSAttributedString *fixed = CGRURLFixAttributedString(text);
    if (gTextViewOriginalSetAttributedText) {
        gTextViewOriginalSetAttributedText(self, _cmd, fixed);
    }
}

static void CGRTextViewSetText(id self, SEL _cmd, NSString *text) {
    NSString *fixed = CGRURLFixPlainString(text);
    if (gTextViewOriginalSetText) {
        gTextViewOriginalSetText(self, _cmd, fixed);
    }
}

static void CGRLabelSetAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    NSAttributedString *fixed = CGRURLFixAttributedString(text);
    if (gLabelOriginalSetAttributedText) {
        gLabelOriginalSetAttributedText(self, _cmd, fixed);
    }
}

static void CGRLabelSetText(id self, SEL _cmd, NSString *text) {
    NSString *fixed = CGRURLFixPlainString(text);
    if (gLabelOriginalSetText) {
        gLabelOriginalSetText(self, _cmd, fixed);
    }
}

static IMP CGRInstallClassMethodHook(Class cls, SEL selector, IMP replacement, IMP *storedOriginal) {
    if (!cls || !selector || !replacement || !storedOriginal) return NULL;

    Method inheritedOrOwn = class_getInstanceMethod(cls, selector);
    if (!inheritedOrOwn) return NULL;

    IMP original = method_getImplementation(inheritedOrOwn);
    const char *types = method_getTypeEncoding(inheritedOrOwn);
    *storedOriginal = original;

    if (class_addMethod(cls, selector, replacement, types)) {
        return original;
    }

    Method own = class_getInstanceMethod(cls, selector);
    if (!own) return NULL;
    method_setImplementation(own, replacement);
    return original;
}

__attribute__((constructor))
static void CGRURLFixStart(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;

        CGRURLFixLog(@"=== ChatGPTRepair URL fix1 test launch ===");

        Class markdownTextView = NSClassFromString(@"OAIMarkdown.MarkdownTextView");
        if (!markdownTextView) {
            markdownTextView = NSClassFromString(@"_TtC11OAIMarkdown16MarkdownTextView");
        }

        BOOL markdownHook = NO;
        if (markdownTextView) {
            markdownHook = CGRInstallClassMethodHook(
                markdownTextView,
                @selector(setAttributedText:),
                (IMP)CGRMarkdownSetAttributedText,
                (IMP *)&gMarkdownOriginalSetAttributedText
            ) != NULL;
        }

        BOOL textViewAttributedHook = CGRInstallClassMethodHook(
            [UITextView class],
            @selector(setAttributedText:),
            (IMP)CGRTextViewSetAttributedText,
            (IMP *)&gTextViewOriginalSetAttributedText
        ) != NULL;

        BOOL textViewTextHook = CGRInstallClassMethodHook(
            [UITextView class],
            @selector(setText:),
            (IMP)CGRTextViewSetText,
            (IMP *)&gTextViewOriginalSetText
        ) != NULL;

        BOOL labelAttributedHook = CGRInstallClassMethodHook(
            [UILabel class],
            @selector(setAttributedText:),
            (IMP)CGRLabelSetAttributedText,
            (IMP *)&gLabelOriginalSetAttributedText
        ) != NULL;

        BOOL labelTextHook = CGRInstallClassMethodHook(
            [UILabel class],
            @selector(setText:),
            (IMP)CGRLabelSetText,
            (IMP *)&gLabelOriginalSetText
        ) != NULL;

        CGRURLFixLog([NSString stringWithFormat:
            @"hooks markdown=%d textViewAttributed=%d textViewText=%d labelAttributed=%d labelText=%d class=%@",
            markdownHook, textViewAttributedHook, textViewTextHook,
            labelAttributedHook, labelTextHook,
            markdownTextView ? NSStringFromClass(markdownTextView) : @"nil"]);
    }
}
