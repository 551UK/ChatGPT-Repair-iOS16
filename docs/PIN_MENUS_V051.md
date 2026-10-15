# v0.51: normal-history regression and native menu identity

Device evidence: uploaded ChatGPT551Repair(3)(1).log.
- 13:03:07 UTC: unpin HTTP 200, pins count 7 -> 6.
- Repeated native history HTTP 429. At 13:04:42/43 and 13:05:18/19, native history failed while the extra v50 title request succeeded. This demonstrates competing requests, not proof of account history deletion. 429s also occurred before v50, so v50 is an aggravating source of traffic, not the only possible source.
- normal_menu matched=0 and interaction_menu row_found=1 matched=0 despite titles_loaded=20/21. Missing Pin is row identity matching, not absent menu callback.

Fix:
- Remove the entire extra title-history request and timer. Retain only passive parsing of actual app history responses. The owned session remains for confirmed working pin writes and pin-list reads.
- Remove broad UIContextMenuInteraction initializer/delegate hooks. The native collection callback is confirmed present (one=0, many=1) and executing.
- Use the NSString UUID passed to the native UIContextMenuConfiguration factory. Require active history-row callback scope and a valid UUID. Keep the native identifier, preview and menu action provider.

Binary evidence (provided ChatGPT 1.2024.200 framework):
- ObjC collectionView:contextMenuConfigurationForItemsAtIndexPaths:point: IMP 0x35f07c.
- History menu construction 0x35edd0 loads [HistoryItem + 0x10] at 0x35eeb0, the conversationID Swift string field established by baseline type layout/getter 0x370e90.
- The bridged value is retained at 0x35eeb8 and passed as identifier into 0x35fd30 at 0x35f038..48.
- 0x35fe1c..30 calls configurationWithIdentifier:previewProvider:actionProvider: with that identifier. Selector pointer at 0x1fe7f18 verified.

Validation: local compile, Mach-O segments/signatures and ARM64 selection bridge checks pass. CGSetPin is byte-for-byte source-identical to v50 except version log label. Baseline HistoryIsolation, DirectPinSelection, DirectPinABI, PinService and PinnedLayoutShim unchanged. Extra title-fetch block and broad interaction hooks absent. No device test yet; native Pin menu and POST write still require confirmation. Existing server rate limiting can persist after installation; repeated reopening may prolong it.
