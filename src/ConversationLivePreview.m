// ChatGPTRepair: display server-visible remote reply text without reopening chat.
// A text preview is not a second stream or a replacement for native messages.
#import "ConversationLivePreview.h"
#import <UIKit/UIKit.h>
static UIView *gPanel;
static UITextView *gText;
static UILabel *gHeading;
static __weak UIWindow *gPanelWindow;
static NSString *gLastText;
static NSString *gCurrentID;
static BOOL gDismissed;

@interface CGPreviewActions:NSObject
+ (instancetype)shared;
- (void)dismiss:(id)sender;
@end
@implementation CGPreviewActions
+ (instancetype)shared {
    static CGPreviewActions *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value=[CGPreviewActions new]; });
    return value;
}
- (void)dismiss:(id)sender { (void)sender; gDismissed=YES; gPanel.hidden=YES; }
@end

static void CGPreviewReposition(UIWindow *window) {
    if (!window || !gPanel) return;
    CGFloat safe=window.safeAreaInsets.top;
    CGFloat width=MIN(window.bounds.size.width-24,540);
    CGFloat x=(window.bounds.size.width-width)*0.5;
    CGFloat height=MIN(248,MAX(140,window.bounds.size.height*0.30));
    gPanel.frame=CGRectMake(x,safe+107,width,height);
    gHeading.frame=CGRectMake(15,3,width-68,34);
    gText.frame=CGRectMake(12,39,width-24,height-48);
    for (UIView *v in gPanel.subviews)
        if ([v isKindOfClass:UIButton.class])
            v.frame=CGRectMake(width-44,5,35,30);
}
static void CGPreviewCreate(UIWindow *window) {
    if (gPanel && gPanelWindow==window) return;
    [gPanel removeFromSuperview];
    UIView *panel=[UIView new];
    panel.backgroundColor=[UIColor colorWithRed:0.14 green:0.14 blue:0.16 alpha:0.97];
    panel.layer.cornerRadius=14;
    panel.layer.borderWidth=1;
    panel.layer.borderColor=[UIColor colorWithWhite:0.42 alpha:0.70].CGColor;
    panel.layer.masksToBounds=YES;
    UILabel *heading=[UILabel new];
    heading.text=@"Live reply preview";
    heading.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    heading.textColor=UIColor.whiteColor;
    [panel addSubview:heading];
    UITextView *text=[UITextView new];
    text.backgroundColor=UIColor.clearColor;
    text.textColor=UIColor.whiteColor;
    text.font=[UIFont systemFontOfSize:15];
    text.editable=NO;
    text.selectable=YES;
    text.scrollEnabled=YES;
    text.textContainerInset=UIEdgeInsetsMake(0,0,8,0);
    [panel addSubview:text];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"×" forState:UIControlStateNormal];
    close.titleLabel.font=[UIFont systemFontOfSize:25];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [close addTarget:[CGPreviewActions shared] action:@selector(dismiss:)
        forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];
    [window addSubview:panel];
    gPanel=panel; gHeading=heading; gText=text; gPanelWindow=window;
    CGPreviewReposition(window);
}
void CGSyncPreviewUpdate(NSString *conversationID, NSString *text) {
    if (!conversationID.length || !text.length) return;
    NSString *display=text.length>16000?[text substringFromIndex:text.length-16000]:text;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
        UIWindow *window=UIApplication.sharedApplication.keyWindow;
        if (!window) window=UIApplication.sharedApplication.windows.firstObject;
        if (!window) return;
        if (![gCurrentID isEqualToString:conversationID]) {
            gCurrentID=[conversationID copy]; gDismissed=NO; gLastText=nil;
        }
        if ([gLastText isEqualToString:display]) return;
        gLastText=[display copy];
        if (gDismissed) return;
        CGPreviewCreate(window);
        CGFloat priorOffset=gText.contentOffset.y;
        BOOL nearBottom=(gText.contentSize.height-gText.bounds.size.height-priorOffset)<95;
        gText.text=display;
        CGPreviewReposition(window);
        gPanel.hidden=NO;
        [window bringSubviewToFront:gPanel];
        if (nearBottom && gText.contentSize.height>gText.bounds.size.height)
            [gText setContentOffset:CGPointMake(0,gText.contentSize.height-gText.bounds.size.height)
                         animated:NO];
    });
}
void CGSyncPreviewHide(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gPanel.hidden=YES;
        gLastText=nil;
    });
}
