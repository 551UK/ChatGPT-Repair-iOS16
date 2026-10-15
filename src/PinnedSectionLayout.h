// PinnedSectionLayout.h — 551UK, GPL-3.0
// Dynamic pinned section from the complete server pins list, not first 20 chats.
// Reuses native history rows when available and retains every off-page pin.
#import <Foundation/Foundation.h>
#import "PinService.h"

NS_ASSUME_NONNULL_BEGIN

/// Return the *conversation ID* of an existing native history row.
typedef NSString * _Nullable (^CGConversationIDForHistoryRow)(id row);

/// Represents one pinned conversation, including those not loaded into the
/// ordinary paginated history. No user-specific IDs are compiled into the tweak.
@interface CGPinnedSectionEntry : NSObject
@property (nonatomic, strong, readonly) CGPinnedConversation *pin;
/// When present, render/select the exact original native row object.
@property (nonatomic, strong, nullable, readonly) id existingHistoryRow;
/// When absent, the UI adapter must materialise the same native row model
/// from pin.conversationID and pin.title; do not silently drop the pin.
@property (nonatomic, assign, readonly) BOOL needsNativeRow;
- (instancetype)initWithPin:(CGPinnedConversation *)pin
                historyRow:(nullable id)historyRow NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface CGPinnedSectionLayout : NSObject
/// Contains *every* current pin, not only IDs among first 20 history rows.
@property (nonatomic, copy, readonly) NSArray<CGPinnedSectionEntry *> *pinnedEntries;
/// Original native history row objects in their original order minus pins.
@property (nonatomic, copy, readonly) NSArray *ordinaryRows;
/// Number of pins for which the native row is not yet loaded.
@property (nonatomic, assign, readonly) NSUInteger pinsOutsideLoadedHistory;
@property (nonatomic, assign, readonly) NSUInteger duplicateHistoryRows;
- (instancetype)initWithPinnedEntries:(NSArray<CGPinnedSectionEntry *> *)pinnedEntries
                        ordinaryRows:(NSArray *)ordinaryRows
            pinsOutsideLoadedHistory:(NSUInteger)pinsOutsideLoadedHistory
               duplicateHistoryRows:(NSUInteger)duplicateHistoryRows NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

/// Reconcile fresh server pins against *any* currently loaded normal-history
/// page(s), keeping pin order and normal chat selection objects unchanged.
/// Call this after each pins refresh and each new history page.
FOUNDATION_EXPORT CGPinnedSectionLayout *CGMakePinnedSectionLayout(
    NSArray<CGPinnedConversation *> *serverPins,
    NSArray *nativeHistoryRows,
    CGConversationIDForHistoryRow conversationIDForRow);
NS_ASSUME_NONNULL_END
