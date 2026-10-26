// ChatGPTRepair: safe observation of the selected conversation.
#pragma once
#import <Foundation/Foundation.h>
void CGChatSyncTrackDetail(NSURLRequest *request, NSURLSessionConfiguration *configuration);
void CGChatSyncMarkDelivered(NSURLRequest *request, NSDictionary *root);
void CGChatSyncLogEvent(NSString *event);

// Once older pages are cached, update the existing native conversation one time.
void CGChatSyncHydrateBackgroundHistory(NSURLRequest *request);
