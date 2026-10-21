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

        NSURL *remembered=CGRCitationPrimaryURLForMarker(cite);
        NSCAssert([[remembered absoluteString] isEqualToString:@"https://www.example.com/page"],@"citation URL registry did not remember source");

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


        // Adjacent citations from the same site should not render as a row of
        // repeated host links in the legacy app.
        NSString *kc1=@"\uE200cite\uE202turn1search1\uE201";
        NSString *kc2=@"\uE200cite\uE202turn1search2\uE201";
        NSString *kc3=@"\uE200cite\uE202turn1search3\uE201";
        NSString *kc4=@"\uE200cite\uE202turn1search4\uE201";
        NSDictionary *root10=@{@"message":@{
            @"content":@{@"parts":@[[NSString stringWithFormat:@"%@ %@ %@ %@",kc1,kc2,kc3,kc4]]},
            @"metadata":@{@"content_references":@[
                @{@"matched_text":kc1,@"safe_urls":@[@"https://www.koch-chemie.com/a"]},
                @{@"matched_text":kc2,@"safe_urls":@[@"https://www.koch-chemie.com/b"]},
                @{@"matched_text":kc3,@"safe_urls":@[@"https://www.koch-chemie.com/c"]},
                @{@"matched_text":kc4,@"safe_urls":@[@"https://www.koch-chemie.com/d"]}
            ]}
        }};
        NSString *out10=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(root10))));
        NSUInteger kcCount=[[out10 componentsSeparatedByString:@"[koch-chemie.com]"] count]-1;
        NSCAssert(kcCount==1,@"same-site citation spam was not compacted");
        NSCAssert([out10 rangeOfString:@"\uE200cite"].location==NSNotFound,@"raw cite leaked in compacted group");


        // Real-world modern DIL fallback (October 2026 older-app regression).
        // Neither raw JSX tags nor unresolved server-side product bindings may
        // reach the old renderer, but the direct retailer URL must survive.
        NSString *dil=@"One important point:\n"
            "<row align=\"start\" gap={3}>\n"
            "<AsyncImage query=\"Loctite 480 black rubber toughened instant adhesive 20g\" aspectRatio=\"3:4\" maxWidth=\"112px\"/>\n"
            "<box flex=\"1\" gap={1}>\n"
            "**Loctite 480 – 20g**\n\n"
            "£26.38 at MSC Industrial\n"
            "<text size=\"sm\"><Link url=\"https://www.mscdirect.co.uk/loctite-20g-480-black-toughened-instant-adhesive-lct-48020d\" title=\"Buy in the UK\"/></text>\n"
            "</box>\n</row>\n"
            "There is also a cheaper alternative, listed for {turn243296product15.displayed_price}.";
        NSDictionary *richRoot=@{@"message":@{
            @"content":@{@"parts":@[dil]},@"metadata":@{}
        }};
        NSString *rich=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(richRoot))));
        NSCAssert(![rich containsString:@"<row"],@"raw layout tag leaked");
        NSCAssert(![rich containsString:@"<box"],@"raw box tag leaked");
        NSCAssert(![rich containsString:@"<AsyncImage"],@"raw image tag leaked");
        NSCAssert(![rich containsString:@"<Link"],@"raw rich link tag leaked");
        NSCAssert(![rich containsString:@"{turn243296product15"],@"unresolved price binding leaked");
        NSCAssert([rich containsString:@"[price unavailable]"],@"missing fallback price");
        NSCAssert([rich containsString:@"Loctite 480 – 20g"],@"product name lost");
        NSCAssert([rich containsString:@"£26.38 at MSC Industrial"],@"real displayed price lost");
        NSCAssert([rich containsString:@"\uE200url\uE202Buy in the UK\uE202https://www.mscdirect.co.uk/"],@"retailer link lost");

        // Don't transform ordinary examples of XML / UI code.
        NSString *example=@"Here is code: <row align=\"start\"><Link url=\"https://example.com\"/></row>";
        NSDictionary *noRewrite=@{@"message":@{
            @"content":@{@"parts":@[example]},@"metadata":@{}
        }};
        NSString *unchanged=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(noRewrite))));
        NSCAssert([unchanged isEqualToString:example],@"ordinary code example was changed");

        NSString *onlyBinding=@"An alternative costs {turn120product5.displayed_price}.";
        NSDictionary *bindingRoot=@{@"message":@{
            @"content":@{@"parts":@[onlyBinding]},@"metadata":@{}
        }};
        NSString *bound=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(bindingRoot))));
        NSCAssert([bound containsString:@"[price unavailable]"],@"standalone binding leaked");


        // Screenshot regression: modern GenUI button/badge markup was shown
        // literally by ChatGPT 1.2024.200 even though the embedded URL worked.
        NSString *genUIButton=@"**ChatGPTRepair v56.6 – Test fix**\n"
            "<badge color=\"success\">Build passed</badge>\n\n"
            "<button block onClick={() => GenUI.openUrl(\"https://github.com/551UK/ChatGPT-Repair-iOS16/releases/download/v56.6/ChatGPTRepair_56.6_iphoneos-arm64.deb\")}>\n"
            "Download v56.6 DEB\n\n"
            "GitHub release · Previous v56.5";
        NSDictionary *genRoot=@{@"message":@{
            @"content":@{@"parts":@[genUIButton]},@"metadata":@{}
        }};
        NSString *genOut=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(genRoot))));
        NSCAssert(![genOut containsString:@"<badge"],@"raw badge leaked");
        NSCAssert(![genOut containsString:@"<button"],@"raw GenUI button leaked");
        NSCAssert(![genOut containsString:@"GenUI.openUrl"],@"raw GenUI call leaked");
        NSCAssert([genOut containsString:@"Build passed"],@"badge text lost");
        NSCAssert([genOut containsString:@"\uE200url\uE202Download v56.6 DEB\uE202https://github.com/551UK/ChatGPT-Repair-iOS16/releases/download/v56.6/ChatGPTRepair_56.6_iphoneos-arm64.deb\uE201"],
                  @"GenUI download did not become a rich clickable URL token");


        // Screenshot regression: the modern row/icon wrapper must collapse to
        // one clean clickable label instead of exposing JSX + Markdown + URL.
        NSString *downloadRow=@"<row align=\"center\" gap={3}>\n"
            "<icon name=\"download\" size=\"lg\"/>\n"
            "**[Download CallBar Lock Screen Diagnostic DEB](https://github.com/551UK/CallBar-IOS16/releases/download/callbar-lockdiag-4/com.551uk.callbarlockdiag_1.0-1_iphoneos-arm64.deb)**\n"
            "</row>";
        NSDictionary *downloadRowRoot=@{@"message":@{
            @"content":@{@"parts":@[downloadRow]},@"metadata":@{}
        }};
        NSString *downloadRowOut=Part(JSONObj(CGRCitationCompatRewriteJSONData(JSONData(downloadRowRoot))));
        NSCAssert(![downloadRowOut containsString:@"<row"],@"raw download row leaked");
        NSCAssert(![downloadRowOut containsString:@"<icon"],@"raw download icon leaked");
        NSCAssert(![downloadRowOut containsString:@"**["],@"raw Markdown link leaked");
        NSCAssert([downloadRowOut containsString:@"\uE200url\uE202↓ Download CallBar Lock Screen Diagnostic DEB\uE202https://github.com/551UK/CallBar-IOS16/releases/download/callbar-lockdiag-4/com.551uk.callbarlockdiag_1.0-1_iphoneos-arm64.deb\uE201"],
                  @"download row was not converted to one tappable legacy link");

        NSLog(@"PASS: citations compact cleanly, product markers render cleanly, and normal download links stay intact");
    }
    return 0;
}
