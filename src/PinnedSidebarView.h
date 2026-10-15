// PinnedSidebarView.h — 551UK, GPL-3.0
// Native iOS 16 UIKit presentation for the server-backed pinned conversations.
// Host controller integration deliberately separate from this reusable view.
#import <UIKit/UIKit.h>
#import "PinnedSectionLayout.h"

NS_ASSUME_NONNULL_BEGIN
typedef void (^CGPinRowSelection)(CGPinnedSectionEntry *entry);

@interface CGPinnedSidebarView : UIView
/// Called on tap. The host must use native ChatGPT selection/navigation,
/// never an invented browser deep-link. Without a handler, rows are disabled.
@property (nonatomic, copy, nullable) CGPinRowSelection selectionHandler;
@property (nonatomic, copy, nullable) UIMenu *(^menuHandler)(CGPinnedSectionEntry *entry);
/// Allows host collection view to update its spacer on collapse/expand.
@property (nonatomic, copy, nullable) void (^heightDidChange)(void);
@property (nonatomic, assign, getter=isCollapsed) BOOL collapsed;
/// Height of the component, including its 42pt header and at most eight rows.
@property (nonatomic, readonly) CGFloat preferredHeight;
/// Render all server pinned chats. Scrolling is used if >8 rows.
- (void)applyLayout:(CGPinnedSectionLayout *)layout;
@end
NS_ASSUME_NONNULL_END
