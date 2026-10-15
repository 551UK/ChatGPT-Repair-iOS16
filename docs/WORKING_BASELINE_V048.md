# Working baseline — v0.48.0 (the new v9)

Designated by the user on 15 October 2026 as the new working baseline.
Use this version as the starting point for future changes, replacing v0.9
as the default recovery/reference build. Keep the package version 0.48.0;
"the new v9" describes its role, not a version renumbering.

- Source commit: `e730a86ca7424335e44fd6b3675ec138a06752ce`
- Baseline tag: `baseline-v0.48.0`
- Baseline branch: `baseline/v048-working`
- Installer: `ChatGPT-Repair-iOS16_0.48.0_iphoneos-arm64.deb`
- Installer SHA-256: `aee64e100bef4223e1adfcc2a97346f9d1d3e6209c599b6541bdc811f28dd5c5`
- Original source archive: `ChatGPT-Repair-iOS16_0.48.0_source.zip`
- Source archive SHA-256: `6016b44c74cc13df7e5d5e5dfccd3a925f9f436fa219f96bb8f16147f628051a`

Preserve the working pinned section, native opening of pinned chats, normal
history behavior, LLVM linking/signing, and invalidated-session refresh handling.
Make future fixes from this baseline and limit changes to the requested issue.
Do not rebuild or overwrite this baseline installer. v0.9 and v0.47 remain
historical recovery points. No app behavior was changed when recording this.

Target setup: ChatGPT 1.2024.200 on iOS 16, rootless Dopamine, with the existing
ChatGBeFree companion enabled. Device reports can show a spoofed app version.
