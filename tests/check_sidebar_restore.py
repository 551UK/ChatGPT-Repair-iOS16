from pathlib import Path

source=(Path(__file__).resolve().parents[1]/"src/PinnedSidebarIntegration.m").read_text()
assert "CGHistoryDisappear" in source
assert "sSidebarEntryConversationID=[sSelectedDetailID copy]" in source
assert "sSidebarEntryDetailSerial=sDetailRequestSerial" in source
assert "sDetailRequestSerial++" in source
assert "sSidebarEpoch!=epoch" in source
assert "sDetailRequestSerial!=serial" in source
assert "![sSelectedDetailID isEqualToString:cid]" in source
assert "owner.presentedViewController" in source
assert "CG46OpenPin(owner,cid,title)" in source
assert "viewDidDisappear:" in source
assert "0.85*NSEC_PER_SEC" in source
print("PASS: sidebar re-entry guard retains selected ID, avoids duplicate requests and keeps native selection")
