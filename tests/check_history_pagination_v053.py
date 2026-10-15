#!/usr/bin/env python3
"""Static regression checks; real iOS server behaviour must be device-tested."""
from pathlib import Path
base=Path(__file__).resolve().parent.parent
history=(base/'src/HistoryPageCache.m').read_text()
sidebar=(base/'src/PinnedSidebarIntegration.m').read_text()
assert 'CGOlderOffset(request)<20' in history # no v53 retries for first page
assert 'older_page_duplicate_429_joined_existing_retry' in history
assert 'sOlderPageRetries.count>=4' in history
assert 'job.attempts<3' in history
assert 'CGResponseHeader((NSHTTPURLResponse *)response,kCacheHeader)' in history
assert 'valueForHTTPHeaderField:kCacheHeader' not in history # NSURLResponse lacks this selector
assert 'v0.53 loaded=1' in sidebar
assert sidebar.count('X-551UK-History-Retry')==2 # bypass both pin session & double interception
assert 'native_route=' in sidebar and 'CGSetPin' in sidebar # pin/unpin unchanged
assert 'CG46OpenPin' in sidebar
print('PASS: bounded older-page retry, v52 page cache and pin/navigation paths retained')
