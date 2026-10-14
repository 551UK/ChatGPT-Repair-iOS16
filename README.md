# ChatGPT Repair iOS16 — by 551UK

**Target:** official ChatGPT `1.2024.200` on jailbroken iOS 16 (Dopamine rootless).

**Goal:** restore up-to-date conversation history, fully functional attachments in **all existing conversations**, and other compatible features using an independent, maintainable 551UK source project.

## Current development status — v0.5.0 diagnostic companion

**Neither missing history nor missing upload buttons is fixed yet.** Do not claim this release as a repair; it is a controlled test following the failed v0.1–v0.3 approaches. Keep the already-working ChatGBeFree 2.3.5 installed until its functionality can be reconstructed and tested in source.

### Downloads

- [v0.5.0 experimental release](https://github.com/551UK/ChatGPT-Repair-iOS16/releases/tag/v0.5.0)
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

## What v0.5.0 changes

The source code no longer registers a custom `NSURLProtocol`, modifies session configurations, replays network calls, alters request query parameters, changes the JSON body, or fabricates successful responses. It logs URLSession task route categories/pagination and passively observes both completion-handler responses and already-implemented URLSession delegate callbacks. No network requests or response payloads are changed.

See `src/HistoryRepair.m`. The only writable file is a bounded diagnostic log inside the app's own Caches directory. No chat contents, titles, conversation identifiers, access tokens or full request URLs are logged. Delegate callbacks are observed only if their delegate class already implements those methods; this remains incomplete coverage of other Swift transports. A missing completion line is **not proof** the server failed.

### Testing (please follow this exact order)

1. Upgrade only the 551UK tweak to v0.5.0. Keep ChatGBeFree 2.3.5 installed.
2. Force-close ChatGPT and reopen.
3. Start **one new conversation within the app** and confirm whether the `+` button works.
4. Next open **one existing sidebar conversation** and confirm whether its `+` button is missing.
5. Pull down to refresh sidebar; try scrolling older chats and note whether new items appear.
6. Use Filza in the ChatGPT data container to find `Library/Caches/ChatGPT551Repair.log`. Share the log (do not share cookies, tokens or private messages).

If the log has `delegate hooks data=1 finished=1` and `complete route=init` entries, compare the `blocked=` and model-field presence between the new and existing conversation. Report which chat you opened first. The diagnostic may log some delegate hook entries for sessions that are not used by these routes. If `complete route=history` is absent, we still need a different observation point; it does not mean the request timed out. The code buffers at most 4 MB of relevant response data *in memory only* to inspect structural fields.

If the app becomes unstable, remove only `com.551uk.chatgptrepair`; it is a separate companion and does not delete chats.

## Building / release

Theos / iOS 16.5 SDK; `make package FINALPACKAGE=1`. Pushing a new version to main builds the rootless DEB with GitHub Actions and creates an asset in Releases.

## Long-term independence

Original public version-spoof concept from [ChatGBeFree by Liam](https://github.com/liamschwie/ChatGBeFree), GPLv3, with attribution in LICENSE and source. Later 2.3.5 voice, models and image functionality is not available as complete published source, and **is not currently replicated by the 551UK project**. We will not distribute the private compiled binary as though it were editable source.

This project is not affiliated with OpenAI. UI patches cannot override genuine account, model or server-side capability restrictions.
