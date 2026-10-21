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
for filename in ("VoiceBridge/LegacyVoiceBridge.m","VoiceBridge/LegacyRealtimeVoice.m","CopyBridge/LegacyCopyBridge.m","ImageBridge/LegacyImageBridge.m","ModelSwitcher/LegacyModelSwitcher.m","Runtime/ChatGPTRuntimeResolver.m"):
    assert (root/"upstream/chatgbefree"/filename).exists()
    assert "upstream/chatgbefree/"+filename in (root/"Makefile").read_text()
for file in (root/"src").glob("*.m"):
    assert "CGRCompatibilityEnsureLoaded" not in file.read_text(), file
assert "ChatGPTRepairDownloadFixTest.log" in (root/"src/DownloadFix.m").read_text()
assert "removeItemAtPath" in (root/"src/DownloadFix.m").read_text()
assert "CGRLog(" not in (root/"src/DownloadFix.m").read_text()
assert "didMoveToWindow" not in (root/"src/LinkFix.m").read_text()
assert "richPattern" in (root/"src/LinkFix.m").read_text()
assert "NSRegularExpression" in (root/"src/LinkFix.m").read_text()
assert "NSDataDetector" in (root/"src/LinkFix.m").read_text()
# Remove duplicate upstream packaging; retain all Objective-C source and tests.
for unused in ('Makefile','control','ChatGBeFree.plist','README.md','LICENSE','.gitignore','.gitattributes'):
    assert not (root/'upstream/chatgbefree'/unused).exists(), unused
for path in root.rglob('*'):
    if path.is_file():
        assert path.suffix.lower() not in ('.deb','.dylib','.a','.o'), path

print("PASS: clean source-only tree and existing repair regression guards")
