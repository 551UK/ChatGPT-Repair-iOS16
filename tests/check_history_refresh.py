"""Offline regression checks for fresh normal chat-list refresh."""
from pathlib import Path

root=Path(__file__).resolve().parents[1]
adapter=(root/"src/HistoryIsolation.m").read_text()
cache=(root/"src/HistoryPageCache.m").read_text()
pins=(root/"src/PinnedSidebarIntegration.m").read_text()

assert "NSURLRequestReloadIgnoringLocalCacheData" in adapter
assert 'setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"' in adapter
assert 'setValue:@"no-cache" forHTTPHeaderField:@"Pragma"' in adapter
assert 'if (firstPage)' in adapter
assert 'exclude_conversation_origin' in adapter
assert 'CGRAdaptHistoryRequest' in adapter

# A failed first-page refresh must attempt fresh authenticated network pages
# before showing the old cached 200 response.
assert cache.index("CGEnqueueOlderRetry(key,request,configuration,data,response,error,completion)") < cache.index("NSData *fallback=nil;")
assert "BOOL firstPage=CGOlderOffset(request)==0;" in cache
assert '(!firstPage || !retryRequest || finalRetry)' in cache
assert 'freshBackoff[]={2,5,12}' in cache
assert 'olderBackoff[]={15,35,70}' in cache
assert 'static void CGFinishWithFirstPageFallback' in cache
assert 'if(!key || !completion || error || (offset!=0 && offset<20)' in cache
assert 'CGFinishWithFirstPageFallback(job);' in cache

# Existing pin/unpin hooks, native navigation and older-page retries remain.
assert 'CGSetPin(' in pins and 'CG46OpenPin(' in pins
assert 'CGHistoryPageResult(' in pins
assert "job.attempts<3" in cache
assert 'X-551UK-History-Retry' in pins

print("PASS: first-page no-cache refresh, bounded 429 retries, eventual fallback, and existing pin behaviour")
