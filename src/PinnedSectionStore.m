// ChatGPTRepair: Maintain pinned sidebar section state.
// PinnedSectionStore.m — 551UK, GPL-3.0
#import "PinnedSectionStore.h"

@interface CGPinnedSectionStore ()
@property (nonatomic, copy, readwrite) NSArray<CGPinnedConversation *> *currentPins;
@property (nonatomic, assign, readwrite) BOOL hasVerifiedServerList;
@end

@implementation CGPinnedSectionStore

- (instancetype)init {
    if ((self = [super init])) {
        _currentPins = @[];
        _hasVerifiedServerList = NO;
    }
    return self;
}

- (BOOL)acceptResult:(CGPinsResult *)result {
    if (!result || !result.recognizedResponse) return NO;
    @synchronized(self) {
        self.currentPins = result.conversations ?: @[];
        self.hasVerifiedServerList = YES;
    }
    return YES;
}

- (CGPinnedSectionLayout *)layoutForHistoryRows:(NSArray *)rows
                         conversationIDForRow:(CGConversationIDForHistoryRow)conversationIDForRow {
    NSArray<CGPinnedConversation *> *pins;
    @synchronized(self) {
        pins = self.currentPins;
    }
    return CGMakePinnedSectionLayout(pins, rows, conversationIDForRow);
}

- (void)refreshWithSession:(NSURLSession *)session
       authenticatedHistoryRequest:(NSURLRequest *)request
                        completion:(void (^)(BOOL changed, NSError *error))completion {
    __weak typeof(self) weakSelf = self;
    CGFetchPins(session, request, ^(CGPinsResult *result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { if (completion) completion(NO, error); return; }
            BOOL accepted = [strongSelf acceptResult:result];
            NSError *reportedError = error;
            if (!accepted && !reportedError) {
                reportedError = [NSError errorWithDomain:@"com.551uk.pins"
                                           code:3
                                       userInfo:@{NSLocalizedDescriptionKey:
                           @"Pins response format unrecognized, preserving last list"}];
            }
            if (completion) completion(accepted, reportedError);
        });
    });
}
@end
