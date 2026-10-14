# ChatGPT Repair iOS16 — by 551UK

Source-based jailbreak compatibility project for the official ChatGPT **1.2024.200** app on **iOS 16 / rootless Dopamine**.

## Status: v0.1.0 — experimental companion

This is your own editable source project, not a renamed or repackaged binary. The initial release is an **add-on to ChatGBeFree 2.3.5**, so that its existing model, voice, generated-image, and version-bypass features remain installed during development.

**Neither of the two reported problems is yet confirmed fixed.** The first version includes a conservative history JSON compatibility adapter and diagnostics for differences between conversations opened on the phone and those created on PC.

- Sidebar history: intercept successful GET conversation-list responses on OpenAI / ChatGPT domains, avoid stale caching, and add the legacy items array when the server returns equivalent arrays under conversations or data.items.
- Missing attachment (+) button in desktop-created chats: observe the structural fields in GET conversation-detail responses; no fabricated UI or server entitlements. The fix will need to target the real cause, potentially the old app's model/composer gating.
- Existing ChatGBeFree 2.3.5: stays installed, and its closed-source extra features are not redistributed here.
- Independent version-spoof code: included as editable source in src/StandaloneVersion.m but not enabled in the companion build to avoid conflicts.

## How to build

Use GitHub Actions > Build ChatGPT Repair Rootless > Run workflow. After successful compilation, download the workflow artifact containing the DEB. Or build locally with Theos using: make package FINALPACKAGE=1.

Do NOT uninstall Liam's ChatGBeFree 2.3.5 yet. Install this alongside it. The new package ID is com.551uk.chatgptrepair.

## Testing

Close ChatGPT completely, reopen, then try the sidebar and open one PC-created and one phone-created conversation. In Filza, find your ChatGPT data container, then Library/Caches/ChatGPT551Repair.log. Share that log and what changed.

The log contains only statuses, sizes, JSON key-presence flags and counts, never chat text, titles, conversation IDs, authorization tokens or private headers.

If something crashes or stops working, remove only the 551UK package. Chat data is untouched.

## Limits and future work

The 2024 app might use a non-URLSession transport, or its Swift views may reject modern models. This initial adapter is deliberately narrow and not guaranteed to work. Restoring the actual attachment picker and reconstructing the model/voice/image compatibility features in source require further app-version-specific investigation. No complete standalone replacement is claimed yet.

## Credits / licence

The publicly released [ChatGBeFree](https://github.com/liamschwie/ChatGBeFree) version-spoofing code/concept by Liam is GPLv3. Credit and GPLv3 are retained. History repair/probe source is original 551UK work. No third-party binary is bundled. This project is not affiliated with OpenAI.
