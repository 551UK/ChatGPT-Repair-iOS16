// ChatGPTRepair: Observe newer responses in the currently opened chat.
#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
void CGChatSyncTrackDetail(NSURLRequest *request, NSURLSessionConfiguration *configuration);
void CGChatSyncMarkDelivered(NSURLRequest *request, NSDictionary *root);
// Remember the native sidebar controller even when it is no longer visible.
void CGChatSyncRememberHistoryController(UIViewController *controller);
