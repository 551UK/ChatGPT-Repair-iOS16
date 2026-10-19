#import "RichMarkupCompat.h"
#import <Foundation/Foundation.h>

// The 2024 client doesn't know 2026 rich-layout tags. Degrade only recognised
// rich response fragments; leave ordinary HTML, code and old link tokens alone.
static NSRegularExpression *CGRRegex(NSString *pattern, NSRegularExpressionOptions options) {
    return [NSRegularExpression regularExpressionWithPattern:pattern options:options error:NULL];
}

static NSString *CGRReplace(NSString *input, NSString *pattern,
                            NSRegularExpressionOptions options,
                            NSString *(^transform)(NSTextCheckingResult *, NSString *)) {
    NSRegularExpression *regex=CGRRegex(pattern,options);
    if (!regex) return input;
    NSArray<NSTextCheckingResult *> *matches=
        [regex matchesInString:input options:0 range:NSMakeRange(0,input.length)];
    if (!matches.count) return input;
    NSMutableString *output=[input mutableCopy];
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        NSString *replacement=transform(match,input);
        if (replacement) [output replaceCharactersInRange:match.range withString:replacement];
    }
    return output;
}

static NSString *CGRGroup(NSTextCheckingResult *match, NSUInteger group, NSString *input) {
    if (match.numberOfRanges<=group) return nil;
    NSRange range=[match rangeAtIndex:group];
    return range.location!=NSNotFound && NSMaxRange(range)<=input.length
        ? [input substringWithRange:range] : nil;
}

static NSString *CGRAttribute(NSString *attributes, NSString *key) {
    NSString *pattern=[NSString stringWithFormat:@"(?:^|\\s)%@\\s*=\\s*([\"'])(.*?)\\1",key];
    NSRegularExpression *regex=CGRRegex(pattern,NSRegularExpressionDotMatchesLineSeparators);
    NSTextCheckingResult *match=[regex firstMatchInString:attributes options:0
                                                  range:NSMakeRange(0,attributes.length)];
    NSString *value=match?CGRGroup(match,2,attributes):nil;
    // Common XML/HTML escaping in literal DIL attributes.
    return [[[[value stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"]
        stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""]
        stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"]
        stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
}

static NSString *CGRTrim(NSString *text) {
    return [text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *CGRSafeRichLink(NSString *label, NSString *urlString) {
    NSURL *url=[NSURL URLWithString:urlString ?: @""];
    NSString *scheme=url.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) ||
        !url.host.length || [urlString containsString:@"\uE201"] ||
        [label containsString:@"\uE202"] || [label containsString:@"\uE201"])
        return label.length?label:@"[link unavailable]";
    if (!label.length) label=@"Open link";
    // Existing ZZChatGPTLinkFix translates this token to a tappable URL.
    return [NSString stringWithFormat:@"\uE200url\uE202%@\uE202%@\uE201",
            label,url.absoluteString];
}

static NSString *CGRFriendlyPlaceholder(NSTextCheckingResult *match, NSString *original) {
    NSString *field=CGRGroup(match,1,original);
    if ([field isEqualToString:@"displayed_price"] ||
        [field isEqualToString:@"price"]) return @"[price unavailable]";
    if ([field isEqualToString:@"merchant"]) return @"[retailer unavailable]";
    return @"[product details unavailable]";
}

NSString *CGRLegacyReadableRichMarkup(NSString *original) {
    if (![original isKindOfClass:NSString.class] || !original.length) return original;
    // Both a supported layout component and an image/link/entity component
    // must be present, so an ordinary code sample isn't silently rewritten.
    BOOL hasLayout=[original containsString:@"<row "] ||
                   [original containsString:@"<box "] ||
                   [original containsString:@"<col "] ||
                   [original containsString:@"<grid "] ||
                   [original containsString:@"<text "] ||
                   [original containsString:@"<row>"] ||
                   [original containsString:@"<box>"];
    BOOL hasImage=[original containsString:@"<AsyncImage "];
    BOOL hasStructuredLink=[original containsString:@"<Link "] &&
                           [original containsString:@"<text "] &&
                           [original containsString:@"<box "];
    BOOL hasBinding=[original containsString:@"{turn"] &&
                    [original containsString:@"product"];
    BOOL hasGenUIButton=[original containsString:@"<button"] &&
                        [original containsString:@"GenUI.openUrl("];
    if (!((hasLayout && (hasImage || hasStructuredLink)) || hasBinding || hasGenUIButton))
        return original;

    NSString *output=original;
    // Strip Markdown code fences only around unsupported rich layout blocks.
    // Do not touch independent code blocks in the same message.
    output=CGRReplace(output,@"```(?:jsx|tsx|xml|html)?[ \\t]*\\n([\\s\\S]*?)\\n?```",
                      NSRegularExpressionCaseInsensitive,
                      ^NSString *(NSTextCheckingResult *match,NSString *text) {
        NSString *body=CGRGroup(match,1,text);
        if ([body containsString:@"<AsyncImage"] ||
            [body containsString:@"<Link "] ||
            [body containsString:@"</box"] ||
            [body containsString:@"</row"])
            return body;
        return CGRGroup(match,0,text);
    });
    // Modern response buttons degrade to the same rich URL token understood
    // by the existing LinkFix. Handle both paired and legacy-unclosed forms.
    output=CGRReplace(output,
                      @"<button\\b[^>]*onClick=\\{\\(\\)\\s*=>\\s*GenUI\\.openUrl\\(([\\"\'])(https?://[^\\"\']+)\\1\\)\\}[^>]*>(.*?)</button>",
                      NSRegularExpressionDotMatchesLineSeparators,
                      ^NSString *(NSTextCheckingResult *match,NSString *text) {
        NSString *url=CGRGroup(match,2,text);
        NSString *label=CGRTrim(CGRGroup(match,3,text) ?: @"");
        return CGRSafeRichLink(label.length?label:@"Open link",url);
    });
    output=CGRReplace(output,
                      @"<button\\b[^>]*onClick=\\{\\(\\)\\s*=>\\s*GenUI\\.openUrl\\(([\\"\'])(https?://[^\\"\']+)\\1\\)\\}[^>]*>[ \\t\\r\\n]*([^\\r\\n<]+)",
                      0,^NSString *(NSTextCheckingResult *match,NSString *text) {
        NSString *url=CGRGroup(match,2,text);
        NSString *label=CGRTrim(CGRGroup(match,3,text) ?: @"");
        return CGRSafeRichLink(label.length?label:@"Open link",url);
    });
    output=CGRReplace(output,@"<badge\\b[^>]*>(.*?)</badge>",
                      NSRegularExpressionDotMatchesLineSeparators,
                      ^NSString *(NSTextCheckingResult *match,NSString *text) {
        return CGRTrim(CGRGroup(match,1,text) ?: @"");
    });

    // Process links before stripping their enclosing layout wrappers.
    output=CGRReplace(output,@"<Link\\b([^>]*)>(.*?)</Link>",
                      NSRegularExpressionDotMatchesLineSeparators,
                      ^NSString *(NSTextCheckingResult *match,NSString *text) {
        NSString *attrs=CGRGroup(match,1,text);
        NSString *label=CGRTrim(CGRGroup(match,2,text) ?: @"");
        if (!label.length) label=CGRAttribute(attrs,@"title");
        return CGRSafeRichLink(label,CGRAttribute(attrs,@"url"));
    });
    output=CGRReplace(output,@"<Link\\b([^>]*?)/>",
                      NSRegularExpressionDotMatchesLineSeparators,
                      ^NSString *(NSTextCheckingResult *match,NSString *text) {
        NSString *attrs=CGRGroup(match,1,text);
        NSString *label=CGRAttribute(attrs,@"title") ?: @"Open link";
        return CGRSafeRichLink(label,CGRAttribute(attrs,@"url"));
    });

    // The old app can't fetch/display an AsyncImage by its text query.
    // Keep a helpful description rather than printing its raw JSX.
    output=CGRReplace(output,@"<AsyncImage\\b([^>]*?)/>",
                      NSRegularExpressionDotMatchesLineSeparators,
                      ^NSString *(NSTextCheckingResult *match,NSString *text) {
        NSString *attrs=CGRGroup(match,1,text);
        NSString *description=CGRAttribute(attrs,@"alt") ?: CGRAttribute(attrs,@"query");
        return description.length?[NSString stringWithFormat:@"[Image: %@]",description]:@"[Image]";
    });
    output=CGRReplace(output,@"<Entity\\b([^>]*?)/>",
                      NSRegularExpressionDotMatchesLineSeparators,
                      ^NSString *(NSTextCheckingResult *match,NSString *text) {
        NSString *attrs=CGRGroup(match,1,text);
        return CGRAttribute(attrs,@"value") ?: @"";
    });

    // Remove only allowlisted structural tags, not arbitrary HTML/markup.
    output=CGRReplace(output,
                      @"</?(?:row|box|col|grid|grid-item|flow|flow-item|text|title|caption|card|divider|spacer|list|list-item|table|table-row|table-cell|badge|button)\\b[^>]*>",
                      NSRegularExpressionDotMatchesLineSeparators,
                      ^NSString *(NSTextCheckingResult *match,NSString *text) {
        NSString *tag=CGRGroup(match,0,text);
        if ([tag hasPrefix:@"</row"] || [tag hasPrefix:@"</box"] ||
            [tag hasPrefix:@"</col"] || [tag hasPrefix:@"<divider"])
            return @"\n";
        return @"";
    });

    // Product binding references are resolved by modern clients, not supplied
    // as prices in old-client JSON. Never make up a value.
    output=CGRReplace(output,
                      @"\\{turn[0-9]+product[0-9]+\\.(displayed_price|price|merchant|title)\\}",
                      0,^NSString *(NSTextCheckingResult *match,NSString *text) {
        return CGRFriendlyPlaceholder(match,text);
    });
    output=CGRReplace(output,@"\n[ \t]*\n[ \t]*\n+",0,
                      ^NSString *(NSTextCheckingResult *match,NSString *text) {
        return @"\n\n";
    });
    return output;
}
