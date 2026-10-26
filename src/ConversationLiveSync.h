// ChatGPTRepair: safe observation of the selected conversation.
#pragma once
#import <Foundation/Foundation.h>
void CGChatSyncTrackDetail(NSURLRequest *request, NSURLSessionConfiguration *configuration);
void CGChatSyncMarkDelivered(NSURLRequest *request, NSDictionary *root);
