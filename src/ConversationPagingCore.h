// ChatGPTRepair: Conversation-page assembly declarations.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSDictionary * _Nullable CGConversationPagingJSONObject(NSData *data);
NSArray *CGConversationPagingMessages(NSDictionary *root);
NSString * _Nullable CGConversationPagingStartCursor(NSDictionary *root, BOOL *hasPrevious);
BOOL CGConversationPagingHasVersionMarkers(NSDictionary *root);
NSArray *CGConversationPagingMergeMessages(NSArray *older, NSArray *newer);
NSData * _Nullable CGConversationPagingLegacyData(NSDictionary *root,
                                                    NSArray *messages,
                                                    NSString * _Nullable currentNodeOverride);

NS_ASSUME_NONNULL_END
