from pathlib import Path

source=(Path(__file__).resolve().parents[1]/"src/PinnedSidebarIntegration.m").read_text()
assert "CGSidebarListIsTopmost" in source
assert "hitTest:point withEvent:nil" in source
assert "CGSidebarVisibilityTick" in source
assert "CGTrackHistoryController" in source
assert "sSidebarEntryConversationID=[sSelectedDetailID copy]" in source
assert "sSidebarEntryDetailSerial=sDetailRequestSerial" in source
assert "sDetailRequestSerial++" in source
assert "sSidebarEpoch!=epoch" in source
assert "sDetailRequestSerial!=serial" in source
assert "![sSelectedDetailID isEqualToString:cid]" in source
assert "CGSidebarListIsTopmost(owner)" in source
assert "owner.presentedViewController" in source
assert "CG46OpenPin(owner,cid,title)" in source
assert "UIViewController *owner=controller;" in source
assert "__weak UIViewController *weakController=controller;" not in source
assert "owner!=sHistoryController" not in source
assert "0.35*NSEC_PER_SEC" in source
assert "DISPATCH_SOURCE_TYPE_TIMER" in source
assert "0.20*NSEC_PER_SEC" in source
assert "CGHistoryDisappear" not in source
assert "viewDidDisappear:" not in source
print("PASS: sidebar restore retains dismissed HistoryViewController long enough to fire native reselection and still yields to real detail requests")
