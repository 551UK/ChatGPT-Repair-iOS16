# ChatGPT Repair iOS16 — 551UK

**Target:** Decrypted official ChatGPT app **1.2024.200**, minimum OS 16.1, on jailbroken **iOS 16 / Dopamine rootless**.

The aim is a completely source-maintained 551UK compatibility tweak. **Current released v0.3.0 is an experimental companion, not a verified fix** for sidebar history or the missing upload (+) button. It does not include or redistribute another developer's compiled tweak.

## Download

- **Latest experimental DEB:** [v0.3.0 Releases](https://github.com/551UK/ChatGPT-Repair-iOS16/releases/tag/v0.3.0)
- **Verified IPA static-analysis findings:** [docs/IPA_ANALYSIS.md](docs/IPA_ANALYSIS.md)
- Builds are reproducible from this repository using GitHub Actions.

## Findings from the actual IPA

- The legacy history code uses a paginated request with `offset`, `limit`, `order`, `expand`, `isArchived`, and decodes a response containing `items` and `total`. Its `HistoryViewModel` maintains a separate in-memory list and loads additional pages.
- The message composer has `_fileUploadBlockedFeature`, `_shouldShowAttachmentsDisabledPopover`, and a flag named `chatgpt-ios-disable-message-attachments`.
- Conversation metadata contains `blockedFeatures` and an explicit `fileUpload` blocking case.

These are **static observations, not proof** of why a particular PC-created chat has no attachment button or a missing chat did not load. Simply forcing a + symbol without a functioning upload action would not constitute a repair.

## What v0.3.0 does

- Keeps the v0.1 narrow response adapter for successful conversation-list GET requests.
- **New:** If a history GET returns HTTP 500 and lacks an archived filter, retries once with `is_archived=false`. Only a successful, decodable list replaces the failed response; otherwise the original error is passed through.
- Adds a read-only `NSURLSessionTask resume` route probe (when invoked via the hooked implementation) to learn whether the 2024 Swift app requests history, what pagination it sends, and when conversation-detail / init requests occur.
- Reports statuses and array counts for applicable URLProtocol requests and limited structure information for conversation-detail requests.
- Logs no conversation IDs, titles, prompts, message contents, authorization headers, cookies or uploads.

**Keep the currently working ChatGBeFree 2.3.5 installed**; this companion has a separate package ID and does not include those voice, model, version-bypass and image features. If the app misbehaves, uninstall just the 551UK package.

## Exactly how to test

1. Install v0.3.0 in Sileo over v0.2.0, keeping ChatGBeFree 2.3.5 installed.
2. Force-close and reopen ChatGPT, open the left sidebar, scroll older chats, and try reopening the sidebar.
3. Open a conversation that originated on PC and lacks the + button. Then open a conversation started on iPhone that has the button.
4. Use Filza to open the **ChatGPT app data container** and find `Library/Caches/ChatGPT551Repair.log`.
5. Send the log and state whether the sidebar had fewer/newer/older missing chats and whether the two attachment buttons differed. **Do not send cookies or account tokens.**

If the log only says v0.3.0 loaded, the 2024 app may not be using a hooked task method. Compare `history original_500`, `history retry variant=is_archived_false status=... list_valid=...` and the final `history status=...`. If no matching response appears, interception or client transport may be incomplete. Neither history nor upload UI is verified repaired.

## Building

In [Actions](../../actions), run the **Build ChatGPT Repair Rootless** workflow, or use Theos on macOS: `make package FINALPACKAGE=1`.

Versioned builds are published to [Releases](../../releases) on successful `main` pushes when the `control` package version is new.

## Licence and credit

GPLv3. The original public version-spoofing code and concept come from [ChatGBeFree by Liam](https://github.com/liamschwie/ChatGBeFree), and are credited as required. The source-written diagnostics and compatibility experimentation are maintained by 551UK. The independently editable optional version source remains disabled in the companion to avoid conflicting with 2.3.5.

Not affiliated with OpenAI.
