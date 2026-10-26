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

        NSDictionary *visibleUser=@{@"id":@"visible-user",
            @"author":@{@"role":@"user"},
            @"content":@{@"content_type":@"text",@"parts":@[@"hello"]}};
        NSDictionary *tool=@{@"id":@"tool",
            @"author":@{@"role":@"tool"},
            @"content":@{@"content_type":@"text",@"parts":@[@"internal"]}};
        NSDictionary *toolCall=@{@"id":@"call",
            @"author":@{@"role":@"assistant"},@"recipient":@"functions.exec",
            @"content":@{@"content_type":@"text",@"parts":@[@"internal"]}};
        NSDictionary *thinking=@{@"id":@"thinking",
            @"author":@{@"role":@"assistant"},
            @"metadata":@{@"channel":@"analysis"},
            @"content":@{@"content_type":@"text",@"parts":@[@"internal"]}};
        NSDictionary *hidden=@{@"id":@"hidden",
            @"author":@{@"role":@"assistant"},
            @"metadata":@{@"is_visually_hidden_from_conversation":@YES},
            @"content":@{@"content_type":@"text",@"parts":@[@"internal"]}};
        NSDictionary *visibleAnswer=@{@"id":@"visible-answer",
            @"author":@{@"role":@"assistant"},
            @"metadata":@{@"channel":@"final"},
            @"content":@{@"content_type":@"text",@"parts":@[@"reply"]}};
        NSArray *mixed=@[visibleUser,tool,toolCall,thinking,hidden,visibleAnswer];
        NSCAssert(CGConversationPagingVisibleCount(mixed)==2,
                  @"Only human-visible messages belong in the old renderer");
        NSData *reduced=CGConversationPagingLegacyData(latest,mixed,@"visible-answer");
        NSDictionary *mapped=CGConversationPagingJSONObject(reduced)[@"mapping"];
        NSCAssert(mapped.count==3 && mapped[@"visible-user"] &&
                  mapped[@"visible-answer"],@"Both visible messages remain");
        NSCAssert([mapped[@"visible-user"][@"children"][0]
                   isEqualToString:@"visible-answer"],
                  @"Invisible tool records must not break message chain");
        NSMutableArray *many=[NSMutableArray array];
        for (NSUInteger i=0;i<600;i++)
            [many addObject:Message([NSString stringWithFormat:@"visible-%lu",
                       (unsigned long)i],@"content")];
        NSData *all=CGConversationPagingLegacyData(latest,many,nil);
        NSDictionary *full=CGConversationPagingJSONObject(all)[@"mapping"];
        NSCAssert(CGConversationPagingVisibleCount(many)==600 &&
                  full.count==601,@"No truncation of a long visible history");
        NSLog(@"PASS: conversation pages merge and convert to the 2024 mapping shape");
    }
    return 0;
}
