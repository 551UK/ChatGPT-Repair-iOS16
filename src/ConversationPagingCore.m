// ChatGPTRepair: Assemble older conversation pages into the legacy message mapping.
#import "ConversationPagingCore.h"

static NSDictionary *CGPagingMessageObject(id raw) {
    if (![raw isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *row=raw;
    NSDictionary *nested=[row[@"message"] isKindOfClass:NSDictionary.class]?row[@"message"]:nil;
    return nested ?: row;
}

static NSString *CGPagingMessageID(id raw) {
    NSDictionary *message=CGPagingMessageObject(raw);
    id identifier=message[@"id"];
    if (![identifier isKindOfClass:NSString.class] || ![(NSString *)identifier length])
        identifier=message[@"message_id"];
    if (![identifier isKindOfClass:NSString.class] || ![(NSString *)identifier length]) {
        if ([raw isKindOfClass:NSDictionary.class]) {
            identifier=((NSDictionary *)raw)[@"id"];
            if (![identifier isKindOfClass:NSString.class] || ![(NSString *)identifier length])
                identifier=((NSDictionary *)raw)[@"message_id"];
        }
    }
    return [identifier isKindOfClass:NSString.class] && [(NSString *)identifier length]
        ? identifier : nil;
}

NSDictionary *CGConversationPagingJSONObject(NSData *data) {
    if (!data.length || data.length>32*1024*1024) return nil;
    id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [json isKindOfClass:NSDictionary.class]?json:nil;
}

NSArray *CGConversationPagingMessages(NSDictionary *root) {
    id messages=[root isKindOfClass:NSDictionary.class]?root[@"messages"]:nil;
    return [messages isKindOfClass:NSArray.class]?messages:@[];
}

NSString *CGConversationPagingStartCursor(NSDictionary *root, BOOL *hasPrevious) {
    if (hasPrevious) *hasPrevious=NO;
    NSDictionary *page=[root[@"page_info"] isKindOfClass:NSDictionary.class]?root[@"page_info"]:nil;
    if (!page) return nil;
    id previous=page[@"has_previous_page"];
    BOOL has=[previous respondsToSelector:@selector(boolValue)]?[previous boolValue]:NO;
    if (hasPrevious) *hasPrevious=has;
    id cursor=page[@"start_cursor"];
    return [cursor isKindOfClass:NSString.class] && [(NSString *)cursor length]
        ? cursor : nil;
}

NSArray *CGConversationPagingMergeMessages(NSArray *older, NSArray *newer) {
    NSMutableArray<NSString *> *order=[NSMutableArray array];
    NSMutableDictionary<NSString *,id> *byID=[NSMutableDictionary dictionary];
    for (NSArray *source in @[older?:@[],newer?:@[]]) {
        for (id raw in source) {
            NSString *identifier=CGPagingMessageID(raw);
            if (!identifier.length) continue;
            if (!byID[identifier]) [order addObject:identifier];
            byID[identifier]=raw;
        }
    }
    NSMutableArray *result=[NSMutableArray arrayWithCapacity:order.count];
    for (NSString *identifier in order) {
        id raw=byID[identifier];
        if (raw) [result addObject:raw];
    }
    return result;
}

NSData *CGConversationPagingLegacyData(NSDictionary *root, NSArray *messages,
                                       NSString *currentNodeOverride) {
    if (![root isKindOfClass:NSDictionary.class] || ![messages isKindOfClass:NSArray.class]) return nil;

    NSMutableArray<NSDictionary *> *valid=[NSMutableArray array];
    NSMutableArray<NSString *> *ids=[NSMutableArray array];
    NSMutableSet<NSString *> *seen=[NSMutableSet set];
    for (id raw in messages) {
        NSDictionary *message=CGPagingMessageObject(raw);
        NSString *identifier=CGPagingMessageID(raw);
        if (!message || !identifier.length || [seen containsObject:identifier]) continue;
        [seen addObject:identifier];
        [valid addObject:message];
        [ids addObject:identifier];
    }
    if (!valid.count) return nil;

    NSString *rootID=@"client-created-root";
    if ([seen containsObject:rootID]) rootID=@"551uk-pagination-root";
    NSMutableDictionary *mapping=[NSMutableDictionary dictionaryWithCapacity:valid.count+1];
    mapping[rootID]=@{
        @"id":rootID,
        @"message":[NSNull null],
        @"parent":[NSNull null],
        @"children":ids.count?@[ids.firstObject]:@[]
    };

    for (NSUInteger index=0;index<valid.count;index++) {
        NSString *identifier=ids[index];
        NSString *parent=index?ids[index-1]:rootID;
        NSArray *children=(index+1<ids.count)?@[ids[index+1]]:@[];
        mapping[identifier]=@{
            @"id":identifier,
            @"message":valid[index],
            @"parent":parent,
            @"children":children
        };
    }

    NSMutableDictionary *legacy=[root mutableCopy];
    [legacy removeObjectForKey:@"messages"];
    [legacy removeObjectForKey:@"page_info"];
    legacy[@"mapping"]=mapping;

    NSString *conversationID=[legacy[@"id"] isKindOfClass:NSString.class]?legacy[@"id"]:nil;
    if (!conversationID.length && [legacy[@"conversation_id"] isKindOfClass:NSString.class]) {
        conversationID=legacy[@"conversation_id"];
        legacy[@"id"]=conversationID;
    }

    NSString *current=[currentNodeOverride isKindOfClass:NSString.class] && currentNodeOverride.length
        ? currentNodeOverride
        : ([legacy[@"current_node"] isKindOfClass:NSString.class]?legacy[@"current_node"]:nil);
    if (!current.length || !mapping[current]) current=ids.lastObject;
    if (current.length) legacy[@"current_node"]=current;

    return [NSJSONSerialization dataWithJSONObject:legacy options:0 error:NULL];
}

NSArray *CGConversationPagingReplaceTail(NSArray *cached, NSArray *newest) {
    if (!cached.count || !newest.count) return nil;
    NSString *anchor=CGPagingMessageID(newest.firstObject);
    if (!anchor.length) return nil;
    NSUInteger index=NSNotFound;
    for (NSUInteger i=0;i<cached.count;i++) {
        if ([CGPagingMessageID(cached[i]) isEqualToString:anchor]) { index=i; break; }
    }
    if (index==NSNotFound) return nil;
    // Validate IDs before truncation. Never retain an obsolete regenerated suffix.
    NSMutableSet *seen=[NSMutableSet set];
    NSMutableArray *result=[NSMutableArray array];
    for (NSUInteger i=0;i<index;i++) {
        NSString *identifier=CGPagingMessageID(cached[i]);
        if (!identifier.length || [seen containsObject:identifier]) return nil;
        [seen addObject:identifier];
        [result addObject:cached[i]];
    }
    for (id raw in newest) {
        NSString *identifier=CGPagingMessageID(raw);
        if (!identifier.length || [seen containsObject:identifier]) return nil;
        [seen addObject:identifier];
        [result addObject:raw];
    }
    return result;
}
