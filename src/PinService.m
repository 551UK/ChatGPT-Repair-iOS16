// PinService.m — 551UK, GPL-3.0
// Source-only service for the browser-observed GET
// /backend-api/pins?item_type=conversation.
// No data is fetched until CGFetchPins is called explicitly.
#import "PinService.h"

@implementation CGPinnedConversation
- (instancetype)initWithID:(NSString *)conversationID
                     title:(NSString *)title
                  pinnedAt:(NSString *)pinnedAt {
    if (!(self = [super init])) return nil;
    _conversationID = [conversationID copy];
    _title = [title copy];
    _pinnedAt = [pinnedAt copy];
    return self;
}
@end

@implementation CGPinsResult
- (instancetype)initWithConversations:(NSArray<CGPinnedConversation *> *)conversations
                       examinedItems:(NSUInteger)examinedItems
                        skippedItems:(NSUInteger)skippedItems
                  recognizedResponse:(BOOL)recognizedResponse
                          nextCursor:(NSString *)nextCursor {
    if (!(self = [super init])) return nil;
    _conversations = [conversations copy];
    _examinedItems = examinedItems;
    _skippedItems = skippedItems;
    _recognizedResponse = recognizedResponse;
    _nextCursor = [nextCursor copy];
    return self;
}
@end

static NSString *CGValidString(id value) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *candidate = [(NSString *)value
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return candidate.length && candidate.length <= 300 ? candidate : nil;
}

static id CGFirstObject(NSDictionary *obj, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = obj[key];
        if (value && value != [NSNull null]) return value;
    }
    return nil;
}

static NSDictionary *CGDictionary(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSArray *CGExtractPinArray(id json, BOOL *recognized, NSString **nextCursor) {
    if ([json isKindOfClass:[NSArray class]]) {
        *recognized = YES; return json;
    }
    NSDictionary *root = CGDictionary(json);
    if (!root) return nil;
    NSArray<NSString *> *keys = @[@"items", @"pins", @"pinned_conversations", @"pinnedConversations"];
    for (NSString *key in keys) {
        id value = root[key];
        if ([value isKindOfClass:[NSArray class]]) {
            *recognized = YES;
            *nextCursor = CGValidString(CGFirstObject(root, @[@"next_cursor", @"nextCursor"]));
            return value;
        }
    }
    NSDictionary *data = CGDictionary(root[@"data"]);
    if (data) {
        for (NSString *key in keys) {
            id value = data[key];
            if ([value isKindOfClass:[NSArray class]]) {
                *recognized = YES;
                *nextCursor = CGValidString(CGFirstObject(data, @[@"next_cursor", @"nextCursor"]));
                return value;
            }
        }
    }
    return nil;
}

CGPinsResult *CGParsePinsJSON(NSData *data) {
    BOOL recognized = NO;
    NSString *nextCursor = nil;
    id root = data.length ? [NSJSONSerialization JSONObjectWithData:data
                                               options:0 error:NULL] : nil;
    NSArray *items = CGExtractPinArray(root, &recognized, &nextCursor);
    NSMutableArray<CGPinnedConversation *> *pins = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSUInteger skipped = 0;
    for (id value in items) {
        NSDictionary *entry = CGDictionary(value);
        if (!entry) { skipped++; continue; }
        // Never mistake a pin-record's own "id" for a conversation ID.
        NSString *pinnedAt = CGValidString(entry[@"pinned_at"]) ?: @"";
        NSString *type = CGValidString(CGFirstObject(entry,
                               @[@"item_type", @"itemType", @"type"]));
        if (type && ![type isEqualToString:@"conversation"]) { skipped++; continue; }
        NSDictionary *conversation = CGDictionary(entry[@"conversation"]);
        NSDictionary *item = CGDictionary(entry[@"item"]);
        NSString *cid = CGValidString(CGFirstObject(entry,
                          @[@"conversation_id", @"conversationId", @"item_id", @"itemId"]));
        if (!cid && conversation) cid = CGValidString(CGFirstObject(conversation,
                                             @[@"conversation_id", @"conversationId", @"id"]));
        if (!cid && item) cid = CGValidString(CGFirstObject(item,
                                             @[@"conversation_id", @"conversationId", @"id"]));
        if (!cid) { skipped++; continue; }
        // Titles may not be included in the pin record. A later UI module
        // should resolve them from the app's existing history cache, not
        // display the pin record's ID as a fake title.
        NSString *title = CGValidString(CGFirstObject(entry,
                                             @[@"title", @"conversation_title", @"conversationTitle"]));
        if (!title && conversation) title = CGValidString(conversation[@"title"]);
        if (!title && item) title = CGValidString(item[@"title"]);
        if ([seen containsObject:cid]) continue;
        [seen addObject:cid];
        [pins addObject:[[CGPinnedConversation alloc] initWithID:cid
                                                 title:title ?: @"" pinnedAt:pinnedAt]];
    }
    return [[CGPinsResult alloc] initWithConversations:pins
                                        examinedItems:items.count
                                         skippedItems:skipped
                                   recognizedResponse:recognized
                                           nextCursor:nextCursor];
}

static BOOL CGTrustedHost(NSString *host) {
    NSString *h = host.lowercaseString;
    return [h isEqualToString:@"chatgpt.com"] ||
           [h hasSuffix:@".chatgpt.com"] ||
           [h isEqualToString:@"openai.com"] ||
           [h hasSuffix:@".openai.com"];
}

NSURLRequest *CGPinsRequestFromHistoryRequest(NSURLRequest *historyRequest) {
    if (!historyRequest || !CGTrustedHost(historyRequest.URL.host)) return nil;
    if (![historyRequest.HTTPMethod.uppercaseString isEqualToString:@"GET"]) return nil;
    NSString *path = historyRequest.URL.path;
    if (!([path isEqualToString:@"/backend-api/conversations"] ||
          [path isEqualToString:@"/backend-api/conversations/"])) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:historyRequest.URL
                                         resolvingAgainstBaseURL:NO];
    parts.path = @"/backend-api/pins";
    parts.queryItems = @[[NSURLQueryItem queryItemWithName:@"item_type"
                                                    value:@"conversation"]];
    NSURL *url = parts.URL;
    if (!url || !CGTrustedHost(url.host)) return nil;
    NSMutableURLRequest *request = [historyRequest mutableCopy];
    request.URL = url;
    request.HTTPMethod = @"GET";
    request.HTTPBody = nil;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    // Any existing account credentials stay only inside the URL request
    // managed by the same app session. Never save these to disk or log.
    return request;
}

void CGFetchPins(NSURLSession *session,
                 NSURLRequest *authenticatedHistoryRequest,
                 CGPinsCompletion completion) {
    NSURLRequest *request = CGPinsRequestFromHistoryRequest(authenticatedHistoryRequest);
    if (!session || !request) {
        if (completion) completion(nil, [NSError errorWithDomain:@"com.551uk.pins"
                                code:1 userInfo:@{NSLocalizedDescriptionKey:
                                  @"An authenticated history request/session is needed"}]);
        return;
    }
    NSURLSessionDataTask *task = nil;
    @try {
        task = [session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) { if (completion) completion(nil,error); return; }
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
                ? ((NSHTTPURLResponse *)response).statusCode : 0;
            if (status != 200 || data.length > 2 * 1024 * 1024) {
                if (completion) completion(nil, [NSError errorWithDomain:@"com.551uk.pins"
                  code:status ?: 2 userInfo:@{NSLocalizedDescriptionKey:
                                   @"Pinned-conversation response was not usable"}]);
                return;
            }
            CGPinsResult *parsed = CGParsePinsJSON(data ?: [NSData data]);
            if (completion) completion(parsed,nil);
        }];
    } @catch (NSException *exception) {
        // The app may invalidate its captured session between sidebar visits.
        // Catch only CFNetwork's reported task-creation failure, not unrelated
        // exceptions or errors in the app's normal history requests.
        if (![exception.name isEqualToString:NSGenericException] || !exception.reason.length ||
            [exception.reason rangeOfString:@"session that has been invalidated"
                                   options:NSCaseInsensitiveSearch].location == NSNotFound) {
            @throw;
        }
        if (completion) completion(nil, [NSError errorWithDomain:@"com.551uk.pins"
            code:CGPinsSessionInvalidated userInfo:@{NSLocalizedDescriptionKey:
                @"Pins refresh deferred until a fresh app session is available"}]);
        return;
    }
    [task resume];
}
