# v0.46: independent native selection from the v0.9 baseline

This is a new implementation path, pending on-device verification. It does not
claim that successful compilation demonstrates working chat loading.

## Evidence rechecked from both supplied IPAs

* 1.2024.200: iOS 16.1 minimum, framework UUID
  F1CF3B21-AAAF-3E57-BB62-CE6149AA9040.
* 1.2026.272: iOS 18.0 minimum, includes ChatGPTPinning.PinnedItemRepository,
  PinnedItemsWithHistory and PinnedItemResponse. These are not drop-in iOS 16 modules.
* 2024 ConversationListResponseItem uses Foundation.Date for create/update time;
  ConversationResponse uses Swift.Double. Copying a detail object into a list is
  not a type-equivalent conversion. Previous documentation incorrectly implied it was.
* Native history selection at 0x36e340 requires BOTH historyItemsByID and
  conversationsByID. It silently exits when either lookup fails. This explains why
  calling that helper with a missing pinned ID cannot be a navigation solution.
* The successful branch constructs HistorySelection.historyItem with a tuple of
  HistoryItem and Conversations.Conversation, calls the stored didSelect closure
  at model offset 760, then destroys the temporary selection.
* The receiving flow at 0x1c86ac uses the supplied Conversation, obtains its
  coordinator through 0xd8adc0, and selects that coordinator. It is not another
  lookup in HistoryViewModel.historyItemsByID.

## New path

1. Keep src/HistoryIsolation.m byte-identical to v0.9 (97c257a).
2. Fetch pin IDs/titles independently; present a separate Pinned group above
   ordinary history. Do not wait for message bodies to display pins.
3. On a tap, initialize a fresh native Conversation with its native constructor.
   Set its real remoteId and title using native setters; retain a fresh empty
   native tree. No other conversation's mapping, current node or state is copied.
4. Construct a matching HistoryItem, with native Date and title state, no search
   result, and conversationHasDetails=false.
5. Construct HistorySelection.historyItem and call the existing didSelect closure
   directly. This bypasses only the two cache lookups that blocked prior attempts.
   Native coordinator/network code remains responsible for loading the chat.
6. Destroy temporary Swift values through their native value witnesses.

No history response rewriting, timestamp rewriting, offset shifting, fabricated
HTTP success, server unpinning, search automation, web-view replacement, or
modification of normal row selection is part of this build.

## Guardrails and validation

The bridge rejects other framework UUIDs, unexpected callback ownership,
metadata sizes/field offsets, missing runtime symbols, or a changed closure offset.
The C/Swift adapters preserve x20 and the link register. Synthetic ARM64 emulation
checks the register/return-value contract of each adapter; this is ABI testing,
not execution of UIKit or the app's conversation-loading code.

The pin service/presentation components are reused from the separate-view design;
the former network bootstrap and 0x36e340 invocation are not compiled.

The latest provided log ends at v0.44, so v0.45's failure is a user observation,
not something established by that log. v0.44 fetched valid detail JSON but held
history callbacks pending all pin requests, then timed out. v0.46 never holds an
ordinary history callback for pin fetching.

## On-device evidence still required

After upgrading, force-close ChatGPT and reopen. A pin tap should log
`direct_pin46 dispatch=historyItem`, `callback_returned=1`, and native detail/init
requests. HTTP 200 alone does not prove the message view rendered. Verify one
older pinned conversation, a second pinned conversation, and a normal chat.

Logs contain counts/status/size/layout information, not tokens, IDs, titles,
request URLs, or message content. Keep ChatGBeFree 2.3.5 installed as with v0.9.

## Completed local validation

Compiled all nine translation units for arm64 iOS 16.0 against the 16.5 SDK.
Linked Foundation/UIKit/CoreGraphics/Objective-C system libraries and signed the
dylib with ldid. Verified all code-signature page hashes. All five emulated ABI
checks pass on the final signed dylib, including register preservation and stack
alignment. Confirmed HistoryIsolation.m is byte-identical to commit 97c257a.
The package contains only the rootless dylib and its ChatGPT-only filter plist.

Local linking reserves 4096 header bytes before signing; the final signed-code
test catches signer/header overlap. No proprietary IPA or framework is shipped.
GitHub publishing was blocked by automatic approval review, so this source
archive and DEB are delivered directly. On-device behavior remains unverified.
