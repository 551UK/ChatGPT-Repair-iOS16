# v0.49 pin menus

Parent: v0.48 (e730a86), baseline documentation commit 18d3184.

Missing pinned menu cause: CGPinnedSidebarView implemented UITableView selection but no context-menu delegate. Added contextMenuConfigurationForRowAtIndexPath with an immutable record captured by the menu closure. Tap and selection ABI files are unchanged.

Normal menus: scope a configuration-factory wrapper to HistoryViewController collection menu callbacks. Preserve native action provider, preview provider and menu properties. Resolve exact displayed labels against loaded history titles; skip non-unique matches. This path needs device verification because SwiftUI may build menus outside those callbacks.

Request evidence from provided 2026 binary: 0x558d644 builds path components pins, item type, item ID with method tag 1 on its ordinary branch; 0x558d944 builds the same path with method tag 4. POST/DELETE mapping is inferred from request method tags. Route used: /backend-api/pins/conversation/<UUID>. No invented JSON body or request retries. HTTP errors are displayed and logged; no local pin change on failure.

Concurrency: block writes while a pins fetch is outstanding, block fetches while writes are outstanding, suppress duplicate writes for the same ID, discard completed writes after an auth/store change. Retain v48 invalidated-session handling. Apply local change only after 2xx, then reconcile using existing fetch.

Limitations: not run on an iPhone here. Native menu callback coverage, POST/DELETE server acceptance and refresh behaviour must be checked on the target device. A pin absent from the loaded normal history may require reopening the list after unpinning.

Verification: compile; signed Mach-O layout/code-page validation; ARM64 selection bridge check; unchanged HistoryIsolation, DirectPinSelection, DirectPinABI, PinService, PinnedLayoutShim against v48.
