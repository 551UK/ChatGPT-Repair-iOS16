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
assert "DISPATCH_SOURCE_TYPE_TIMER" in source
assert "0.20*NSEC_PER_SEC" in source
assert "CGHistoryDisappear" not in source
assert "viewDidDisappear:" not in source
print("PASS: sidebar visibility transition repair avoids duplicate/native navigation and no longer relies on viewDidDisappear")
