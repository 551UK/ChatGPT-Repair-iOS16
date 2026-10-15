// PinnedSidebarView.m — 551UK, GPL-3.0
// UIKit view: Pinned heading, collapse/expand, scrollable live pinned rows.
// This file implements presentation only, no speculative Swift runtime hooks.
#import "PinnedSidebarView.h"

static const CGFloat kHeaderHeight = 42.0;
static const CGFloat kRowHeight = 46.0;
static const NSUInteger kMaxVisibleRows = 8;

@interface CGPinnedSidebarView () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIButton *heading;
@property (nonatomic, strong) UIImageView *chevron;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSLayoutConstraint *tableHeight;
@property (nonatomic, copy) NSArray<CGPinnedSectionEntry *> *entries;
@property (nonatomic, assign) CGFloat preferredHeight;
@end

@implementation CGPinnedSidebarView
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = [UIColor systemBackgroundColor];
    _entries = @[];
    _collapsed = NO;

    _heading = [UIButton buttonWithType:UIButtonTypeSystem];
    _heading.translatesAutoresizingMaskIntoConstraints = NO;
    _heading.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [_heading setTitle:@"Pinned" forState:UIControlStateNormal];
    [_heading setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    _heading.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [_heading addTarget:self action:@selector(toggleCollapse)
       forControlEvents:UIControlEventTouchUpInside];
    _heading.accessibilityLabel = @"Pinned conversations";
    _heading.accessibilityHint = @"Double tap to expand or collapse";
    [self addSubview:_heading];

    _chevron = [[UIImageView alloc] initWithImage:
                [UIImage systemImageNamed:@"chevron.down"]];
    _chevron.translatesAutoresizingMaskIntoConstraints = NO;
    _chevron.tintColor = [UIColor secondaryLabelColor];
    _chevron.contentMode = UIViewContentModeScaleAspectFit;
    _chevron.userInteractionEnabled = NO;
    [self addSubview:_chevron];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.translatesAutoresizingMaskIntoConstraints = NO;
    _table.backgroundColor = [UIColor systemBackgroundColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.showsVerticalScrollIndicator = YES;
    _table.rowHeight = kRowHeight;
    _table.scrollEnabled = YES;
    _table.dataSource = self;
    _table.delegate = self;
    _table.estimatedRowHeight = 0;
    _table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self addSubview:_table];

    _tableHeight = [_table.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [_heading.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_heading.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-40],
        [_heading.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_heading.heightAnchor constraintEqualToConstant:kHeaderHeight],
        [_chevron.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-22],
        [_chevron.centerYAnchor constraintEqualToAnchor:_heading.centerYAnchor],
        [_chevron.widthAnchor constraintEqualToConstant:12],
        [_chevron.heightAnchor constraintEqualToConstant:12],
        [_table.topAnchor constraintEqualToAnchor:_heading.bottomAnchor],
        [_table.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_table.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_table.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        _tableHeight,
    ]];
    [self updateHeights];
    return self;
}

- (void)setSelectionHandler:(CGPinRowSelection)handler {
    _selectionHandler = [handler copy];
    [_table reloadData];
}
- (void)setCollapsed:(BOOL)collapsed {
    if (_collapsed == collapsed) return;
    _collapsed = collapsed;
    [self updateHeights];
}
- (void)toggleCollapse { self.collapsed = !self.isCollapsed; if (self.heightDidChange) self.heightDidChange(); }

- (void)applyLayout:(CGPinnedSectionLayout *)layout {
    // This covers *all* pins provided by the server, never a fixed set of six.
    self.entries = layout.pinnedEntries ?: @[];
    [_table reloadData];
    [self updateHeights];
}
- (void)updateHeights {
    NSUInteger count = self.collapsed ? 0 : MIN(self.entries.count, kMaxVisibleRows);
    _tableHeight.constant = count * kRowHeight;
    _table.hidden = self.collapsed || !self.entries.count;
    _preferredHeight = kHeaderHeight + _tableHeight.constant;
    _chevron.transform = self.collapsed ? CGAffineTransformMakeRotation(-M_PI_2)
                                        : CGAffineTransformIdentity;
    [_heading setAccessibilityValue:self.collapsed ? @"Collapsed" : @"Expanded"];
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}
- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, self.preferredHeight);
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.entries.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView
        cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuse = @"CGPinnedChatRow";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:reuse];
        cell.backgroundColor = [UIColor systemBackgroundColor];
        cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
        cell.textLabel.numberOfLines = 1;
        cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        UIView *selected = [[UIView alloc] init];
        selected.backgroundColor = [UIColor secondarySystemBackgroundColor];
        cell.selectedBackgroundView = selected;
    }
    CGPinnedSectionEntry *entry = self.entries[indexPath.row];
    NSString *title = entry.pin.title.length ? entry.pin.title : @"Untitled conversation";
    cell.textLabel.text = [@"📌  " stringByAppendingString:title];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.accessibilityLabel = title;
    cell.selectionStyle = self.selectionHandler
        ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CGPinRowSelection handler = self.selectionHandler;
    if (handler && indexPath.row < self.entries.count)
        handler(self.entries[indexPath.row]);
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
 contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (indexPath.row >= self.entries.count || !self.menuHandler) return nil;
    CGPinnedSectionEntry *entry = self.entries[indexPath.row];
    UIMenu *(^provider)(CGPinnedSectionEntry *) = self.menuHandler;
    return [UIContextMenuConfiguration configurationWithIdentifier:entry.pin.conversationID
        previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
            return provider(entry);
        }];
}
@end
