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

## v0.2.0 on-device observation (14 October 2026)

A user-supplied, private-safe diagnostic log showed:
- Conversation-list GET invoked at `offset=0, limit=20`, with an `order` parameter and no `is_archived` parameter.
- No successful list-response was observed. At 16:29:15 UTC, the forwarded history request returned `HTTP 500` (28 response bytes). An earlier run observed a URLSession timeout (`NSURLErrorDomain -1001`).
- Conversation-detail GETs returned `HTTP 200`, including messages from newer-model conversations.
- This does **not** establish that the server is permanently broken: status may originate in an upstream proxy or be influenced by interception. It also does not determine the cause of the missing upload UI.

## v0.3.0 experiment

When and only when an intercepted history GET returns HTTP 500 **and lacks `is_archived`**, retry that same authenticated GET once with `is_archived=false`. Keep offset, limit, order and headers unchanged. Apply the result only if it returns HTTP 200 and a JSON conversation-list array. Otherwise pass through the original error. Cap retry timeout at 12 seconds.

Log interpretation:
- `history original_500; retrying_once variant=is_archived_false`: alternate request attempted.
- `history retry ... status=200 ... list_valid=1`: alternate server response looks compatible; if the sidebar still does not update, client decoding/state may be at fault.
- `history retry ... list_valid=0` or non-200: no evidence that the parameter fixed the request.
- Absence of all `history status=` lines: protocol interception or the client transport needs further investigation.

**This is explicitly experimental and is not claimed to fix either the sidebar or attachment button until verified on-device.**
