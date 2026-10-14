# ChatGPT Repair iOS16 — by 551UK

**Target:** official ChatGPT `1.2024.200` on jailbroken iOS 16 (Dopamine rootless).

**Goal:** restore up-to-date conversation history, fully functional attachments in **all existing conversations**, and other compatible features using an independent, maintainable 551UK source project.

## Current development status — v0.9.0 diagnostic companion

**Neither missing history nor missing upload buttons is fixed yet.** Do not claim this release as a repair; it is a controlled test following the failed v0.1–v0.3 approaches. Keep the already-working ChatGBeFree 2.3.5 installed until its functionality can be reconstructed and tested in source.

### Downloads

- [v0.9.0 experimental release](https://github.com/551UK/ChatGPT-Repair-iOS16/releases/tag/v0.9.0)
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

## v0.9.0: original interceptor control

The last v0.7.0 test established that bypassing the existing ChatGBeFree 2.3.5 interceptor for a history GET led to **NSURLError -1005** (network connection lost) after 9 seconds with 0 bytes and no HTTP response. The bypass is **disabled** in v0.9.0.

The source still observes the original interceptor's `canInitWithRequest:` decision and the same task's final status using passive KVO, but returns the original routing decision unmodified. This lets us compare original routing with bypassed routing. It does not implement any attachment UI changes or restore the missing chats.

Read the [v0.8 control test](docs/HISTORY_CONTROL_V08.md) before installing. Install v0.9.0 over v0.7.0, keep ChatGBeFree 2.3.5 installed, force close and reopen the app, refresh once, then send the updated `Library/Caches/ChatGPT551Repair.log`.

**Look for:** `force_bypass=0`, then `history_task=... completed=1 http_status=... error_code=...`. A 200 suggests the older response decoder/UI could be dropping conversations; HTTP 500 or -1005 suggests the request/network path must be investigated before pagination.

## Building / release

Theos / iOS 16.5 SDK; `make package FINALPACKAGE=1`. Pushing a new version to main builds the rootless DEB with GitHub Actions and creates an asset in Releases.

## Long-term independence

Original public version-spoof concept from [ChatGBeFree by Liam](https://github.com/liamschwie/ChatGBeFree), GPLv3, with attribution in LICENSE and source. Later 2.3.5 voice, models and image functionality is not available as complete published source, and **is not currently replicated by the 551UK project**. We will not distribute the private compiled binary as though it were editable source.

This project is not affiliated with OpenAI. UI patches cannot override genuine account, model or server-side capability restrictions.

## v0.9.0: adapt the failed history GET to the proven browser query

The user's desktop Firefox showed **HTTP 200** for these two history-list query groups:

- `exclude_conversation_origin=tpp`: normal conversations
- `conversation_origin=tpp`: a separate group

Both included `expand=false&hide_snorlax=false&is_archived=false&is_starred=false&limit=20&order=updated&offset=0`.

The iOS 2024 client was repeatedly returning HTTP 500 or timing out before it could retrieve even the first 20 chats. We now have a reproducible **working URL shape** from the same account, not just speculative API compatibility guesses.

**v0.9.0 actively changes one thing:** for normal, non-archived history-list GET requests, it changes the request URL parameters to the working browser shape while preserving the old app's offset/limit and all authentication/session headers. It does not bypass ChatGBeFree's existing protocol, fake successful responses, interfere with chat messages or enable cosmetic upload UI.

It logs `history_browser_query applied=1` when the adapter runs and `history_task=... completed=1 http_status=...` to measure the result. The adapter's request-creation hooks might miss some Swift transports, so no `applied=1` is also useful evidence.

**Important:** This first experiment covers only the browser's `exclude_conversation_origin=tpp` list. The browser fetches `conversation_origin=tpp` separately, so restoring *all* conversations will also require handling that second group and proving pagination works. Existing-chat attachment buttons remain a separate unresolved issue.

### Test v0.9.0

1. Keep ChatGBeFree 2.3.5 installed and install v0.9.0 over the older 551UK package.
2. Force-close and reopen ChatGPT 1.2024.200, open sidebar, then refresh it once.
3. Check whether any additional chats appear or later pages load when scrolling.
4. After requests finish, share `Library/Caches/ChatGPT551Repair.log`.

See [browser request details and technical limitations](docs/BROWSER_HISTORY_COMPAT_V09.md). If the app misbehaves, remove only the 551UK companion.

