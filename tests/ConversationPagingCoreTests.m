// ChatGPTRepair: Regression tests for older conversation-page assembly.
#import <Foundation/Foundation.h>
#import "../src/ConversationPagingCore.h"

static NSDictionary *Message(NSString *identifier, NSString *text) {
    return @{
        @"id":identifier,
        @"author":@{@"role":@"assistant"},
        @"content":@{@"content_type":@"text",@"parts":@[text]},
        @"metadata":@{}
    };
}

int main(void) {
    @autoreleasepool {
        NSDictionary *latest=@{
            @"conversation_id":@"11111111-1111-1111-1111-111111111111",
            @"title":@"Long chat",
            @"current_node":@"m4",
            @"messages":@[Message(@"m3",@"three"),Message(@"m4",@"four")],
            @"page_info":@{@"start_cursor":@"cursor-3",@"has_previous_page":@YES,@"has_next_page":@NO}
        };
        BOOL hasPrevious=NO;
        NSString *cursor=CGConversationPagingStartCursor(latest,&hasPrevious);
        NSCAssert(hasPrevious && [cursor isEqualToString:@"cursor-3"],@"page cursor was not parsed");

        NSArray *merged=CGConversationPagingMergeMessages(
            @[Message(@"m1",@"one"),Message(@"m2",@"two")],
            @[Message(@"m3",@"three"),Message(@"m4",@"four")]);
        NSCAssert(merged.count==4,@"older and newer pages were not merged");

        NSArray *duplicate=CGConversationPagingMergeMessages(
            @[Message(@"m1",@"old"),Message(@"m2",@"two")],
            @[Message(@"m1",@"new"),Message(@"m3",@"three")]);
        NSCAssert(duplicate.count==3,@"duplicate message ID was not collapsed");
        NSDictionary *first=duplicate[0];
        NSCAssert([first[@"content"][@"parts"][0] isEqualToString:@"new"],@"newer duplicate did not win");

        NSData *legacyData=CGConversationPagingLegacyData(latest,merged,@"m4");
        NSDictionary *legacy=CGConversationPagingJSONObject(legacyData);
        NSDictionary *mapping=legacy[@"mapping"];
        NSCAssert([legacy[@"id"] isEqualToString:latest[@"conversation_id"]],@"legacy conversation ID missing");
        NSCAssert([legacy[@"current_node"] isEqualToString:@"m4"],@"current node changed");
        NSCAssert([mapping isKindOfClass:NSDictionary.class] && mapping.count==5,@"legacy mapping not built");
        NSDictionary *root=mapping[@"client-created-root"];
        NSCAssert([root[@"children"][0] isEqualToString:@"m1"],@"mapping root does not point to oldest loaded message");
        NSCAssert([mapping[@"m1"][@"children"][0] isEqualToString:@"m2"],@"message chain broken at m1");
        NSCAssert([mapping[@"m3"][@"children"][0] isEqualToString:@"m4"],@"message chain broken at m3");
        NSCAssert(!legacy[@"messages"] && !legacy[@"page_info"],@"modern paging fields leaked to legacy decoder");

        NSMutableDictionary *branched=[latest mutableCopy];
        NSMutableArray *versioned=[latest[@"messages"] mutableCopy];
        NSMutableDictionary *firstVersioned=[versioned[0] mutableCopy];
        NSMutableDictionary *metadata=[firstVersioned[@"metadata"] mutableCopy] ?: [NSMutableDictionary dictionary];
        metadata[@"has_versions"]=@YES;
        firstVersioned[@"metadata"]=metadata;
        versioned[0]=firstVersioned;
        branched[@"messages"]=versioned;
        NSCAssert(CGConversationPagingHasVersionMarkers(branched),@"branch/version marker was not detected");

        NSLog(@"PASS: conversation pages merge and convert to the 2024 mapping shape");
    }
    return 0;
}
