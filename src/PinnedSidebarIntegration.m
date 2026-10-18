/*
 * PinnedSidebarIntegration.m — 551UK — GPLv3
 * Experimental native bridge for ChatGPT 1.2024.200.
 * Reuses existing v0.9 browser-compatible history networking unchanged.
 * Fetches /backend-api/pins?item_type=conversation using the same app session
 * and presents pinned chats above the history rows.
 */
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
extern void CGRCompatibilityEnsureLoaded(void);
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <string.h>
#include <math.h>
#import "PinService.h"
#import "HistoryPageCache.h"
#import "HistoryOriginMerge.h"
#import "CitationCompat.h"
#import "PinnedSectionStore.h"
#import "PinnedSidebarView.h"
#import "PinnedLayoutShim.h"

static CGPinnedSectionStore *sPins;
static __weak NSURLSession *sSession;
static NSURLSession *sMenuSession;
static NSURLRequest *sHistoryRequest;
static BOOL sRefreshing = NO;
static NSTimeInterval sLastRefresh = 0;
static BOOL sNativeHookInstalled = NO;
static IMP sOriginalLayout = NULL;
static IMP sOriginalAppear = NULL;
static IMP sOriginalScroll = NULL;
static char kPinView, kPinAnchor, kRenderedPinSet;
static NSString * const kUpdated = @"com.551uk.pins.updated";


// v0.49: Pin mutation uses the native 2026 route: pins/conversation/<UUID>.
static NSMutableSet *sPinWrites;
static NSMutableDictionary<NSString *, NSString *> *sHistoryTitles;
static NSString *sMenuID, *sMenuTitle;
static __weak UIViewController *sMenuOwner;
static void CGRender(id controller);
static void CGRefreshPins(void);
static void CGPinError(UIViewController *owner, NSString *message) {
    if (!owner.view.window || owner.presentedViewController) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Pin update failed"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [owner presentViewController:alert animated:YES completion:nil];
}
static BOOL CGIsPinned(NSString *cid) {
    for (CGPinnedConversation *pin in sPins.currentPins)
        if ([pin.conversationID caseInsensitiveCompare:cid]==NSOrderedSame) return YES;
    return NO;
}
static void CGSetPin(UIViewController *owner, NSString *cid, NSString *title, BOOL pin) {
    if (![[NSUUID alloc] initWithUUIDString:cid] || [sPinWrites containsObject:cid]) return;
    NSURLSession *session=sMenuSession;
    NSMutableURLRequest *request=[CGPinsRequestFromHistoryRequest(sHistoryRequest) mutableCopy];
    if (sRefreshing) { CGPinError(owner,@"The pinned list is refreshing. Please try again in a moment."); return; }
    if (!session || !request) {  CGPinError(owner,@"Load the chat list once so the account authentication can be captured."); return; }
    NSURLComponents *url=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    url.path=[@"/backend-api/pins/conversation/" stringByAppendingString:cid];
    url.query=nil; request.URL=url.URL; request.HTTPMethod=pin?@"POST":@"DELETE";
    request.HTTPBody=nil;
    [request setValue:nil forHTTPHeaderField:@"Content-Length"];
    [sPinWrites addObject:cid];
    NSString *auth=[sHistoryRequest valueForHTTPHeaderField:@"Authorization"];
    CGPinnedSectionStore *store=sPins;
    __weak UIViewController *weakOwner=owner;
    @try {
        [[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
            NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
            dispatch_async(dispatch_get_main_queue(), ^{
                [sPinWrites removeObject:cid];
                
                if (store!=sPins || ![(auth?:@"") isEqualToString:([sHistoryRequest valueForHTTPHeaderField:@"Authorization"]?:@"")]) return;
                if (error || status<200 || status>=300) {
                    CGPinError(weakOwner, error?@"The request could not be completed. Your pinned list has not been changed.":[NSString stringWithFormat:@"The server rejected the update (HTTP %ld). Your pinned list has not been changed.",(long)status]); return;
                }
                // Apply only after server acknowledgement, then reconcile with the server.
                NSMutableArray *updated=[NSMutableArray array];
                for (CGPinnedConversation *item in sPins.currentPins)
                    if ([item.conversationID caseInsensitiveCompare:cid]!=NSOrderedSame) [updated addObject:item];
                if (pin) [updated insertObject:[[CGPinnedConversation alloc] initWithID:cid title:title?:@"" pinnedAt:@""] atIndex:0];
                [sPins acceptResult:[[CGPinsResult alloc] initWithConversations:updated examinedItems:updated.count skippedItems:0 recognizedResponse:YES nextCursor:nil]];
                [[NSNotificationCenter defaultCenter] postNotificationName:kUpdated object:nil];
                sLastRefresh=0; CGRefreshPins();
            });
        }] resume];
    } @catch (NSException *exception) {
        [sPinWrites removeObject:cid];
        if (![exception.name isEqualToString:NSGenericException] ||
            [exception.reason rangeOfString:@"session that has been invalidated" options:NSCaseInsensitiveSearch].location==NSNotFound) @throw;
        if (sMenuSession==session) sMenuSession=nil;
        CGPinError(owner,@"Reopen the chat list to refresh your session, then try again.");
    }
}
static UIAction *CGPinAction(UIViewController *owner, NSString *cid, NSString *title) {
    BOOL pinned=CGIsPinned(cid);
    __weak UIViewController *weakOwner=owner;
    UIAction *action=[UIAction actionWithTitle:pinned?@"Unpin chat":@"Pin chat"
        image:[UIImage systemImageNamed:pinned?@"pin.slash":@"pin"]
        identifier:@"com.551uk.pin-toggle" handler:^(__unused UIAction *a) {
            CGSetPin(weakOwner,cid,title,!pinned);
        }];
    if ([sPinWrites containsObject:cid]) action.attributes=UIMenuElementAttributesDisabled;
    return action;
}
static void CGRememberHistory(NSData *data) {
    if (!data.length || data.length>16*1024*1024) return;
    id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:NSDictionary.class]) return;
    id items=json[@"items"];
    if (![items isKindOfClass:NSArray.class]) return;
    NSMutableDictionary *records=[NSMutableDictionary dictionary];
    for (id row in items) if ([row isKindOfClass:NSDictionary.class]) {
        id cid=row[@"id"], title=row[@"title"];
        if ([cid isKindOfClass:NSString.class] && [title isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:cid]) records[cid]=title;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [sHistoryTitles addEntriesFromDictionary:records];  });
}
// Wrap the app's existing menu factory only while its history delegate builds
// that row's menu. Keep its original preview provider and every native action.
@interface UIContextMenuConfiguration (CGPinMenus)
+ (instancetype)cgp_configurationWithIdentifier:(id<NSCopying>)identifier
 previewProvider:(UIContextMenuContentPreviewProvider)preview actionProvider:(UIContextMenuActionProvider)provider;
@end
@implementation UIContextMenuConfiguration (CGPinMenus)
+ (instancetype)cgp_configurationWithIdentifier:(id<NSCopying>)identifier
 previewProvider:(UIContextMenuContentPreviewProvider)preview actionProvider:(UIContextMenuActionProvider)provider {
    if (!NSThread.isMainThread || !sMenuOwner)
        return [self cgp_configurationWithIdentifier:identifier previewProvider:preview actionProvider:provider];
    NSString *cid=nil;
    if ([(id)identifier isKindOfClass:NSString.class]) cid=(id)identifier;
    else if ([(id)identifier isKindOfClass:NSUUID.class]) cid=[(NSUUID *)(id)identifier UUIDString];
    if (!cid.length || ![[NSUUID alloc] initWithUUIDString:cid]) {
        
        return [self cgp_configurationWithIdentifier:identifier previewProvider:preview actionProvider:provider];
    }
    NSString *title=sHistoryTitles[cid]?:@"Untitled conversation";
    __weak UIViewController *owner=sMenuOwner;
    
    return [self cgp_configurationWithIdentifier:identifier previewProvider:preview actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIMenu *original=provider?provider(suggested):nil;
        NSMutableArray *children=[NSMutableArray arrayWithArray:original.children?:@[]];
        BOOL exists=NO;
        for (UIMenuElement *item in children) if ([item isKindOfClass:UIAction.class] && [((UIAction *)item).identifier isEqualToString:@"com.551uk.pin-toggle"]) exists=YES;
        if (!exists) [children insertObject:CGPinAction(owner,cid,title) atIndex:0];
        return original?[original menuByReplacingChildren:children]:[UIMenu menuWithTitle:@"" children:children];
    }];
}
@end
static IMP sNativeMenuOne, sNativeMenuMany;
static void CGBeginNativeMenu(id owner, UICollectionView *list, NSIndexPath *index) {
    sMenuID=nil; sMenuTitle=nil; sMenuOwner=nil;
    if (!index || ![owner isKindOfClass:UIViewController.class]) return;
    // The native factory supplies HistoryItem.conversationID as NSString.
    // No visible-label matching and no additional history request are needed.
    sMenuOwner=owner;
}
static id CGNativeMenuOne(id owner,SEL cmd,UICollectionView *list,NSIndexPath *index,CGPoint point) {
    CGBeginNativeMenu(owner,list,index);
    @try { return ((id(*)(id,SEL,id,id,CGPoint))sNativeMenuOne)(owner,cmd,list,index,point); }
    @finally { sMenuID=nil;sMenuTitle=nil;sMenuOwner=nil; }
}
static id CGNativeMenuMany(id owner,SEL cmd,UICollectionView *list,NSArray *indices,CGPoint point) {
    CGBeginNativeMenu(owner,list,indices.count==1?indices.firstObject:nil);
    @try { return ((id(*)(id,SEL,id,id,CGPoint))sNativeMenuMany)(owner,cmd,list,indices,point); }
    @finally { sMenuID=nil;sMenuTitle=nil;sMenuOwner=nil; }
}


static BOOL CGIsHistory(NSURLRequest *request) {
    if (![request.HTTPMethod.uppercaseString isEqualToString:@"GET"]) return NO;
    NSURL *url = request.URL;
    NSString *host = url.host.lowercaseString;
    if (!([host isEqualToString:@"chatgpt.com"] || [host hasSuffix:@".chatgpt.com"] ||
          [host isEqualToString:@"openai.com"] || [host hasSuffix:@".openai.com"])) return NO;
    return [url.path isEqualToString:@"/backend-api/conversations"] ||
           [url.path isEqualToString:@"/backend-api/conversations/"];
}
static BOOL CGIsConversationDetail(NSURLRequest *request) {
    if (![request.HTTPMethod.uppercaseString isEqualToString:@"GET"]) return NO;
    NSURL *url=request.URL;
    NSString *host=url.host.lowercaseString;
    if (!([host isEqualToString:@"chatgpt.com"] || [host hasSuffix:@".chatgpt.com"] ||
          [host isEqualToString:@"openai.com"] || [host hasSuffix:@".openai.com"])) return NO;
    NSArray<NSString *> *parts=[(url.path?:@"") componentsSeparatedByString:@"/"];
    if (parts.count==4 && [parts[1] isEqualToString:@"backend-api"] &&
        [parts[2] isEqualToString:@"conversation"] && [parts[3] length]) return YES;
    if (parts.count==3 && [parts[1] isEqualToString:@"conversation"] &&
        [parts[2] length]) return YES;
    return NO;
}
static NSString * const kDetailRetryHeader=@"X-551UK-Detail-Retry";

// A server timeout is not an empty conversation. Keep the old app's original
// completion pending while transient failures are retried. Authentication and
// permanently missing conversations are not retried.
static BOOL CGDetailRetryable(NSURLResponse *response, NSError *error) {
    NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]
        ?((NSHTTPURLResponse *)response).statusCode:0;
    if (status==408 || status==429 || status==500 || status==502 ||
        status==503 || status==504 || status==520 || status==522 || status==524) return YES;
    if (!error || ![error.domain isEqualToString:NSURLErrorDomain]) return NO;
    switch(error.code) {
        case NSURLErrorTimedOut:
        case NSURLErrorNetworkConnectionLost:
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorCannotFindHost:
        case NSURLErrorNotConnectedToInternet:
            return YES;
        default: return NO;
    }
}
static NSString *sSelectedDetailID;
static NSUInteger sSelectedDetailGeneration=0;
static NSUInteger CGDetailSelected(NSURLRequest *request) {
    NSString *cid=request.URL.path.lastPathComponent;
    @synchronized([NSURLSession class]) {
        if (![sSelectedDetailID isEqualToString:cid]) {
            sSelectedDetailID=[cid copy];
            sSelectedDetailGeneration++;
        }
        return sSelectedDetailGeneration;
    }
}
static BOOL CGDetailStillSelected(NSString *cid, NSUInteger generation) {
    @synchronized([NSURLSession class]) {
        return [sSelectedDetailID isEqualToString:cid] &&
            sSelectedDetailGeneration==generation;
    }
}
static void CGDetailFinishCancelled(void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    if (completion) completion(nil,nil,
        [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
}
static NSTimeInterval CGDetailRetryDelay(NSURLResponse *response, NSUInteger attempt) {
    // No retry count or total-duration cutoff. Pace subsequent attempts to
    // avoid flooding the backend, and always honor Retry-After.
    static const NSTimeInterval backoff[]={2,5,10,20,30,45,60};
    NSTimeInterval delay=backoff[MIN(attempt,6)];
    if (![response isKindOfClass:NSHTTPURLResponse.class]) return delay;
    NSString *value=nil;
    for (id key in ((NSHTTPURLResponse *)response).allHeaderFields) {
        if ([key isKindOfClass:NSString.class] &&
            [key caseInsensitiveCompare:@"Retry-After"]==NSOrderedSame) {
            id raw=((NSHTTPURLResponse *)response).allHeaderFields[key];
            value=[raw isKindOfClass:NSString.class]?raw:[raw description];
            break;
        }
    }
    if (!value.length) return delay;
    NSScanner *scanner=[NSScanner scannerWithString:value];
    double seconds=0;
    if ([scanner scanDouble:&seconds] && scanner.isAtEnd && isfinite(seconds) && seconds>=0)
        return MAX(delay,seconds);
    NSDateFormatter *date=[NSDateFormatter new];
    date.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    date.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];
    date.dateFormat=@"EEE, dd MMM yyyy HH:mm:ss 'GMT'";
    NSDate *retryDate=[date dateFromString:value];
    if (retryDate) return MAX(delay,MAX(0,[retryDate timeIntervalSinceNow]));
    return delay;
}
static void CGRetryConversationDetail(NSURLSessionConfiguration *, NSURLRequest *,
    NSString *, NSUInteger, NSUInteger,
    void (^)(NSData *,NSURLResponse *,NSError *));
static void CGScheduleDetailRetry(NSURLSessionConfiguration *configuration,
    NSURLRequest *request, NSString *cid, NSUInteger generation, NSUInteger attempt,
    NSURLResponse *response, void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    if (!CGDetailStillSelected(cid,generation)) {
        CGDetailFinishCancelled(completion); return;
    }
    NSTimeInterval delay=CGDetailRetryDelay(response,attempt);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        if (!CGDetailStillSelected(cid,generation)) {
            CGDetailFinishCancelled(completion); return;
        }
        CGRetryConversationDetail(configuration,request,cid,generation,MIN(attempt+1,6),completion);
    });
}
static void CGRetryConversationDetail(NSURLSessionConfiguration *configuration,
    NSURLRequest *request, NSString *cid, NSUInteger generation, NSUInteger attempt,
    void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    if (!CGDetailStillSelected(cid,generation)) {
        CGDetailFinishCancelled(completion); return;
    }
    NSMutableURLRequest *retry=[request mutableCopy];
    [retry setValue:@"1" forHTTPHeaderField:kDetailRetryHeader];
    // Preserve the app's timeouts, credentials and network configuration.
    // Each failed server request gets a new attempt, without a total retry cutoff.
    NSURLSessionConfiguration *config=[configuration copy] ?: [NSURLSessionConfiguration defaultSessionConfiguration];
    __block NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
    @try {
        NSURLSessionDataTask *task=[session dataTaskWithRequest:retry completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
            [session finishTasksAndInvalidate];
            session=nil;
            if (!CGDetailStillSelected(cid,generation)) {
                CGDetailFinishCancelled(completion); return;
            }
            if (CGDetailRetryable(response,error)) {
                CGScheduleDetailRetry(configuration,request,cid,generation,attempt,response,completion);
                return;
            }
            completion(data,response,error);
        }];
        if (task) [task resume];
        else {
            [session invalidateAndCancel]; session=nil;
            CGScheduleDetailRetry(configuration,request,cid,generation,attempt,nil,completion);
        }
    } @catch(__unused NSException *exception) {
        [session invalidateAndCancel]; session=nil;
        CGScheduleDetailRetry(configuration,request,cid,generation,attempt,nil,completion);
    }
}
static void CGRefreshPins(void) {
    NSURLSession *session = sMenuSession ?: sSession;
    NSURLRequest *request = sHistoryRequest;
    if (!session || !request) return;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (sRefreshing || sPinWrites.count || now - sLastRefresh < 12) return;
    sRefreshing = YES; sLastRefresh = now;
    
    [sPins refreshWithSession:session authenticatedHistoryRequest:request
                  completion:^(BOOL accepted, NSError *error) {
        sRefreshing = NO;
        if ([error.domain isEqualToString:@"com.551uk.pins"] &&
            error.code == CGPinsSessionInvalidated && sSession == session) {
            // Do not clear the pin store or discard a newer captured session.
            sSession = nil;
            sLastRefresh = 0;
            
        }
        
        if (accepted) [[NSNotificationCenter defaultCenter]
            postNotificationName:kUpdated object:nil];
    }];
}
static void CGSeeHistory(NSURLSession *session, NSURLRequest *request) {
    if (session==sMenuSession || !CGIsHistory(request) ||
        ([[request valueForHTTPHeaderField:@"X-551UK-History-Retry"] isEqualToString:@"1"] ||
         [[request valueForHTTPHeaderField:@"X-551UK-History-Merge"] isEqualToString:@"1"])) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *oldAuth=[sHistoryRequest valueForHTTPHeaderField:@"Authorization"];
        NSString *newAuth=[request valueForHTTPHeaderField:@"Authorization"];
        // Do not replace an authenticated request with a headerless outer task.
        if(oldAuth.length && !newAuth.length)return;
        if(oldAuth.length && newAuth.length && ![oldAuth isEqualToString:newAuth]) {
            sPins=[CGPinnedSectionStore new];
            [sHistoryTitles removeAllObjects];
            sLastRefresh=0;
            [[NSNotificationCenter defaultCenter] postNotificationName:kUpdated object:nil];
        }
        sSession=session;
        sHistoryRequest=[request copy];
        if (!sMenuSession || (oldAuth.length && newAuth.length && ![oldAuth isEqualToString:newAuth])) {
            [sMenuSession finishTasksAndInvalidate];
            // Own the lifetime; the app invalidates its short-lived history sessions.
            NSURLSessionConfiguration *config=[session.configuration copy];
            config.timeoutIntervalForRequest=30;
            sMenuSession=[NSURLSession sessionWithConfiguration:config];
            
        }
        CGRefreshPins();
    });
}

@interface NSURLSession (CGPinsHook)
- (NSURLSessionDataTask *)cgp_dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)cgp_dataTaskWithRequest:(NSURLRequest *)request
                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
@end
@implementation NSURLSession (CGPinsHook)
- (NSURLSessionDataTask *)cgp_dataTaskWithRequest:(NSURLRequest *)request {
    BOOL detailRetry=[[request valueForHTTPHeaderField:kDetailRetryHeader] length]>0;
    if (CGIsConversationDetail(request) && !detailRetry) {
        CGDetailSelected(request);
        CGOriginMergeConversationDidOpen();
    }
    NSURLSessionDataTask *task = [self cgp_dataTaskWithRequest:request];
    CGSeeHistory(self,request);
    return task;
}
- (NSURLSessionDataTask *)cgp_dataTaskWithRequest:(NSURLRequest *)request
              completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    BOOL isDetail=CGIsConversationDetail(request);
    BOOL detailRetry=[[request valueForHTTPHeaderField:kDetailRetryHeader] length]>0;
    NSUInteger detailGeneration=0;
    NSString *detailCID=nil;
    if (isDetail && !detailRetry) {
        detailCID=request.URL.lastPathComponent;
        detailGeneration=CGDetailSelected(request);
        CGOriginMergeConversationDidOpen();
    }
    void (^forward)(NSData *,NSURLResponse *,NSError *)=completion;

    if (completion && isDetail && !detailRetry) {
        void (^originalDetailForward)(NSData *,NSURLResponse *,NSError *)=forward;
        NSURLSessionConfiguration *detailConfig=[self.configuration copy];
        forward=^(NSData *data,NSURLResponse *response,NSError *error) {
            if (!CGDetailStillSelected(detailCID,detailGeneration)) {
                CGDetailFinishCancelled(originalDetailForward);
                return;
            }
            if (CGDetailRetryable(response,error)) {
                CGScheduleDetailRetry(detailConfig,request,detailCID,detailGeneration,0,response,originalDetailForward);
                return;
            }
            originalDetailForward(data,response,error);
        };
    }

    if (completion && self!=sMenuSession && CGIsHistory(request) &&
        ![[request valueForHTTPHeaderField:@"X-551UK-History-Retry"] isEqualToString:@"1"] &&
        ![[request valueForHTTPHeaderField:@"X-551UK-History-Merge"] isEqualToString:@"1"]) {
        void (^originalForward)(NSData *,NSURLResponse *,NSError *)=forward;
        NSURLSessionConfiguration *historyConfig=[self.configuration copy];
        forward=^(NSData *data,NSURLResponse *response,NSError *error) {
            CGHistoryPageResult(request,historyConfig,data,response,error,
                ^(NSData *usableData,NSURLResponse *usableResponse,NSError *usableError) {
                    CGOriginMergePage(historyConfig,request,usableData,usableResponse,usableError,
                        ^(NSData *combined,NSURLResponse *combinedResponse,NSError *combinedError) {
                            if (!combinedError) CGRememberHistory(combined);
                            originalForward(combined,combinedResponse,combinedError);
                        });
                });
        };
    }
    // Resolve modern web citation markers before the 2024 app renders them.
    // This is deliberately the outermost wrapper so it applies to normal
    // conversation loads, retry loads, and any other completion-based JSON.
    if (forward) {
        void (^citationForward)(NSData *,NSURLResponse *,NSError *)=forward;
        forward=^(NSData *data,NSURLResponse *response,NSError *error) {
            citationForward(CGRCitationCompatRewriteJSONData(data),response,error);
        };
    }
    NSURLSessionDataTask *task = [self cgp_dataTaskWithRequest:request completionHandler:forward];
    CGSeeHistory(self,request);
    return task;
}
@end

static UICollectionView *CGFindList(UIView *view) {
    if ([view isKindOfClass:UICollectionView.class]) return (UICollectionView *)view;
    for (UIView *sub in view.subviews) {
        UICollectionView *result = CGFindList(sub);
        if (result) return result;
    }
    return nil;
}
// Native collection item identifiers can be Swift wrappers. Do not assume
// the pin record ID equals a collection item's private identifier.
static NSString *CGID(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    for (NSString *key in @[@"conversationID",@"conversationId",@"conversation_id"]) {
        @try {
            id field = [value valueForKey:key];
            if ([field isKindOfClass:NSString.class]) return field;
            if ([field respondsToSelector:@selector(UUIDString)]) return [field UUIDString];
        } @catch (__unused NSException *ex) {}
    }
    return nil;
}

/*
 * The old implementation used contentInset.top and therefore placed pins
 * *above the GPT shortcuts*. Instead, locate the first date-group heading
 * (Today/Yesterday...) and use its original collection-content Y as the
 * insertion point. Shift only native date-group cells and headers downward.
 * Original cells, delegates, and their index paths remain unchanged.
 */
/*
 * Search labels exposed either as UIKit UILabels OR as accessible SwiftUI
 * hosting views. SwiftUI Text does not have to create a UILabel.
 * Return the immediate collection-view child containing the target text.
 */
static BOOL CGContainsLabel(NSString *candidate, NSString *expected) {
    if (!candidate.length || !expected.length) return NO;
    NSString *normal=[[candidate stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    NSString *wanted=expected.lowercaseString;
    return [normal isEqualToString:wanted] ||
           [normal hasPrefix:[wanted stringByAppendingString:@","]] ||
           [normal hasPrefix:[wanted stringByAppendingString:@" "]];
}
static UIView *CGFindTextContainer(UIView *root, UICollectionView *list,
                                   BOOL (^predicate)(NSString *)) {
    if (root!=list && [root isKindOfClass:CGPinnedSidebarView.class]) return nil;
    NSMutableArray<NSString *> *labels=[NSMutableArray array];
    if ([root isKindOfClass:UILabel.class]) {
        NSString *title=((UILabel *)root).text;
        if (title.length) [labels addObject:title];
    }
    if ([root isKindOfClass:UIButton.class]) {
        NSString *title=[((UIButton *)root) titleForState:UIControlStateNormal];
        if (title.length) [labels addObject:title];
    }
    if (root.accessibilityLabel.length)
        [labels addObject:root.accessibilityLabel];
    for (NSString *candidate in labels) {
        if (!predicate(candidate)) continue;
        UIView *direct=root;
        while (direct.superview && direct.superview!=list)
            direct=direct.superview;
        if (direct.superview==list) return direct;
    }
    for (UIView *sub in root.subviews) {
        UIView *result=CGFindTextContainer(sub,list,predicate);
        if (result) return result;
    }
    return nil;
}
static CGFloat CGContentYOfView(UIView *view, UICollectionView *list, BOOL bottom) {
    if (!view || !list) return NAN;
    CGRect frame=[view convertRect:view.bounds toView:list];
    return bottom ? CGRectGetMaxY(frame) : CGRectGetMinY(frame);
}
// The 2024 sidebar's Search control may be a UIKit UITextField hosted in
// SwiftUI rather than UISearchBar; locate either without creating fake routes.
static UIView *CGFindNativeSearch(UIView *root) {
    if ([root isKindOfClass:UISearchBar.class]) return root;
    if ([root isKindOfClass:UITextField.class]) {
        UITextField *input=(UITextField *)root;
        if ([input.placeholder.lowercaseString containsString:@"search"] ||
            [input.accessibilityLabel.lowercaseString containsString:@"search"])
            return input;
    }
    for (UIView *sub in root.subviews) {
        UIView *found=CGFindNativeSearch(sub);
        if (found) return found;
    }
    return nil;
}
static NSString *CGSearchText(UIView *search) {
    if ([search isKindOfClass:UISearchBar.class]) return ((UISearchBar *)search).text ?: @"";
    if ([search isKindOfClass:UITextField.class]) return ((UITextField *)search).text ?: @"";
    return @"";
}
extern BOOL CG46OpenPin(UIViewController *, NSString *, NSString *);

/*
 * Prefer the first date heading. If it is a SwiftUI-rendered collection
 * supplementary view, take its actual UIKit layout frame instead.
 * Last resort: anchor after the visible "Explore GPTs" shortcut.
 * Don't silently discard verified pinned records when the text isn't UILabel.
 */
static CGFloat CGInsertionY(UICollectionView *list) {
    NSNumber *cached=objc_getAssociatedObject(list,&kPinAnchor);
    if (cached) return cached.doubleValue;

    UIView *heading=CGFindTextContainer(list,list,^BOOL(NSString *text) {
        for (NSString *date in @[@"Today",@"Yesterday",@"Previous 7 Days",
             @"Last 7 Days",@"Previous 30 Days",@"Last 30 Days",
             @"This Week",@"Last Week",@"Older",@"This Month",@"Last Month"]) {
            if (CGContainsLabel(text,date)) return YES;
        }
        return NO;
    });
    CGFloat anchor=NAN;
    if (heading) {
        anchor=CGContentYOfView(heading,list,NO);
    }
    // A visible Explore GPTs shortcut is the most reliable boundary when
    // SwiftUI does not expose the Today heading as a UIKit label.
    if (!isfinite(anchor) || anchor<=0) {
        UIView *explore=CGFindTextContainer(list,list,^BOOL(NSString *text) {
            return CGContainsLabel(text,@"Explore GPTs");
        });
        if (explore) {
            anchor=CGContentYOfView(explore,list,YES)+16;
        }
    }
    // Fall back to collection-section header frames if the shortcut is
    // not accessible; never assume SwiftUI Text is backed by UILabel.
    if (!isfinite(anchor) || anchor<=0) {
        NSArray *headers=[list visibleSupplementaryViewsOfKind:
            UICollectionElementKindSectionHeader];
        CGFloat best=CGFLOAT_MAX;
        for (UICollectionReusableView *header in headers) {
            CGFloat y=CGContentYOfView(header,list,NO);
            if (isfinite(y) && y>12 && y<best) best=y;
        }
        if (best!=CGFLOAT_MAX) {
            anchor=best;
        }
    }
    // UICollectionView may not render offscreen headers on the initial pass.
    // Use the first actual later-section item/heading layout attribute.
    if (!isfinite(anchor) || anchor<=0) {
        NSInteger sections=[list numberOfSections];
        for (NSInteger section=1;section<sections;section++) {
            NSIndexPath *index=[NSIndexPath indexPathForItem:0 inSection:section];
            UICollectionViewLayoutAttributes *attr=
                [list.collectionViewLayout layoutAttributesForItemAtIndexPath:index];
            if (attr && CGRectGetMinY(attr.frame)>20) {
                anchor=CGRectGetMinY(attr.frame)-32;
                break;
            }
        }
    }
    // A low layout-derived anchor (for example y=16 in earlier diagnostics)
    // sits inside the GPT shortcuts rather than below Explore GPTs.
    // Do not cache or show a pinned panel at an unverified position.
    if (isfinite(anchor) && anchor<90) {
        
        anchor=NAN;
    }
    if (!isfinite(anchor) || anchor<=0) {
        static NSTimeInterval lastFailure=0;
        NSTimeInterval now=NSDate.date.timeIntervalSince1970;
        if (now-lastFailure>5) {
            lastFailure=now;
            
        }
        return NAN;
    }
    objc_setAssociatedObject(list,&kPinAnchor,@(anchor),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    return anchor;
}
static void CGRender(id controller) {
    if (![controller isKindOfClass:UIViewController.class]) return;
    UIViewController *vc=(UIViewController *)controller;
    UICollectionView *list=CGFindList(vc.view);
    if (!list) return;
    CGFloat anchor = CGInsertionY(list);
    if (isnan(anchor)) return;
    CGPinnedSidebarView *pinned=objc_getAssociatedObject(list,&kPinView);
    if (!pinned) {
        pinned=[[CGPinnedSidebarView alloc] initWithFrame:CGRectZero];
        pinned.translatesAutoresizingMaskIntoConstraints=YES;
        [list addSubview:pinned];
        objc_setAssociatedObject(list,&kPinView,pinned,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIViewController *weakVC=vc;
        pinned.selectionHandler=^(CGPinnedSectionEntry *entry) {
            UIViewController *owner=weakVC;
            if (!owner || !entry.pin.conversationID.length) return;
            
            CG46OpenPin(owner,entry.pin.conversationID,entry.pin.title);
            
        };
        pinned.menuHandler=^UIMenu *(CGPinnedSectionEntry *entry) {
            return [UIMenu menuWithTitle:@"" children:@[CGPinAction(weakVC,entry.pin.conversationID,entry.pin.title)]];
        };
        pinned.heightDidChange=^{
            UIViewController *owner=weakVC;
            if (owner) CGRender(owner);
        };
        
    }
    NSArray *pins=sPins.currentPins;
    if (objc_getAssociatedObject(list,&kRenderedPinSet)!=pins) {
        CGPinnedSectionLayout *layout=[sPins layoutForHistoryRows:@[]
                                             conversationIDForRow:^NSString *(id row) {
            return CGID(row);
        }];
        [pinned applyLayout:layout];
        objc_setAssociatedObject(list,&kRenderedPinSet,pins,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *search=CGFindNativeSearch(vc.view);
    BOOL inSearch=CGSearchText(search).length>0;
    CGFloat height = sPins.hasVerifiedServerList && pins.count && !inSearch
        ? pinned.preferredHeight+8 : 0;
    // Reserve the space inside the native UICollectionViewLayout.
    // Never move a cell frame or transform: UIKit reuses/repositions those
    // and manual edits corrupt row heights / make text overlap.
    BOOL positioned=CGPinSetLayoutSpace(list,anchor,height);
    if (!positioned) {
        static NSTimeInterval lastFailed=0;
        NSTimeInterval now=NSDate.date.timeIntervalSince1970;
        if (now-lastFailed>8) {
            
            lastFailed=now;
        }
        height=0; // no overlay if we cannot reserve genuine layout space
    }
    pinned.hidden=height<1;
    pinned.frame=CGRectMake(0,anchor,list.bounds.size.width,height>0?height-8:0);
    [list bringSubviewToFront:pinned];
}
static void CGHistoryLayout(id self, SEL command) {
    ((void(*)(id, SEL))sOriginalLayout)(self,command);
    CGRender(self);
}
static void CGHistoryScroll(id self, SEL command, UIScrollView *scroll) {
    if (sOriginalScroll) ((void(*)(id,SEL,UIScrollView *))sOriginalScroll)(self,command,scroll);
    CGRender(self);
}
static void CGHistoryAppear(id self, SEL command, BOOL animated) {
    ((void(*)(id, SEL, BOOL))sOriginalAppear)(self,command,animated);
    CGRefreshPins();
    CGRender(self);
}
static void CGInstallNativeHook(void) {
    if (sNativeHookInstalled) return;
    Class cls = objc_getClass("_TtC14ChatGPTHistory21HistoryViewController");
    if (!cls) {  return; }
    Method layout = class_getInstanceMethod(cls,@selector(viewDidLayoutSubviews));
    Method appear = class_getInstanceMethod(cls,@selector(viewDidAppear:));
    if (!layout || !appear) {  return; }
    Method scroll=class_getInstanceMethod(cls,@selector(scrollViewDidScroll:));
    if (scroll) {
        sOriginalScroll=method_getImplementation(scroll);
        class_replaceMethod(cls,@selector(scrollViewDidScroll:),
                             (IMP)CGHistoryScroll,method_getTypeEncoding(scroll));
    }
    sOriginalLayout = method_getImplementation(layout);
    sOriginalAppear = method_getImplementation(appear);
    class_replaceMethod(cls,@selector(viewDidLayoutSubviews),
        (IMP)CGHistoryLayout,method_getTypeEncoding(layout));
    class_replaceMethod(cls,@selector(viewDidAppear:),
        (IMP)CGHistoryAppear,method_getTypeEncoding(appear));
    SEL one=@selector(collectionView:contextMenuConfigurationForItemAtIndexPath:point:);
    SEL many=@selector(collectionView:contextMenuConfigurationForItemsAtIndexPaths:point:);
    Method m=class_getInstanceMethod(cls,one);
    if(m) { sNativeMenuOne=method_getImplementation(m); class_replaceMethod(cls,one,(IMP)CGNativeMenuOne,method_getTypeEncoding(m)); }
    m=class_getInstanceMethod(cls,many);
    if(m) { sNativeMenuMany=method_getImplementation(m); class_replaceMethod(cls,many,(IMP)CGNativeMenuMany,method_getTypeEncoding(m)); }
    
    sNativeHookInstalled = YES;
    
}
static void CGPinsDidChange(NSNotification *notification) {
    (void)notification;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        NSMutableArray<UIViewController *> *stack = [NSMutableArray array];
        if (window.rootViewController) [stack addObject:window.rootViewController];
        while (stack.count) {
            UIViewController *vc = stack.lastObject; [stack removeLastObject];
            if ([NSStringFromClass(vc.class) containsString:@"HistoryViewController"])
                CGRender(vc);
            [stack addObjectsFromArray:vc.childViewControllers];
            if (vc.presentedViewController) [stack addObject:vc.presentedViewController];
        }
    }
}
__attribute__((constructor)) static void CGPinnedBoot(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
        CGRCompatibilityEnsureLoaded();
        sPins = [CGPinnedSectionStore new];
        sPinWrites=[NSMutableSet set]; sHistoryTitles=[NSMutableDictionary dictionary];
        Method mf=class_getClassMethod(UIContextMenuConfiguration.class,@selector(configurationWithIdentifier:previewProvider:actionProvider:));
        Method mw=class_getClassMethod(UIContextMenuConfiguration.class,@selector(cgp_configurationWithIdentifier:previewProvider:actionProvider:));
        if(mf && mw) method_exchangeImplementations(mf,mw);
        Method a = class_getInstanceMethod(NSURLSession.class,
             @selector(dataTaskWithRequest:));
        Method b = class_getInstanceMethod(NSURLSession.class,
             @selector(cgp_dataTaskWithRequest:));
        Method c = class_getInstanceMethod(NSURLSession.class,
             @selector(dataTaskWithRequest:completionHandler:));
        Method d = class_getInstanceMethod(NSURLSession.class,
             @selector(cgp_dataTaskWithRequest:completionHandler:));
        if (a && b) method_exchangeImplementations(a,b);
        if (c && d) method_exchangeImplementations(c,d);
        dispatch_async(dispatch_get_main_queue(), ^{
            CGInstallNativeHook();
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                 object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
                    CGInstallNativeHook();
                    CGRefreshPins();
                 }];
            [[NSNotificationCenter defaultCenter] addObserverForName:kUpdated
                    object:nil queue:NSOperationQueue.mainQueue usingBlock:
                    ^(NSNotification *note) { CGPinsDidChange(note); }];
        });
        
    }
}
