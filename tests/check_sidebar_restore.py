from pathlib import Path

source=(Path(__file__).resolve().parents[1]/"src/PinnedSidebarIntegration.m").read_text()

assert "CGHistoryAppear" in source
assert "CGHistoryDisappear" in source
assert "viewDidAppear:" in source
assert "viewDidDisappear:" in source
assert "sSidebarEntryConversationID=[sSelectedDetailID copy]" in source
assert "sSidebarEntryDetailSerial=sDetailRequestSerial" in source
assert "sDetailRequestSerial++" in source
assert "sDetailRequestSerial!=serial" in source
assert "![sSelectedDetailID isEqualToString:cid]" in source
assert "CG46OpenPin((UIViewController *)self,cid,title)" in source
assert "UIApplicationStateActive" in source

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

print("PASS: final sidebar repair uses direct lifecycle reselection only")
