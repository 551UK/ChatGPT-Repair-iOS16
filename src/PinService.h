// PinService.h — 551UK, GPL-3.0
// Read-only pinned-conversation data model for legacy ChatGPT iOS 16.
// Does not install UI hooks or change existing conversation history.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface CGPinnedConversation : NSObject
@property (nonatomic, copy, readonly) NSString *conversationID;
@property (nonatomic, copy, readonly) NSString *title;
/// ISO-8601 value returned by the pins endpoint; list order is preserved.
@property (nonatomic, copy, readonly) NSString *pinnedAt;
- (instancetype)initWithID:(NSString *)conversationID
                     title:(NSString *)title
                  pinnedAt:(NSString *)pinnedAt NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface CGPinsResult : NSObject
@property (nonatomic, copy, readonly) NSArray<CGPinnedConversation *> *conversations;
@property (nonatomic, assign, readonly) NSUInteger examinedItems;
@property (nonatomic, assign, readonly) NSUInteger skippedItems;
@property (nonatomic, assign, readonly) BOOL recognizedResponse;
@property (nonatomic, copy, nullable, readonly) NSString *nextCursor;
- (instancetype)initWithConversations:(NSArray<CGPinnedConversation *> *)conversations
                       examinedItems:(NSUInteger)examinedItems
                        skippedItems:(NSUInteger)skippedItems
                  recognizedResponse:(BOOL)recognizedResponse
                          nextCursor:(nullable NSString *)nextCursor;
@end

enum { CGPinsSessionInvalidated = 4 };

typedef void (^CGPinsCompletion)(CGPinsResult * _Nullable result,
                                  NSError * _Nullable error);

/// Only call with a first-party *authenticated* history-list request.
/// Uses the same host, method-independent auth headers and cookie handling;
/// never logs or exposes account tokens.
FOUNDATION_EXPORT NSURLRequest * _Nullable CGPinsRequestFromHistoryRequest(
    NSURLRequest *historyRequest);

/// Tolerant parser for the response's outer envelope, not a guessed UI model.
/// Returns recognizedResponse=NO for unknown schemas, rather than inventing
/// conversation IDs or titles.
FOUNDATION_EXPORT CGPinsResult *CGParsePinsJSON(NSData *data);

/// Fetch once using the app's existing URLSession, keeping its authentication
/// and delegate/session transport untouched. Does not paginate by itself.
FOUNDATION_EXPORT void CGFetchPins(NSURLSession *session,
                                   NSURLRequest *authenticatedHistoryRequest,
                                   CGPinsCompletion completion);
NS_ASSUME_NONNULL_END
