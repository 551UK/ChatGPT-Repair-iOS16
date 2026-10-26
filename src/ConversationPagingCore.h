// ChatGPTRepair: Conversation-page assembly declarations.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSDictionary * _Nullable CGConversationPagingJSONObject(NSData *data);
NSArray *CGConversationPagingMessages(NSDictionary *root);
NSString * _Nullable CGConversationPagingStartCursor(NSDictionary *root, BOOL *hasPrevious);
NSArray *CGConversationPagingMergeMessages(NSArray *older, NSArray *newer);
NSUInteger CGConversationPagingVisibleCount(NSArray *messages);
NSData * _Nullable CGConversationPagingLegacyData(NSDictionary *root,
                                                    NSArray *messages,
                                                    NSString * _Nullable currentNodeOverride);

// Replace the cached suffix at a shared anchor. nil means a full reload is needed.
NSArray * _Nullable CGConversationPagingReplaceTail(NSArray *cached, NSArray *newest);

NS_ASSUME_NONNULL_END
