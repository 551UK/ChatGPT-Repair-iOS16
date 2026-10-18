#import "CitationCompat.h"

static BOOL CGRIsCitationMarker(NSString *text) {
    // Only rewrite actual citation tokens. Normal rich URL tokens use the same
    // private-use framing and must be left untouched so LinkFix can preserve
    // their original user-facing label (for example "Download ... (.deb)").
    return [text hasPrefix:@"\uE200cite\uE202"] ||
           [text hasPrefix:@"\uE200filecite\uE202"];
}

static NSString *CGRFallbackForCitationMarker(NSString *text) {
    return [text hasPrefix:@"\uE200filecite\uE202"] ? @"[file]" : @"[source]";
}

static BOOL CGRReplaceUnresolvedMarker(NSMutableString *text,
                                       NSString *prefix,
                                       NSString *fallback) {
    BOOL changed=NO;
    while (YES) {
        NSRange start=[text rangeOfString:prefix];
        if (start.location==NSNotFound) break;
        NSUInteger after=NSMaxRange(start);
        if (after>=text.length) break;
        NSRange end=[text rangeOfString:@"\uE201" options:0
                                 range:NSMakeRange(after,text.length-after)];
        if (end.location==NSNotFound) break;
        NSRange whole=NSMakeRange(start.location,NSMaxRange(end)-start.location);
        [text replaceCharactersInRange:whole withString:fallback];
        changed=YES;
    }
    return changed;
}


static NSString *CGRProductLabelFromSelection(id selection) {
    if (![selection isKindOfClass:NSArray.class]) return nil;
    NSArray *array=selection;
    if (array.count<2 || ![array[1] isKindOfClass:NSString.class]) return nil;
    NSString *label=[array[1] stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return label.length?label:nil;
}

static NSString *CGRProductReplacement(NSString *kind, NSString *payload) {
    NSData *jsonData=[payload dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData.length) return [kind isEqualToString:@"products"]?@"[products]":@"[product]";
    id json=[NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];

    if ([kind isEqualToString:@"products"]) {
        NSArray *selections=[json isKindOfClass:NSDictionary.class] &&
            [json[@"selections"] isKindOfClass:NSArray.class] ? json[@"selections"] : nil;
        NSMutableArray<NSString *> *labels=[NSMutableArray array];
        for (id selection in selections) {
            NSString *label=CGRProductLabelFromSelection(selection);
            if (label.length && ![labels containsObject:label]) [labels addObject:label];
        }
        if (labels.count) return [labels componentsJoinedByString:@" • "];
        return @"[products]";
    }

    NSString *single=CGRProductLabelFromSelection(json);
    return single.length?single:@"[product]";
}

static BOOL CGRReplaceProductMarkers(NSMutableString *text, NSString *kind) {
    NSString *prefix=[NSString stringWithFormat:@"\uE200%@\uE202",kind];
    BOOL changed=NO;
    while (YES) {
        NSRange start=[text rangeOfString:prefix];
        if (start.location==NSNotFound) break;
        NSUInteger payloadStart=NSMaxRange(start);
        if (payloadStart>=text.length) break;
        NSRange end=[text rangeOfString:@"\uE201" options:0
                                 range:NSMakeRange(payloadStart,text.length-payloadStart)];
        if (end.location==NSNotFound) break;
        NSString *payload=[text substringWithRange:
            NSMakeRange(payloadStart,end.location-payloadStart)];
        NSString *replacement=CGRProductReplacement(kind,payload);
        NSRange whole=NSMakeRange(start.location,NSMaxRange(end)-start.location);
        [text replaceCharactersInRange:whole withString:replacement];
        changed=YES;
    }
    return changed;
}

static NSString *CGRSafeLabelForURL(NSURL *url) {
    NSString *host=url.host.lowercaseString ?: @"";
    if ([host hasPrefix:@"www."]) host=[host substringFromIndex:4];
    if (!host.length) return @"source";
    return host;
}

static void CGRAddURL(NSMutableArray<NSURL *> *urls, NSMutableSet<NSString *> *seen, id value) {
    NSString *raw=nil;
    if ([value isKindOfClass:NSString.class]) raw=value;
    else if ([value isKindOfClass:NSURL.class]) raw=[value absoluteString];
    if (!raw.length) return;
    NSURL *url=[NSURL URLWithString:raw];
    NSString *scheme=url.scheme.lowercaseString;
    if (!url || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return;
    NSString *key=url.absoluteString;
    if (!key.length || [seen containsObject:key]) return;
    [seen addObject:key];
    [urls addObject:url];
}

static NSArray<NSURL *> *CGRURLsForReference(NSDictionary *reference) {
    NSMutableArray<NSURL *> *urls=[NSMutableArray array];
    NSMutableSet<NSString *> *seen=[NSMutableSet set];

    id safe=reference[@"safe_urls"];
    if ([safe isKindOfClass:NSArray.class])
        for (id value in (NSArray *)safe) CGRAddURL(urls,seen,value);
    else CGRAddURL(urls,seen,safe);

    CGRAddURL(urls,seen,reference[@"url"]);

    // Older/newer server variants sometimes put the durable URL only in alt.
    NSString *alt=[reference[@"alt"] isKindOfClass:NSString.class]?reference[@"alt"]:nil;
    if (alt.length) {
        NSDataDetector *detector=[NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
        for (NSTextCheckingResult *match in [detector matchesInString:alt options:0 range:NSMakeRange(0,alt.length)]) {
            if (match.resultType==NSTextCheckingTypeLink) CGRAddURL(urls,seen,match.URL);
        }
    }
    return urls;
}

static NSString *CGRRichLinkToken(NSURL *url) {
    NSString *label=[NSString stringWithFormat:@"[%@]",CGRSafeLabelForURL(url)];
    // LinkFix.m already knows this modern rich URL token and turns it into
    // NSLinkAttributeName on the old UIKit renderer.
    return [NSString stringWithFormat:@"\uE200url\uE202%@\uE202%@\uE201",label,url.absoluteString];
}

static BOOL CGRRewriteMessage(NSMutableDictionary *message) {
    NSMutableDictionary *content=[message[@"content"] isKindOfClass:NSDictionary.class]
        ?[message[@"content"] mutableCopy]:nil;
    NSDictionary *metadata=[message[@"metadata"] isKindOfClass:NSDictionary.class]
        ?message[@"metadata"]:nil;
    NSArray *references=[metadata[@"content_references"] isKindOfClass:NSArray.class]
        ?metadata[@"content_references"]:nil;
    NSArray *parts=[content[@"parts"] isKindOfClass:NSArray.class]?content[@"parts"]:nil;
    if (!content || !parts.count) return NO;

    NSMutableArray *newParts=[parts mutableCopy];
    BOOL changed=NO;
    for (NSUInteger p=0;p<newParts.count;p++) {
        if (![newParts[p] isKindOfClass:NSString.class]) continue;
        NSString *original=newParts[p];
        NSMutableString *text=[original mutableCopy];

        for (id rawReference in references) {
            if (![rawReference isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *reference=rawReference;
            NSString *matched=[reference[@"matched_text"] isKindOfClass:NSString.class]
                ?reference[@"matched_text"]:nil;
            // Some source-footnote records use ordinary whitespace for
            // matched_text. Never perform a global replacement on those.
            if (!matched.length || !CGRIsCitationMarker(matched)) continue;
            if ([text rangeOfString:matched].location==NSNotFound) continue;

            NSArray<NSURL *> *urls=CGRURLsForReference(reference);
            NSString *replacement=nil;
            if (urls.count) {
                NSMutableArray<NSString *> *tokens=[NSMutableArray arrayWithCapacity:urls.count];
                for (NSURL *url in urls) [tokens addObject:CGRRichLinkToken(url)];
                replacement=[tokens componentsJoinedByString:@" "];
            } else {
                replacement=CGRFallbackForCitationMarker(matched);
            }
            [text replaceOccurrencesOfString:matched withString:replacement
                                    options:0 range:NSMakeRange(0,text.length)];
        }
        // File citations can arrive without a content_references record.
        // Never let the old app expose the raw private-use framing/turn ID.
        CGRReplaceUnresolvedMarker(text,@"\uE200filecite\uE202",@"[file]");
        // Apply the same clean fallback to any unresolved web cite token. This
        // deliberately does not match \uE200url, so normal/download links keep
        // their original labels byte-for-byte.
        CGRReplaceUnresolvedMarker(text,@"\uE200cite\uE202",@"[source]");

        // Modern product cards are not understood by the 2024 renderer.
        // Preserve their human-facing product names instead of exposing the
        // raw selections JSON and turn...product IDs.
        CGRReplaceProductMarkers(text,@"products");
        CGRReplaceProductMarkers(text,@"product");

        if (![text isEqualToString:original]) {
            newParts[p]=text;
            changed=YES;
        }
    }
    if (changed) {
        content[@"parts"]=newParts;
        message[@"content"]=content;
    }
    return changed;
}

static BOOL CGRRewriteObject(id object) {
    BOOL changed=NO;
    if ([object isKindOfClass:NSMutableDictionary.class]) {
        NSMutableDictionary *dict=object;
        changed|=CGRRewriteMessage(dict);
        for (id key in [dict.allKeys copy]) changed|=CGRRewriteObject(dict[key]);
    } else if ([object isKindOfClass:NSMutableArray.class]) {
        for (id value in (NSMutableArray *)object) changed|=CGRRewriteObject(value);
    }
    return changed;
}

NSData *CGRCitationCompatRewriteJSONData(NSData *data) {
    if (!data.length) return data;
    static NSData *referencesNeedle;
    static NSData *fileciteNeedle;
    static NSData *citeNeedle;
    static NSData *productNeedle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        referencesNeedle=[@"content_references" dataUsingEncoding:NSUTF8StringEncoding];
        fileciteNeedle=[@"filecite" dataUsingEncoding:NSUTF8StringEncoding];
        citeNeedle=[@"cite" dataUsingEncoding:NSUTF8StringEncoding];
        productNeedle=[@"product" dataUsingEncoding:NSUTF8StringEncoding];
    });
    NSRange whole=NSMakeRange(0,data.length);
    BOOL maybeReferences=[data rangeOfData:referencesNeedle options:0 range:whole].location!=NSNotFound;
    BOOL maybeFilecite=[data rangeOfData:fileciteNeedle options:0 range:whole].location!=NSNotFound;
    BOOL maybeCite=[data rangeOfData: citeNeedle options:0 range:whole].location!=NSNotFound;
    BOOL maybeProduct=[data rangeOfData:productNeedle options:0 range:whole].location!=NSNotFound;
    if (!maybeReferences && !maybeFilecite && !maybeCite && !maybeProduct) return data;

    NSError *error=nil;
    id root=[NSJSONSerialization JSONObjectWithData:data
        options:NSJSONReadingMutableContainers error:&error];
    if (error || !root || !CGRRewriteObject(root)) return data;

    NSData *rewritten=[NSJSONSerialization dataWithJSONObject:root options:0 error:&error];
    return (!error && rewritten.length)?rewritten:data;
}
