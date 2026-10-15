# v0.50 follow-up

Observed v49 failure: screenshot says "Reopen the chat list to refresh your session". This message is generated before a write when the session/request is missing, or by the invalidated-session catch. It is not an HTTP error.

Changes:
- Keep a dedicated session copied from the captured history session configuration. Replace it on authentication change, finishing old requests. App-owned sessions are not retained or revived.
- Use owned transport for pin reads/writes. Original history transport is unchanged.
- Read title/ID mapping separately, covering delegate-based native history responses. Ignore own session in history capture to prevent recursion.
- Observe actual UIContextMenuInteraction delegate configuration method. Scope menu addition to a HistoryViewController collection row, excluding pinned table interactions. Keep native preview/action provider, skip ambiguous title matches, suppress duplicate Pin actions.
- Preserve Objective-C init-family ownership on the swizzled interaction initializer.
- Add logs for session creation, title fetch status/count, interaction hook class, row resolution and write HTTP/error code. No request tokens or chat text are logged.

Checks: compilation, signed Mach-O layout and page hashes, ARM64 bridge validation, byte comparison of baseline history/selection/layout source. Not run on a physical iPhone; endpoint acceptance and native menu presentation need the user's test. Endpoint/method choices from v49 are unchanged because the screenshot did not reach an HTTP failure.
