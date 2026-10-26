// ChatGPTRepair: Observe newer responses in the currently opened chat.
#pragma once
#import <Foundation/Foundation.h>
void CGChatSyncTrackDetail(NSURLRequest *request, NSURLSessionConfiguration *configuration);
void CGChatSyncMarkDelivered(NSURLRequest *request, NSDictionary *root);
