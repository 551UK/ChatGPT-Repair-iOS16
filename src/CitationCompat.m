#import "CitationCompat.h"

static BOOL CGRContainsPrivateCitationMarker(NSString *text) {
    for (NSUInteger i=0;i<text.length;i++) {
        unichar c=[text characterAtIndex:i];
        if (c>=0xE200 && c<=0xE203) return YES;
    }
    return NO;
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
    if (!content || !references.count || !parts.count) return NO;

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
            if (!matched.length || !CGRContainsPrivateCitationMarker(matched)) continue;
            if ([text rangeOfString:matched].location==NSNotFound) continue;

            NSArray<NSURL *> *urls=CGRURLsForReference(reference);
            NSString *replacement=nil;
            if (urls.count) {
                NSMutableArray<NSString *> *tokens=[NSMutableArray arrayWithCapacity:urls.count];
                for (NSURL *url in urls) [tokens addObject:CGRRichLinkToken(url)];
                replacement=[tokens componentsJoinedByString:@" "];
            } else {
                replacement=@"[source]";
            }
            [text replaceOccurrencesOfString:matched withString:replacement
                                    options:0 range:NSMakeRange(0,text.length)];
        }
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
    static NSData *needle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        needle=[@"content_references" dataUsingEncoding:NSUTF8StringEncoding];
    });
    if ([data rangeOfData:needle options:0 range:NSMakeRange(0,data.length)].location==NSNotFound)
        return data;

    NSError *error=nil;
    id root=[NSJSONSerialization JSONObjectWithData:data
        options:NSJSONReadingMutableContainers error:&error];
    if (error || !root || !CGRRewriteObject(root)) return data;

    NSData *rewritten=[NSJSONSerialization dataWithJSONObject:root options:0 error:&error];
    return (!error && rewritten.length)?rewritten:data;
}
