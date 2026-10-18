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


        // Regression: normal rich URL markers are already supported by LinkFix
        // and must retain their custom label. v56.0 accidentally replaced them
        // with a host-only [github.com] citation label.
        NSString *download=@"\uE200url\uE202Download ChatGPTRepair v56.0 (.deb)\uE202https://github.com/551UK/ChatGPT-Repair-iOS16/releases/download/v56.0/ChatGPTRepair_56.0_iphoneos-arm64.deb\uE201";
        NSDictionary *root5=@{@"message":@{
            @"content":@{@"parts":@[download]},
            @"metadata":@{@"content_references":@[@{
                @"matched_text":download,
                @"safe_urls":@[@"https://github.com/551UK/ChatGPT-Repair-iOS16/releases/download/v56.0/ChatGPTRepair_56.0_iphoneos-arm64.deb"]
            }]}
        }};
        NSString *out5=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(root5))));
        NSCAssert([out5 isEqualToString:download],@"normal rich/download link label was modified");
        NSCAssert([out5 containsString:@"Download ChatGPTRepair v56.0 (.deb)"],@"download label was lost");


        // File citations use a different marker family from web citations.
        // They must never leak raw private-use characters/turn IDs in the old app.
        NSString *filecite=@"\uE200filecite\uE202turn20file0\uE201";
        NSDictionary *root6=@{@"message":@{
            @"content":@{@"parts":@[[@"See " stringByAppendingFormat:@"%@ here",filecite]]},
            @"metadata":@{}
        }};
        NSString *out6=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(root6))));
        NSCAssert([out6 rangeOfString:@"\uE200filecite"].location==NSNotFound,@"raw filecite leaked");
        NSCAssert([out6 containsString:@"See [file] here"],@"filecite without metadata was not cleaned");

        NSString *fileciteURL=@"\uE200filecite\uE202turn21file3\uE202L10-L20\uE201";
        NSDictionary *root7=@{@"message":@{
            @"content":@{@"parts":@[fileciteURL]},
            @"metadata":@{@"content_references":@[@{
                @"matched_text":fileciteURL,
                @"safe_urls":@[@"https://files.example.test/document"]
            }]}
        }};
        NSString *out7=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(root7))));
        NSCAssert([out7 containsString:@"https://files.example.test/document"],@"filecite URL was not preserved");
        NSCAssert([out7 rangeOfString:@"\uE200filecite"].location==NSNotFound,@"resolved filecite marker leaked");


        // Modern shopping UI markers must degrade to readable product names.
        NSString *products=@"\uE200products\uE202{\"selections\":[[\"turn378126product0\",\"Koch Chemie Top Star\"],[\"turn479938product4\",\"Poorboy's Natural Look\"]]}\uE201";
        NSDictionary *root8=@{@"message":@{
            @"content":@{@"parts":@[[@"Pick: " stringByAppendingString:products]]},
            @"metadata":@{}
        }};
        NSString *out8=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(root8))));
        NSCAssert([out8 rangeOfString:@"\uE200products"].location==NSNotFound,@"raw products marker leaked");
        NSCAssert([out8 containsString:@"Koch Chemie Top Star"],@"first product name lost");
        NSCAssert([out8 containsString:@"Poorboy's Natural Look"],@"second product name lost");
        NSCAssert([out8 rangeOfString:@"turn378126product0"].location==NSNotFound,@"product ref ID leaked");

        NSString *product=@"\uE200product\uE202[\"turn0product1\",\"Example Product\",{\"render_as\":\"hero\"}]\uE201";
        NSDictionary *root9=@{@"message":@{
            @"content":@{@"parts":@[product]},
            @"metadata":@{}
        }};
        NSString *out9=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(root9))));
        NSCAssert([out9 isEqualToString:@"Example Product"],@"single product marker was not reduced to its label");

        NSLog(@"PASS: web/file citations and product markers render cleanly without altering normal download links");
    }
    return 0;
}
