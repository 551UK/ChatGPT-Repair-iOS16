"""Offline regression checks for history refresh and HTTP 429 handling."""
from pathlib import Path

root=Path(__file__).resolve().parents[1]
adapter=(root/"src/HistoryIsolation.m").read_text()
cache=(root/"src/HistoryPageCache.m").read_text()
pins=(root/"src/PinnedSidebarIntegration.m").read_text()
merge=(root/"src/HistoryOriginMerge.m").read_text()

assert "NSURLRequestReloadIgnoringLocalCacheData" in adapter
assert 'setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"' in adapter
assert 'setValue:@"no-cache" forHTTPHeaderField:@"Pragma"' in adapter
assert 'if (firstPage)' in adapter
assert 'exclude_conversation_origin' in adapter
assert 'CGRAdaptHistoryRequest' in adapter

# On HTTP 429, a valid cached first page must be considered before starting
# another rapid retry burst. If no cache exists, the existing bounded retry
# path remains available.
assert "NSData *fallback=nil;" in cache
assert cache.index("NSData *fallback=nil;") < cache.rindex("CGEnqueueOlderRetry(key,request,configuration,data,response,error,completion)")
assert "BOOL firstPage=CGOlderOffset(request)==0;" in cache
assert '(!firstPage || !retryRequest || finalRetry)' in cache
assert 'olderBackoff[]={15,35,70}' in cache
assert 'static void CGFinishWithFirstPageFallback' in cache
assert 'if(!key || !completion || error || (offset!=0 && offset<20)' in cache
assert 'CGFinishWithFirstPageFallback(job);' in cache
assert "rate-limit-fallback" in cache

# TPP history merging must tolerate 429s rather than immediately dropping the
# extra-origin page and making conversations disappear.
assert "CGOriginFetchWithRetry" in merge
assert "CGOriginRetryDelay" in merge
assert 'Retry-After' in merge
assert 'baseWasRateLimitFallback' in merge
assert 'initialDelay=baseWasRateLimitFallback?8.0:0.0' in merge
assert 'NSURLErrorCancelled' in merge

# Conversation detail requests that return 429 must be held and retried instead
# of forwarding the failed response to the old app as a blank conversation.
assert 'X-551UK-Detail-Retry' in pins
assert 'CGRetryConversationDetail' in pins
assert 'CGDetailRetryDelay' in pins
assert 'CGDetailRetryable(response,error)' in pins
assert 'status==500' in pins and 'status==502' in pins and 'status==503' in pins
assert 'NSURLErrorTimedOut' in pins
assert 'CGDetailStillSelected' in pins
assert 'CGScheduleDetailRetry' in pins
assert 'MIN(attempt+1,6)' in pins
assert 'attempt>=2' not in pins
assert 'attempt+1<2' not in pins
detail=pins.split('static NSString * const kDetailRetryHeader=',1)[1].split('static void CGRefreshPins(void)',1)[0]
assert 'timeoutIntervalForRequest=30' not in detail
assert 'timeoutIntervalForResource=120' not in detail
assert 'Retry-After' in pins
assert 'originalDetailForward' in pins

# Existing pin/unpin hooks, native navigation and older-page retries remain.
assert 'CGSetPin(' in pins and 'CG46OpenPin(' in pins
assert 'CGHistoryPageResult(' in pins
assert "job.attempts<3" in cache
assert 'X-551UK-History-Retry' in pins

print("PASS: cached 429 fallback, TPP merge retry, detail retry, and existing pin/history behaviour")
