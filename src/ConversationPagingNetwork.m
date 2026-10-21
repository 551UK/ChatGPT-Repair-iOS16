#import "ConversationPagingCompat.h"
#import "ConversationPagingState.h"
#import "ConversationPagingCore.h"

NSURLRequest *CGConversationPagingPrepareDetailRequest(NSURLRequest *originalRequest,
                                                        NSUInteger *generationOut) {
    if (generationOut) *generationOut=0;
    NSString *cid=CGPagingConversationID(originalRequest);
    if (!cid.length) return originalRequest;
    @synchronized(CGPagingStateLock()) {
        if (![CGPagingSelectedID isEqualToString:cid]) {
            CGPagingSelectedID=[cid copy];
            CGPagingGeneration++;
            CGPagingState=nil;
        }
        if (generationOut) *generationOut=CGPagingGeneration;
    }
    return CGPagingModernRequest(originalRequest,nil);
}

void CGConversationPagingProcessDetailResponse(
    NSURLSessionConfiguration *configuration, NSURLRequest *originalRequest,
    NSUInteger generation, NSData *data, NSURLResponse *response, NSError *error,
    void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    NSString *cid=CGPagingConversationID(originalRequest);
    if (!cid.length || !generation || !completion) { if (completion) completion(data,response,error); return; }
    if (!CGPagingStillActive(cid,generation)) { completion(data,response,error); return; }

    NSInteger status=CGPagingStatus(response);
    if (error || status<200 || status>=300) {
        if (!error && CGPagingCompatibilityFailure(status))
            CGPagingFetchLegacy(configuration,originalRequest,cid,generation,completion);
        else completion(data,response,error);
        return;
    }

    NSDictionary *root=CGConversationPagingJSONObject(data);
    BOOL hasPrevious=NO;
    NSString *cursor=nil;
    if (!root || !CGPagingValidPageRoot(root,&hasPrevious,&cursor) || CGConversationPagingHasVersionMarkers(root)) {
        CGPagingFetchLegacy(configuration,originalRequest,cid,generation,completion);
        return;
    }

    NSArray *newest=CGConversationPagingMessages(root);
    NSArray *merged=newest;
    NSString *current=[root[@"current_node"] isKindOfClass:NSString.class]?root[@"current_node"]:nil;
    if (!current.length) {
        NSDictionary *raw=[newest.lastObject isKindOfClass:NSDictionary.class]?newest.lastObject:nil;
        NSDictionary *message=[raw[@"message"] isKindOfClass:NSDictionary.class]?raw[@"message"]:raw;
        id identifier=message[@"id"] ?: message[@"message_id"];
        if ([identifier isKindOfClass:NSString.class]) current=identifier;
    }

    BOOL stale=NO;
    @synchronized(CGPagingStateLock()) {
        if (![CGPagingSelectedID isEqualToString:cid] || CGPagingGeneration!=generation) stale=YES;
        if (!stale) {
            CGConversationPagingState *state=CGPagingState;
            if (!state || ![state.conversationID isEqualToString:cid] || state.generation!=generation) {
                state=[CGConversationPagingState new];
                state.conversationID=cid; state.generation=generation; CGPagingState=state;
            }
            if (state.loadedOlder && state.messages.count) merged=CGConversationPagingMergeMessages(state.messages,newest);
            state.messages=merged;
            state.baseRoot=root;
            if (current.length) state.currentNode=current;
            if (!state.loadedOlder) { state.startCursor=cursor; state.hasPrevious=hasPrevious; }
            state.originalRequest=[originalRequest copy];
            state.configuration=[configuration copy] ?: [NSURLSessionConfiguration defaultSessionConfiguration];
            state.responseTemplate=response;
            state.completion=[completion copy];
            state.loadingOlder=NO;
        }
    }
    if (stale) { completion(data,response,error); return; }

    NSData *legacy=CGConversationPagingLegacyData(root,merged,current);
    if (!legacy.length) { CGPagingFetchLegacy(configuration,originalRequest,cid,generation,completion); return; }
    completion(legacy,CGPagingLegacyResponse(response,originalRequest.URL,legacy.length),nil);
    CGConversationPagingInstallScrollHook();
}
