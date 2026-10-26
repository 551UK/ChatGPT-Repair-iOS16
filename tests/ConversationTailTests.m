#import <Foundation/Foundation.h>
#import "../src/ConversationPagingCore.h"
static NSDictionary *row(NSString *i,NSString *text) {return @{@"id":i,@"content":text};}
int main(void) { @autoreleasepool {
    NSArray *old=@[row(@"a",@"old"),row(@"b",@"partial"),row(@"c",@"obsolete")];
    NSArray *tail=@[row(@"b",@"complete"),row(@"d",@"new")];
    NSArray *merged=CGConversationPagingReplaceTail(old,tail);
    NSCAssert(merged.count==3 && [merged[0] isEqual:old[0]],@"preserve loaded prefix");
    NSCAssert([merged[1] isEqual:tail[0]] && [merged[2] isEqual:tail[1]],@"update partial and discard old branch");
    NSCAssert(!CGConversationPagingReplaceTail(old,@[row(@"x",@"gap")]),@"missing overlap must reload");
    NSCAssert(!CGConversationPagingReplaceTail(old,@[row(@"b",@"x"),row(@"a",@"duplicate")]),@"reject duplicate prefix");
    NSCAssert(!CGConversationPagingReplaceTail(old,@[@{@"content":@"no id"}]),@"reject missing ID");
    NSArray *nested=CGConversationPagingReplaceTail(old,@[@{@"message":row(@"b",@"nested")}]);
    NSCAssert(nested.count==2,@"accept nested messages");
    NSCAssert([CGConversationPagingReplaceTail(old,old) isEqual:old],@"unchanged snapshot");
    puts("PASS: live tail replacement, partial text, branch replacement, gap fallback");
} return 0; }
