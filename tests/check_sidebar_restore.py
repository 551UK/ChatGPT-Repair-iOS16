from pathlib import Path

source=(Path(__file__).resolve().parents[1]/"src/PinnedSidebarIntegration.m").read_text()

# Final diagnostic-driven design: use the lifecycle callback proven by the log,
# not the discarded visibility polling / delayed weak-owner experiments.
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

# Old failed approaches must stay deleted.
assert "CGSidebarVisibilityTick" not in source
assert "CGSidebarListIsTopmost" not in source
assert "CGViewDescendsFrom" not in source
assert "CGTrackHistoryController" not in source
assert "sSidebarVisibilityTimer" not in source
assert "sSidebarVisibilityKnown" not in source
assert "sSidebarActuallyVisible" not in source
assert "__weak UIViewController *weakController=controller;" not in source
assert "owner!=sHistoryController" not in source
assert "0.35*NSEC_PER_SEC" not in source
assert "0.60*NSEC_PER_SEC" not in source
assert "0.85*NSEC_PER_SEC" not in source

print("PASS: final sidebar repair is direct lifecycle reselection only; obsolete polling and delayed-owner code is absent")
