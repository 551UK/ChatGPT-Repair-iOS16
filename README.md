# ChatGPTRepair

Restores missing features to the older ChatGPT app on jailbroken iOS 16. This tweak is designed for version 1.2024.200.

- Removes the sunset/update-required screen.
- Restores working chat history and older conversations.
- Recognises existing pinned chats and lets you pin or unpin conversations.
- Restores image generation and generated-image viewing.
- Adds additional AI models and thinking options.
- Restores voice chat features.
- Improves copying text and compatibility with newer ChatGPT features.

- Makes plain and newer rich-style links clickable on the older app.
- Handles server rate limiting so history pages and conversation details do not disappear or open blank during HTTP 429 responses.

- Retries transient chat-opening timeouts (including HTTP 500) without a fixed attempt count; waits according to server Retry-After and cancels obsolete retries after selecting another chat.

- Restores modern web citations in the legacy app by converting citation metadata into tappable source links.

- v56.1 preserves the original labels of normal rich/download links while converting only genuine citation markers.

- v56.2 handles filecite markers cleanly, using resolved links when available or a [file] fallback without exposing raw turn IDs.

- v56.3 converts unsupported product/products rich markers into readable product names without exposing raw product reference IDs.

- v56.4 compacts adjacent same-site citation links so repeated source hosts do not spam the old renderer.

- v56.5 converts unsupported rich layout markup (`<row>`, `<AsyncImage>`, `<Link>` and product price placeholders) into readable text with tappable URL tokens for older iOS clients. This does not add native rich cards or image query support.

- v56.7 converts raw GenUI download buttons and badges into clean text/clickable links on the legacy renderer.

- v56.8 fixes the sidebar-return blank-chat bug by snapshotting the selected conversation when the sidebar appears and synchronously reselecting that same conversation when the sidebar disappears, only when no different detail request has started. Earlier timer/hit-test/delayed-controller experiments were removed.

- v56.9 moves the same-chat sidebar reload before the app's original `viewDidDisappear:` runs, because the diagnostic showed the HistoryViewController is detached and its native selection closure is unusable immediately afterwards.

- v57.0 protects the active conversation at the successful sidebar-history refresh event, reasserting the same native selection without an arbitrary timer.

- v57.1 repairs the exact loaded-to-zero message collection state after sidebar history refresh, without timer polling.
