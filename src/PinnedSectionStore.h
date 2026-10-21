// ChatGPTRepair: Pinned conversation section state interface.
// PinnedSectionStore.h — 551UK, GPL-3.0
#import <Foundation/Foundation.h>
#import "PinnedSectionLayout.h"

NS_ASSUME_NONNULL_BEGIN
/// Keeps the currently fetched server pins; no hardcoded IDs/titles or limit.
/// Caller must invoke refresh when the native sidebar opens/refreshes.
@interface CGPinnedSectionStore : NSObject
@property (nonatomic, copy, readonly) NSArray<CGPinnedConversation *> *currentPins;
@property (nonatomic, assign, readonly) BOOL hasVerifiedServerList;

/// Replace from a verified server response. Successful empty arrays clear pins.
/// Failed/unknown responses leave the last verified list unchanged.
- (BOOL)acceptResult:(CGPinsResult *)result;

/// Snapshot an arbitrary amount of pin records into a distinct Pinned section.
/// Pins absent from loaded history are still represented by their server data.
- (CGPinnedSectionLayout *)layoutForHistoryRows:(NSArray *)rows
                         conversationIDForRow:(CGConversationIDForHistoryRow)conversationIDForRow;

/// Uses same authenticated native app session; completion dispatched to main.
/// The UI adapter should reload its pinned snapshot only after success.
- (void)refreshWithSession:(NSURLSession *)session
       authenticatedHistoryRequest:(NSURLRequest *)request
                        completion:(void (^)(BOOL changed, NSError * _Nullable error))completion;
@end
NS_ASSUME_NONNULL_END
