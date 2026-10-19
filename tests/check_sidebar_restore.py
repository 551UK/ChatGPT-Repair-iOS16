from pathlib import Path

source=(Path(__file__).resolve().parents[1]/"src/PinnedSidebarIntegration.m").read_text()

assert "CGHistoryAppear" in source
assert "CGHistoryDisappear" in source
assert "viewDidAppear:" in source
assert "viewDidDisappear:" in source
assert "sSidebarEntryConversationID=[sSelectedDetailID copy]" in source
assert "sSidebarEntryDetailSerial=sDetailRequestSerial" in source
assert "sDetailRequestSerial++" in source
assert "sDetailRequestSerial==serial" in source
assert "[sSelectedDetailID isEqualToString:cid]" in source
assert "CG46OpenPin((UIViewController *)self,cid,title)" in source
assert "UIApplicationStateActive" in source

# The reload must happen before the app's original viewDidDisappear. The
# diagnostic showed the HistoryViewModel/selection closure is gone afterwards.
fn=source[source.index("static void CGHistoryDisappear"):source.index("static void CGInstallNativeHook")]
assert fn.index("CG46OpenPin((UIViewController *)self,cid,title)") < fn.index("sOriginalDisappear")
assert "if (CG46OpenPin((UIViewController *)self,cid,title))" in fn

for old in (
    "CGSidebarVisibilityTick",
    "CGSidebarListIsTopmost",
    "CGViewDescendsFrom",
    "CGTrackHistoryController",
    "sSidebarVisibilityTimer",
    "sSidebarVisibilityKnown",
    "sSidebarActuallyVisible",
    "sSidebarEpoch",
    "sSidebarWasShown",
    "__weak UIViewController *weakController=controller;",
    "UIViewController *owner=controller;",
    "0.35*NSEC_PER_SEC",
    "0.60*NSEC_PER_SEC",
    "0.85*NSEC_PER_SEC",
):
    assert old not in source, old

print("PASS: sidebar reload runs before original viewDidDisappear while HistoryViewModel is alive")

assert "sVisibleHistoryController" in source

assert "CGRepairCollapsedChatIfNeeded" in source
assert "CGFindMessageCollection" in source
assert 'containsString:@"BottomAlignedCollectionViewController"' in source
assert "sSidebarObservedLoadedMessages" in source
assert "sSidebarHistoryRefreshArmed" in source
repair=source[source.index("static void CGRepairCollapsedChatIfNeeded"):source.index("static void CGHistoryLayout")]
assert "dispatch_after" not in repair
assert "dispatch_async" not in repair
assert "messages.contentSize.height" in repair
assert "sDetailRequestSerial==serial" in repair
assert "CG46OpenPin(owner,cid,title)" in repair
