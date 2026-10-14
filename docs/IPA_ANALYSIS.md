# Static analysis of decrypted ChatGPT iOS 1.2024.200

This analysis uses the decrypted IPA supplied by the repository owner. No OpenAI app binaries, private chat contents, session credentials or third-party compiled dylibs are committed.

## Verified bundle details

- CFBundleIdentifier: com.openai.chat
- CFBundleShortVersionString: 1.2024.200
- CFBundleVersion: 10062920475
- MinimumOSVersion: 16.1
- Most of the app's Swift code is in Frameworks/ChatGPT.framework/ChatGPT (~44.6 MB uncompressed).

## History system

The 2024 Swift binary includes ChatGPTHistory.HistoryViewModel, with reflected fields:
- conversations, _conversationsByID, historyItemsByID
- historyUpdateTask and fetchMoreItemsTask
- _sections, _fetchState and _emptyHistory

An API.ConversationListRequest model contains offset, limit, order, expand and isArchived, while API.ConversationListResponse contains items and total. A separate native method is named conversationList(using:logToConsole:).

**Inference (not yet proven):** missing recent sidebar items could result from the old pagination request, server response decoding, or failure to update the app's stored history state. Merely refreshing an HTTP cache or reassigning a JSON key is insufficient if Swift's model decode drops records or its in-memory history remains stale.

## Attachments / input UI

ChatGPTMessageInput.MessageInputViewModel includes:
- _fileUploadBlockedFeature, which holds conversation-specific metadata
- _shouldShowAttachmentsDisabledPopover and _attachmentsDisabledPopover
- _isConversationInputDisabled, _productFeatures, _uploads and _uploadIDs
- supportedAttachmentTypes, showAttachmentType(_:) and showAttachmentsDisabledPopover()

The app contains a feature-flag string: chatgpt-ios-disable-message-attachments.

The API metadata includes the fields blockedFeatures, modelLimits, defaultModelSlug, conversationId. A blocked-feature enumeration exposes send, fileUpload and gizmoTag. In the UI the _fileUploadBlockedFeature is associated with ConversationDetailMetadata.

**Inference (not yet proven):** PC-created conversations might return different conversation metadata or newer model values, leading the legacy composer to hide or disable its attachment buttons. Showing a cosmetic + icon would not restore a working upload pipeline.

## Why v0.1.0 did not establish a fix

The prior URLProtocol experiment normalized only a few response envelopes and did not alter any composer UI logic. URLProtocol registration does not guarantee coverage of every URLSession instance, delegate or transport used by the Swift app. There was no on-device evidence for the specific response shape assumed.

## Diagnostic v0.2.0

Added a read-only probe of relevant NSURLSessionTask resume calls, recording route **categories** and numeric sidebar pagination parameters but no URLs, IDs, tokens, chat contents, message bodies or headers. The original narrow history adapter remains. It may not see every request if a private task subclass overrides resume.

After opening the sidebar and one PC-created and one iPhone-created chat, retrieve the log from the ChatGPT app data container: Library/Caches/ChatGPT551Repair.log.

For history, check whether any probe route=history-list is logged, which offset/limit are requested, and whether history status/items lines appear. For attachment UI, compare whether conversation-init and conversation-detail categories are requested. This log by itself cannot determine the values of private blocked features or definitively identify the cause.

This is an investigative build, not a verified repair or standalone replacement. Further changes should be driven by observed on-device behaviour and harmless structural evidence.