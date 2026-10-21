// ChatGPTRepair: Degrade unsupported rich layouts into readable legacy markup.
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


static NSString *CGRReplaceDownloadIconRows(NSString *input) {
    if (![input containsString:@"<row"] ||
        ![input containsString:@"<icon"] ||
        !([input containsString:@"name=\"download\""] ||
          [input containsString:@"name='download'"]) ||
        ![input containsString:@"]("])
        return input;

    // Match only the known modern download-row shape. Converting the whole
    // row means the legacy Markdown renderer never sees raw JSX or the raw URL.
    NSString *pattern=@"<row\\b[^>]*>\\s*<icon\\b[^>]*\\bname\\s*=\\s*[\"']download[\"'][^>]*/>\\s*(?:\\*\\*)?\\[([^\\]\\n]+)\\]\\((https?://[^\\s\\)]+)\\)(?:\\*\\*)?\\s*</row>";
    return CGRReplace(input,pattern,
                      NSRegularExpressionCaseInsensitive |
                      NSRegularExpressionDotMatchesLineSeparators,
                      ^NSString *(NSTextCheckingResult *match,NSString *text) {
        NSString *label=CGRTrim(CGRGroup(match,1,text) ?: @"");
        NSString *url=CGRGroup(match,2,text);
        if (!label.length) label=@"Download";
        NSString *display=[label hasPrefix:@"↓"] ? label
            : [@"↓ " stringByAppendingString:label];
        return CGRSafeRichLink(display,url);
    });
}


static NSString *CGRReplaceGenUIButtons(NSString *input) {
    if (![input containsString:@"<button"] || ![input containsString:@"GenUI.openUrl("])
        return input;

    NSMutableString *output=[input mutableCopy];
    NSUInteger cursor=0;
    NSCharacterSet *ws=[NSCharacterSet whitespaceAndNewlineCharacterSet];

    while (cursor<output.length) {
        NSRange start=[output rangeOfString:@"<button" options:0
                                     range:NSMakeRange(cursor,output.length-cursor)];
        if (start.location==NSNotFound) break;

        // Do not search for the first '>' here: the JavaScript arrow itself is
        // '=>'. Find GenUI.openUrl first, parse its quoted URL, then locate the
        // real tag terminator after that call.
        NSUInteger searchLength=MIN((NSUInteger)4096,output.length-start.location);
        NSRange call=[output rangeOfString:@"GenUI.openUrl(" options:0
                                    range:NSMakeRange(start.location,searchLength)];
        if (call.location==NSNotFound) {
            cursor=NSMaxRange(start);
            continue;
        }

        NSUInteger pos=NSMaxRange(call);
        while (pos<output.length && [ws characterIsMember:[output characterAtIndex:pos]]) pos++;
        if (pos>=output.length) break;
        unichar quote=[output characterAtIndex:pos];
        if (quote!='"' && quote!='\'') {
            cursor=NSMaxRange(call);
            continue;
        }

        NSUInteger urlStart=++pos;
        while (pos<output.length && [output characterAtIndex:pos]!=quote) pos++;
        if (pos<=urlStart || pos>=output.length) {
            cursor=NSMaxRange(call);
            continue;
        }
        NSString *url=[output substringWithRange:NSMakeRange(urlStart,pos-urlStart)];

        NSRange tagEnd=[output rangeOfString:@">" options:0
                                      range:NSMakeRange(pos,output.length-pos)];
        if (tagEnd.location==NSNotFound) break;

        NSUInteger labelStart=NSMaxRange(tagEnd);
        while (labelStart<output.length &&
               [ws characterIsMember:[output characterAtIndex:labelStart]]) labelStart++;

        NSRange closing=[output rangeOfString:@"</button>" options:0
                                       range:NSMakeRange(labelStart,output.length-labelStart)];
        NSUInteger wholeEnd=0;
        NSString *label=nil;
        if (closing.location!=NSNotFound && closing.location-labelStart<4096) {
            label=[output substringWithRange:NSMakeRange(labelStart,closing.location-labelStart)];
            wholeEnd=NSMaxRange(closing);
        } else {
            NSRange newline=[output rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                                                    options:0
                                                      range:NSMakeRange(labelStart,output.length-labelStart)];
            NSUInteger labelEnd=newline.location==NSNotFound?output.length:newline.location;
            label=[output substringWithRange:NSMakeRange(labelStart,labelEnd-labelStart)];
            wholeEnd=labelEnd;
        }

        label=CGRTrim(label ?: @"");
        NSString *replacement=CGRSafeRichLink(label.length?label:@"Open link",url);
        NSRange whole=NSMakeRange(start.location,wholeEnd-start.location);
        [output replaceCharactersInRange:whole withString:replacement];
        cursor=start.location+replacement.length;
    }
    return output;
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
    // Newer responses can also send a compact download row made from a
    // structural <row>, a download <icon>, and an ordinary Markdown link.
    // ChatGPT 1.2024.200 prints that component literally unless we unwrap it.
    BOOL hasDownloadIcon=[original containsString:@"<icon"] &&
        ([original containsString:@"name=\"download\""] ||
         [original containsString:@"name='download'"]);
    BOOL hasMarkdownHTTPLink=([original containsString:@"](https://"] ||
                              [original containsString:@"](http://"]);
    BOOL hasIconMarkdownLink=hasDownloadIcon && hasMarkdownHTTPLink &&
                             [original containsString:@"</row>"];
    if (!((hasLayout && (hasImage || hasStructuredLink || hasIconMarkdownLink)) ||
          hasBinding || hasGenUIButton))
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
    // Collapse the known icon + Markdown-link download row to one
    // tappable legacy link before stripping any remaining layout tags.
    output=CGRReplaceDownloadIconRows(output);

    // Modern response buttons degrade to the same rich URL token understood
    // by the existing LinkFix. Parse rather than regex the nested arrow-call syntax.
    output=CGRReplaceGenUIButtons(output);

    // The old renderer has no equivalent for modern inline icon components.
    // Preserve the meaning of the download icon without leaking raw JSX.
    output=CGRReplace(output,@"<icon\\b([^>]*?)/>",
                      NSRegularExpressionDotMatchesLineSeparators,
                      ^NSString *(NSTextCheckingResult *match,NSString *text) {
        NSString *attrs=CGRGroup(match,1,text);
        NSString *name=[CGRAttribute(attrs,@"name") lowercaseString];
        return [name isEqualToString:@"download"]?@"↓ ":@"";
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
