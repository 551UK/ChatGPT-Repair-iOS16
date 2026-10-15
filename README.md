## v0.53 — load the next 20 older chats (preserving v0.52)

When the legacy iOS client requests `offset=20&limit=20` (or the next older page), HTTP 429 can prevent the result from reaching the native conversation list. v0.53 keeps that *existing* native request pending, retries the same authenticated page at a controlled 15/35/70-second backoff (respecting longer server `Retry-After` up to five minutes), and delivers the real successful result to the native completion. At most three attempts; no forged chat rows, offsets or success codes. Concurrent failures for the same page join one retry. It does not bypass rate limits; if they continue, the real failure is passed through.

v0.52's six-hour successful-page cache is retained. Only older pages at offsets >=20 without a matching cache fallback enter the retry path. Retry requests are marked to avoid recursion and excluded from native pin-session tracking. Pin/Unpin actions, the pinned section, and chat navigation are unchanged. This does not address phone-only conversations not appearing in the browser.

**Recovery baseline:** retain the original v0.52 DEB/source package; do not overwrite or delete them.

## v0.52 history retention build

Keeps v51's confirmed Pin and Unpin actions. Stores successful authenticated history pages and supplies the matching saved page when a later refresh receives HTTP 429. This avoids feeding the legacy history consumer a rate-limit error when a usable page exists. Adds no network requests. The cache survives app restarts, is scoped to authentication and exact page query, and expires after six hours.

Requires one successful history load after installation. Existing server rate limiting still needs to clear; pages never fetched cannot be restored. Build/binary checks pass; on-device recovery requires testing.

## v0.51 recovery and native Pin menu build

Removes v50's extra history/title requests, which added traffic while native history was receiving HTTP 429. Uses the conversation UUID already provided by the app's native context-menu factory to add Pin chat. Removes broad interaction hooks and title matching. Confirmed working Unpin logic is preserved, together with v48 native opening and layout.

Build and binary checks pass; device testing remains required. An existing server rate limit may need time to clear. v48 remains the preserved full working baseline; v50 is confirmed for Unpin only.

## v0.50 pin-menu test build

Fixes the v0.49 expired-session failure by owning a dedicated NSURLSession copied from the observed app configuration. Authentication comes from the same observed history request; no credentials are logged. Pins refresh also uses this session so an app-invalidated history session cannot disable menu actions.

Normal menus: hook UIContextMenuInteraction delegates attached to native history rows, in addition to collection callbacks. Capture history titles with a separate read because native history may use delegate transport. Retain original menu preview/actions; append Pin only for a unique resolved row. Device verification remains required.

The v0.48 working baseline remains preserved. Selection bridge, native chat opening and layout files are unchanged.

## v0.49 pin-menu test build

Built from the preserved v0.48 working baseline. Pinned table rows now supply a UIKit long-press menu with Unpin chat. Native history context menus retain their original preview/actions and gain Pin chat when a unique loaded conversation can be resolved. Duplicate or unresolved titles are left unchanged. Server acknowledgement is required before changing the pinned list.

Compilation, Mach-O layout/signatures and the native selection ABI checks pass. On-device menu presentation and authenticated server writes still require testing. v0.48 remains the working baseline; v0.49 is not promoted to baseline.

# Current working baseline: v0.48.0 — the new v9

**User-designated working baseline, 15 October 2026.** All future fixes start
from v0.48.0. Preserve its working pinned section, chat opening and normal history.
The package remains version 0.48.0.

See [the dedicated baseline section](docs/WORKING_BASELINE_V048.md) for the exact
source commit, preserved installer and checksums. The original v0.48 installer
and source archive are saved together in `ChatGPT-Repair-iOS16_v048-working-baseline.zip`.

The sections below are historical build notes, including their validation status
at the time they were written.

---

# v0.48 targeted refresh crash fix

v0.47 is the user-confirmed working pinned-chat baseline, preserved at commit
0061eb6 and local branch `baseline/v047-user-confirmed-working`.

The new crash report identifies `NSGenericException: Task created in a session
that has been invalidated`, raised inside `CGFetchPins` during sidebar appearance.
v0.48 catches only that task-creation exception in the pin service and reports a
failed refresh through the existing completion path. The last accepted pin list
is preserved, the refresh-in-progress flag is cleared, and the expired session
reference is discarded only if it is still the current captured session. A later
authenticated history request supplies the next session. There is no immediate
retry on the invalid session and no replacement networking session.

Pin layout, native chat opening, pin parsing and v0.9 history code are unchanged.
The LLVM linker and signing method remain those of working v0.47. Compilation,
final signed layout/code-page checks and five ARM64 adapter tests pass. The exact
CFNetwork exception path cannot be executed in the Linux build environment;
on-device confirmation is still required.

Install v0.48 over v0.47, keep ChatGBeFree enabled, and close/reopen ChatGPT.
The v0.47 installer is retained for rollback.

---

# v0.47 launch-crash rebuild

The v0.46 device report crashes at the first instruction of `CGRStart` during
dyld initialization (`+0x4174`, protection failure), before pinned-chat code.
The exact on-device cause is not proven by the report.

v0.47 replaces Zig 0.13's Mach-O linker with LLVM `ld64.lld` 18. It produces
16KB-aligned code/data segments, then signs the final dylib with ldid. The
v0.9 history source and v0.46 direct-selection implementation are retained.
New static checks cover segment layout, both constructor targets, header/code
separation, and every CodeDirectory page hash; the five ARM64 adapter tests
also run on the final signed binary. These are not an iOS launch test.

Install over v0.46 and fully close/reopen ChatGPT. Keep the existing ChatGBeFree
setup. If launch still fails, disable only ChatGPTRepair and retain the new crash
report. Pinned-chat loading/opening remains unverified on-device.

Local build: `python3 scripts/build_local.py SDK_PATH LDID_PATH LD64_LLD_PATH`
(requires ziglang==0.13.0, lief, unicorn, and the linker's host shared libraries).

---

# v0.46 — independent native pinned selection

Built afresh from v0.9. Normal history networking is unchanged. Pinned rows use
separate state and pass a newly constructed native conversation to the app's
existing selection callback, bypassing the missing-history-cache lookup.

**Experimental: not yet verified on the phone.** Build and ABI checks cannot
establish that message rendering succeeds. See [the evidence and new approach](docs/DIRECT_PIN_SELECTION_V046.md).

Keep ChatGBeFree 2.3.5 installed; install the companion update, force-close
ChatGPT and reopen. Test two pinned chats and an ordinary chat.

---

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

