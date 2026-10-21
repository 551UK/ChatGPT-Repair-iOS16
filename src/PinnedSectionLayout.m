// ChatGPTRepair: Arrange pinned section above conversation history.
// PinnedSectionLayout.m — 551UK, GPL-3.0
#import "PinnedSectionLayout.h"

@implementation CGPinnedSectionEntry
- (instancetype)initWithPin:(CGPinnedConversation *)pin
                historyRow:(id)historyRow {
    if ((self = [super init])) {
        _pin = pin;
        _existingHistoryRow = historyRow;
        _needsNativeRow = (historyRow == nil);
    }
    return self;
}
@end

@implementation CGPinnedSectionLayout
- (instancetype)initWithPinnedEntries:(NSArray<CGPinnedSectionEntry *> *)entries
                        ordinaryRows:(NSArray *)ordinaryRows
            pinsOutsideLoadedHistory:(NSUInteger)outside
               duplicateHistoryRows:(NSUInteger)duplicates {
    if ((self = [super init])) {
        _pinnedEntries = [entries copy];
        _ordinaryRows = [ordinaryRows copy];
        _pinsOutsideLoadedHistory = outside;
        _duplicateHistoryRows = duplicates;
    }
    return self;
}
@end

CGPinnedSectionLayout *CGMakePinnedSectionLayout(
    NSArray<CGPinnedConversation *> *serverPins,
    NSArray *nativeHistoryRows,
    CGConversationIDForHistoryRow conversationIDForRow) {
    NSMutableDictionary<NSString *, id> *rows = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *seenRows = [NSMutableSet set];
    NSMutableArray *uniqueRows = [NSMutableArray array];
    NSUInteger duplicates = 0;
    for (id row in nativeHistoryRows ?: @[]) {
        NSString *identifier = conversationIDForRow ? conversationIDForRow(row) : nil;
        if (![identifier isKindOfClass:[NSString class]] || !identifier.length) {
            // Unknown native rows should stay visible and retain their identity.
            [uniqueRows addObject:row];
            continue;
        }
        if ([seenRows containsObject:identifier]) {
            duplicates++;
            continue;
        }
        [seenRows addObject:identifier];
        rows[identifier] = row;
        [uniqueRows addObject:row];
    }
    NSMutableSet<NSString *> *seenPins = [NSMutableSet set];
    NSMutableArray<CGPinnedSectionEntry *> *pinEntries = [NSMutableArray array];
    for (CGPinnedConversation *pin in serverPins ?: @[]) {
        NSString *identifier = pin.conversationID;
        if (!identifier.length || [seenPins containsObject:identifier]) continue;
        [seenPins addObject:identifier];
        // Keep a pin even if its conversation is on page 12, or never appears
        // in the normal-list because the web sidebar separates it.
        [pinEntries addObject:[[CGPinnedSectionEntry alloc] initWithPin:pin
                                                            historyRow:rows[identifier]]];
    }
    NSMutableArray *ordinary = [NSMutableArray array];
    for (id row in uniqueRows) {
        NSString *identifier = conversationIDForRow ? conversationIDForRow(row) : nil;
        if (![identifier isKindOfClass:[NSString class]] ||
            ![seenPins containsObject:identifier]) {
            [ordinary addObject:row];
        }
    }
    NSUInteger missing = 0;
    for (CGPinnedSectionEntry *entry in pinEntries)
        if (entry.needsNativeRow) missing++;
    return [[CGPinnedSectionLayout alloc] initWithPinnedEntries:pinEntries
                                                   ordinaryRows:ordinary
                                       pinsOutsideLoadedHistory:missing
                                          duplicateHistoryRows:duplicates];
}
