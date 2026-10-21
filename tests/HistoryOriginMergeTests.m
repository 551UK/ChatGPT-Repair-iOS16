// ChatGPTRepair: Regression tests for historical chat merging.
#import <Foundation/Foundation.h>
#import "../src/HistoryOriginMerge.h"

static NSData *JSON(NSDictionary *value) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];
    NSCAssert(data!=nil,@"fixture");
    return data;
}
static NSDictionary *Parse(NSData *value) {
    return [NSJSONSerialization JSONObjectWithData:value options:0 error:NULL];
}
static NSArray *IDs(NSDictionary *value) {
    NSMutableArray *items=[NSMutableArray array];
    for (NSDictionary *row in value[@"items"]) [items addObject:row[@"id"]];
    return items;
}
int main(void) {
    @autoreleasepool {
        NSDictionary *normal=@{@"items":@[
            @{@"id":@"normal-new",@"title":@"Normal",@"update_time":@"2026-10-16T18:13:33Z"},
            @{@"id":@"normal-old",@"title":@"Older",@"update_time":@"2026-10-15T14:31:08Z"}
        ],@"total":@2,@"limit":@2,@"offset":@0};
        NSDictionary *tpp=@{@"items":@[
            @{@"id":@"web-new",@"title":@"Fresh browser chat",@"update_time":@"2026-10-16T18:16:44Z"},
            @{@"id":@"tpp-old",@"title":@"Old browser chat",@"update_time":@"2026-09-25T14:21:00Z"}
        ],@"total":@2,@"limit":@2,@"offset":@0};
        NSData *first=CGOriginMergeJSON(JSON(normal),JSON(tpp),0,2);
        NSCAssert(first!=nil,@"first page merged");
        NSDictionary *firstPage=Parse(first);
        NSArray *firstExpected=@[@"web-new",@"normal-new"];
        NSCAssert([IDs(firstPage) isEqualToArray:firstExpected],@"global newest first");
        NSCAssert([firstPage[@"total"] integerValue]==4,@"combined total");
        NSData *second=CGOriginMergeJSON(JSON(normal),JSON(tpp),2,2);
        NSArray *secondExpected=@[@"normal-old",@"tpp-old"];
        NSCAssert([IDs(Parse(second)) isEqualToArray:secondExpected],@"correct second page");
        NSMutableDictionary *duplicate=[tpp mutableCopy];
        duplicate[@"items"]=@[
            @{@"id":@"web-new",@"update_time":@"2026-10-16T18:16:44Z"},
            @{@"id":@"normal-new",@"update_time":@"2026-10-16T18:13:33Z"}
        ];
        NSData *dedup=CGOriginMergeJSON(JSON(normal),JSON(duplicate),0,2);
        NSCAssert([IDs(Parse(dedup)) isEqualToArray:firstExpected],@"no duplicate IDs");
        NSCAssert(CGOriginMergeJSON(JSON(normal),nil,0,2)==nil,@"unavailable origin fallback");
        NSURLRequest *r=[NSURLRequest requestWithURL:
            [NSURL URLWithString:@"https://chatgpt.com/backend-api/conversations?offset=0&limit=20"]];
        NSCAssert(CGOriginMergeEligible(r),@"normal feed");
        NSURLRequest *origin=[NSURLRequest requestWithURL:
            [NSURL URLWithString:@"https://chatgpt.com/backend-api/conversations?conversation_origin=tpp"]];
        NSCAssert(!CGOriginMergeEligible(origin),@"never merge a source feed recursively");
        NSCAssert(!CGOriginMergeEligible([NSURLRequest requestWithURL:
            [NSURL URLWithString:@"https://chatgpt.com/backend-api/conversations?is_archived=true"]]),@"archive unaffected");
        NSLog(@"PASS: merged origins newest-first, pagination, deduplication and safe fallback");
    }
    return 0;
}
