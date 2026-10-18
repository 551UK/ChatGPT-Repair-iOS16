#import <Foundation/Foundation.h>
#import "../src/CitationCompat.h"

static NSData *JSONData(NSDictionary *obj) {
    return [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL];
}
static NSDictionary *JSONObj(NSData *data) {
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}
static NSString *Part(NSDictionary *root) {
    return root[@"message"][@"content"][@"parts"][0];
}
int main(void) {
    @autoreleasepool {
        NSString *cite=@"\uE200cite\uE202turn0search1\uE201";
        NSDictionary *root=@{@"message":@{
            @"content":@{@"content_type":@"text",@"parts":@[[@"Fact " stringByAppendingFormat:@"%@ end",cite]]},
            @"metadata":@{@"content_references":@[@{
                @"type":@"grouped_webpages",
                @"matched_text":cite,
                @"safe_urls":@[@"https://www.example.com/page"]
            }]}
        }};
        NSString *out=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(root))));
        NSCAssert([out rangeOfString:@"\uE200cite"].location==NSNotFound,@"raw cite leaked");
        NSCAssert([out rangeOfString:@"\uE200url\uE202[example.com]\uE202https://www.example.com/page\uE201"].location!=NSNotFound,@"citation not converted");

        NSString *multi=@"\uE200cite\uE202turn0search1\uE202turn0search2\uE201";
        NSDictionary *root2=@{@"message":@{
            @"content":@{@"parts":@[multi]},
            @"metadata":@{@"content_references":@[@{
                @"matched_text":multi,
                @"safe_urls":@[@"https://a.example/x",@"https://b.example/y"]
            }]}
        }};
        NSString *out2=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(root2))));
        NSCAssert([out2 containsString:@"[a.example]"] && [out2 containsString:@"[b.example]"],@"grouped citation lost URLs");

        NSString *fallback=@"\uE200cite\uE202turn9search0\uE201";
        NSDictionary *root3=@{@"message":@{
            @"content":@{@"parts":@[fallback]},
            @"metadata":@{@"content_references":@[@{
                @"matched_text":fallback,
                @"alt":@"([Fallback](https://fallback.example/source))"
            }]}
        }};
        NSString *out3=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(root3))));
        NSCAssert([out3 containsString:@"https://fallback.example/source"],@"alt URL fallback failed");

        NSDictionary *root4=@{@"message":@{
            @"content":@{@"parts":@[@"a b"]},
            @"metadata":@{@"content_references":@[@{
                @"matched_text":@" ",
                @"safe_urls":@[@"https://do-not-replace.example/"]
            }]}
        }};
        NSString *out4=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(root4))));
        NSCAssert([out4 isEqualToString:@"a b"],@"ordinary matched_text was incorrectly replaced");

        NSLog(@"PASS: modern citation markers convert to old-app rich links");
    }
    return 0;
}
