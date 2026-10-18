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
