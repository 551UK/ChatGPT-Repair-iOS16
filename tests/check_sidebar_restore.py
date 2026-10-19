from pathlib import Path

source=(Path(__file__).resolve().parents[1]/"src/PinnedSidebarIntegration.m").read_text()

assert "CGHistoryAppear" in source
assert "CGHistoryDisappear" in source
assert "viewDidAppear:" in source
assert "viewDidDisappear:" in source
assert "sVisibleHistoryController=(UIViewController *)self" in source
assert "sVisibleHistoryController=nil" in source
assert "CGShouldQuarantineActiveHistory" in source
assert "CGHistoryFirstPage" in source
assert "NSURLErrorCancelled" in source

# Old repair-after-damage attempts are deliberately removed.
for old in (
    "CGRepairCollapsedChatIfNeeded",
    "CGFindMessageCollection",
    "CGCurrentMessageCollection",
    "sSidebarHistoryRefreshArmed",
    "sSidebarObservedLoadedMessages",
    "sSidebarCollapseRepairIssued",
    "sSidebarEntryConversationID",
    "sSidebarEntryDetailSerial",
    "sSidebarLastRestoreAt",
    "CGSidebarVisibilityTick",
    "sSidebarVisibilityTimer",
):
    assert old not in source, old

# Keep the request/result quarantine ahead of the normal history callback.
history=source[source.index("CGOriginMergePage(historyConfig"):source.index("// Resolve modern web citation markers")]
assert "CGRememberHistory(combined)" in history
assert "originalForward(nil,nil,historyCancelled);" in history
assert history.index("originalForward(nil,nil,historyCancelled);") < history.index("originalForward(combined,combinedResponse,combinedError);")

print("PASS: active-chat sidebar first-page refresh is quarantined before it can clear the legacy Messages model")
