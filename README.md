# ChatGPT Repair iOS16 — by 551UK

**Target:** official ChatGPT `1.2024.200` on jailbroken iOS 16 (Dopamine rootless).

**Goal:** restore up-to-date conversation history, fully functional attachments in **all existing conversations**, and other compatible features using an independent, maintainable 551UK source project.

## Current development status — v0.7.0 diagnostic companion

**Neither missing history nor missing upload buttons is fixed yet.** Do not claim this release as a repair; it is a controlled test following the failed v0.1–v0.3 approaches. Keep the already-working ChatGBeFree 2.3.5 installed until its functionality can be reconstructed and tested in source.

### Downloads

- [v0.7.0 experimental release](https://github.com/551UK/ChatGPT-Repair-iOS16/releases/tag/v0.7.0)
- [Side-by-side analysis: 2024 vs 2026 IPAs](docs/2024_VS_2026_IPA.md)
- [Earlier IPA analysis](docs/IPA_ANALYSIS.md)

## What we learned from both IPA versions

| | 2024 installed app | 2026 comparison app |
| --- | --- | --- |
| Minimum OS | iOS 16.1 | **iOS 18.0** |
| Sidebar | Original history view model, fetchMoreItems() | Revised history and fetchMoreItems(reason:), fetchConversationList(offset:limit:) |
| Attachment logic | Has fileUpload blocked-feature checking | Still has fileUpload blocked-feature checking; expanded composer |
| Working on iOS 16 | Yes | Not without extensive unsupported backporting |

The newer framework **cannot be copied into iOS 16**. Any relevant compatible behaviour needs to be independently implemented against the 2024 app.

The user has **hundreds of conversations** that do not appear in the 2024 sidebar. A request for `offset=0&limit=20` is normal as an initial page; later pages or updates need to work. The uploaded log shows prior HTTP 500 and timeouts, but the 551UK v0.1–0.3 networking interceptor may itself have interfered with the existing ChatGBeFree 2.3.5 interceptor.

The missing `+` button affects **every conversation opened from the sidebar**, not only conversations first created on a PC. It works in a brand-new chat started on the phone. The earlier response logs observed conversation messages, not `POST /conversation/init` metadata. We cannot know what disables the button until those are compared.

## What v0.7.0 changes

The latest v0.5.0 on-device log showed delegate handlers installing, but no captured response completions. We checked the actual ChatGBeFree 2.3.5 binary and found a custom `LVBVoiceURLProtocol` interceptor. **v0.7.0 is a controlled history-only bypass test**, with source in [src/HistoryIsolation.m](src/HistoryIsolation.m).

Only GET requests for the conversation list are excluded from that specific third-party interceptor. v0.7.0 additionally logs task completion status, error code and byte count using passive state observation. Every model, attachment, image, voice, message-send and conversation-detail route remains unchanged. No requests are rewritten, no server responses are fabricated, and no chat data is collected.

**This can make history better, worse or unchanged**, depending on whether the existing interceptor is part of the problem. It is not a proven fix, nor does it restore the missing + attachment button. Read [v0.7 outcome test notes](docs/HISTORY_OUTCOME_V07.md).

### Test

1. Install v0.7.0 over v0.5.0, while retaining the known-working ChatGBeFree 2.3.5.
2. Force-close and reopen ChatGPT 1.2024.200; check whether more chats appear.
3. Pull down to refresh once; check again.
4. Send `Library/Caches/ChatGPT551Repair.log` from the app's data container and report whether the sidebar changed.

The log should show whether `LVBVoiceURLProtocol` wanted to intercept history GETs and — if the task state observer receives a completed event — what HTTP status or network error resulted. If it did not, this particular bypass cannot solve the issue. Removing only the 551UK tweak reverts the test.

**Attachment buttons in all existing chats remain a separate unresolved issue.** The new-chat versus existing-chat difference is established from your test reports, but the precise metadata/UI condition has not yet been verified.

## Building / release

Theos / iOS 16.5 SDK; `make package FINALPACKAGE=1`. Pushing a new version to main builds the rootless DEB with GitHub Actions and creates an asset in Releases.

## Long-term independence

Original public version-spoof concept from [ChatGBeFree by Liam](https://github.com/liamschwie/ChatGBeFree), GPLv3, with attribution in LICENSE and source. Later 2.3.5 voice, models and image functionality is not available as complete published source, and **is not currently replicated by the 551UK project**. We will not distribute the private compiled binary as though it were editable source.

This project is not affiliated with OpenAI. UI patches cannot override genuine account, model or server-side capability restrictions.
