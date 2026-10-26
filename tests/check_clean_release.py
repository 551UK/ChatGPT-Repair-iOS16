# ChatGPTRepair: Verify clean source-only packaging and functional hooks.
from pathlib import Path
root=Path(__file__).resolve().parents[1]
main=["CitationCompat.m","HistoryIsolation.m","HistoryPageCache.m","PinnedSidebarIntegration.m","DirectPinSelection.m","DownloadFix.m","LinkFix.m"]
for file in main:
    content=(root/"src"/file).read_text()
    assert "ChatGPT551Repair.log" not in content, file
    assert "ChatGPTRepair-Compatibility-v055.log" not in content, file
    for marker in ("CGRLog(", "CGPLog(", "CGCacheLog(", "CG46Log(", "CGRHistoryTaskObserver", "CGRInstallHistoryInterceptorProbe"):
        assert marker not in content, (file,marker)
assert "CGRCitationCompatRewriteJSONData" in (root/"src/CitationCompat.m").read_text()
assert "content_references" in (root/"src/CitationCompat.m").read_text()
assert "\\uE200url\\uE202" in (root/"src/CitationCompat.m").read_text()
assert "CGHistoryPageResult" in (root/"src/HistoryPageCache.m").read_text()
assert "(offset!=0 && offset<20)" in (root/"src/HistoryPageCache.m").read_text()
assert "CGSetPin(" in (root/"src/PinnedSidebarIntegration.m").read_text()
assert "CG46OpenPin(" in (root/"src/DirectPinSelection.m").read_text()
assert "CGRAdaptHistoryRequest" in (root/"src/HistoryIsolation.m").read_text()
assert not (root/"src/CompatibilityBoot.m").exists()
assert not (root/"vendor/compatibility-2.3.5.deb.b64").exists()
assert not (root/"scripts/package_combined.py").exists()
assert "ChatGPTRepair_LIBRARIES = substrate" in (root/"Makefile").read_text()
for filename in ("VoiceBridge.m","RealtimeVoice.m","CopyBridge.m","ImageBridge.m","ModelSwitcher.m","ModelSelectionPersistence.m","RuntimeResolver.m"):
    assert (root/"src"/filename).exists(), filename
    assert "src/"+filename in (root/"Makefile").read_text(), filename
for file in (root/"src").glob("*.m"):
    assert "CGRCompatibilityEnsureLoaded" not in file.read_text(), file
assert "ChatGPTRepairDownloadFixTest.log" in (root/"src/DownloadFix.m").read_text()
assert "removeItemAtPath" in (root/"src/DownloadFix.m").read_text()
assert "CGRLog(" not in (root/"src/DownloadFix.m").read_text()
assert "didMoveToWindow" not in (root/"src/LinkFix.m").read_text()
assert "richPattern" in (root/"src/LinkFix.m").read_text()
assert "NSRegularExpression" in (root/"src/LinkFix.m").read_text()
assert "NSDataDetector" in (root/"src/LinkFix.m").read_text()
# One flat source and test layout, with no separate compatibility component.
assert not (root/"upstream").exists()
assert not (root/"THIRD_PARTY_NOTICES.md").exists()
for folder in ("VoiceBridge","CopyBridge","ModelSwitcher","ImageBridge","Runtime"):
    assert not (root/"src"/folder).exists(), folder
for file in ("CopyBridgeTests.m","ImageBridgeTests.m","ModelSwitcherTests.m"):
    assert (root/"tests"/file).exists(), file
assert not (root/"tests/ChatGBeFree").exists()
for path in root.rglob('*'):
    if path.is_file():
        assert path.suffix.lower() not in ('.deb','.dylib','.a','.o'), path

# Large-chat diagnostic build must page in small batches and never use full-chat
# fallback after successfully receiving the modern conversation's newest page.
paging_state=(root/"src/ConversationPagingState.m").read_text()
paging_network=(root/"src/ConversationPagingNetwork.m").read_text()
assert "kConversationPageSize=20;" in paging_state
assert "ChatGPTRepairLargeChat.log" in paging_network
assert "FIRST_PAGE_RETRY_SCHEDULED" in paging_network
assert "PARTIAL_HISTORY" in paging_network
older=paging_network.split("static void CGPagingRetryOlder(",1)[1].split(
    "NSURLRequest *CGConversationPagingPrepareDetailRequest(",1)[0]
assert "CGPagingFinishFallback(" not in older
# Retain Large Chat Test 1 as-is; do not reintroduce Test 2's display cap.
assert "kDiagnosticMaxRenderMessages" not in paging_network
assert "CGConversationPagingHasVersionMarkers" not in (root/"src/ConversationPagingCore.m").read_text()
sync=(root/"src/ConversationLiveSync.m").read_text()
assert "CGChatSyncTrackDetail" in sync
assert "CGChatSyncMarkDelivered" in sync
assert "CGSyncRequestUIRefresh" in sync
assert "UIApplicationDidBecomeActiveNotification" in sync
assert "src/ConversationLiveSync.m" in (root/"Makefile").read_text()
# Cross-device changes must remain detectable after the first eight polls.
assert "sSyncPolls>=8" not in sync
assert "sSyncPolls>=60" not in sync
assert "shouldRetry=YES" in sync
assert "NSJSONWritingSortedKeys" in sync
assert "messages ?: @[]" in sync
assert "CGSyncIndicator" in sync and "UIActivityIndicatorView" in sync
assert "CGSyncReopenCurrentConversation" in sync
assert "NATIVE_RESELECT" in sync
assert "kDiagnosticMaxRenderMessages" not in paging_network
# The missing UI refresh was due to losing the sidebar controller when chat opens.
pins=(root/"src/PinnedSidebarIntegration.m").read_text()
assert "CGChatSyncRememberHistoryController((UIViewController *)self)" in pins
assert "CGChatSyncRememberHistoryController" in sync
assert "RESELECT_NATIVE_DISPATCHED" in sync
assert "RESELECT_NO_HISTORY_CONTROLLER" in sync
assert "sSyncRecentHistoryController" in sync
assert "canInvoke=vc.isViewLoaded" in sync
# Sync4 preserves the history controller after the sidebar disappears and
# retries remote changes until a new conversation detail response is delivered.
assert "static UIViewController *sSyncRecentHistoryController;" in sync
assert "static __weak UIViewController *sSyncRecentHistoryController;" not in sync
assert "STALE_RENDER_RETRY" in sync
assert "RESELECT_RETAINED_ATTEMPT" in sync
assert "RELOAD_DETAIL_REQUEST_RECEIVED" in sync
assert "CONVERSATION_DELIVERED" in sync
assert "sSyncSignature=hash" not in sync
assert "sSyncSignature=signature" in sync
# Overlay is centred below the header, without altering sync request handling.
assert "CGFloat centredX=(CGRectGetWidth(window.bounds)-pillWidth)*0.5;" in sync
assert "CGRectMake(centredX,safe+56,pillWidth,30)" in sync
assert "window.bounds.size.width-140" not in sync
# Remote reply preview must not navigate during changing server text.
assert "CGSyncLatestAssistantText" in sync
assert "CGSyncPreviewUpdate" in sync
assert "SERVER_ASSISTANT_TEXT" in sync
assert "NO_SERVER_ASSISTANT_TEXT" in sync
assert "now-sSyncLastTextChange>=35" in sync
assert "now-sSyncLastUIRefresh>=95" in sync
assert "src/ConversationLivePreview.m" in (root/"Makefile").read_text()
preview=(root/"src/ConversationLivePreview.m").read_text()
assert "Live reply preview" in preview
assert "CGSyncPreviewUpdate" in preview and "gText.text=display" in preview
assert "CGSyncPreviewHide" in preview
# Surface actual ObjC selectors before choosing a private Swift refresh method.
assert "CGSyncTraceRefreshMethods" in sync
assert "NATIVE_METHOD_SCAN_COMPLETE" in sync
assert "method_getNumberOfArguments" in sync
print("PASS: clean source-only tree and existing repair regression guards")
