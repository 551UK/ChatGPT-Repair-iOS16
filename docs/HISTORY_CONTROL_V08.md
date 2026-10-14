# v0.8.0 — original-interceptor control test

## Evidence from the user's v0.7.0 log

At 17:19:24 UTC on 14 October 2026, a history GET was started with offset=0, limit=20. The log confirmed `LVBVoiceURLProtocol` would have claimed it, but v0.7 forced it to decline.

At 17:19:33 UTC, the same history task completed with:
- HTTP status 0 (no HTTP response)
- NSURLErrorDomain code **-1005** (network connection lost)
- **0 received bytes**

This is decisive that the **v0.7 bypass did not fix loading**. It does not by itself prove why the connection failed, and it does not show that the third-party interceptor is the original cause of missing history.

## v0.8.0: compare with original interceptor preserved

The installed ChatGBeFree 2.3.5 `LVBVoiceURLProtocol +canInitWithRequest:` result is observed, then returned **unchanged**. No forced bypass, no invented server response, no request modification, no URLSession protocol registration, no fake pagination and no sensitive response-body logging.

The independent 551UK source continues passive `NSURLSessionTask.state` observation for history GETs. It records only a local task sequence, offset/limit, completion HTTP status, error code and byte count.

### Test and interpretation

1. Install v0.8.0 over the v0.7.0 companion, retaining ChatGBeFree 2.3.5.
2. Force-close ChatGPT 1.2024.200, reopen, let the sidebar load, then pull to refresh once.
3. Send `Library/Caches/ChatGPT551Repair.log` from the ChatGPT data container.
4. Also report whether the number of visible chats changed compared with v0.7.

Look for `v0.8 protocol_probe ... force_bypass=0` and `v0.8 history_task=... completed=1 http_status=... error_code=...`.

**Potential outcomes:**
- Original returns **HTTP 500**: server / forwarding incompatibility is still possible; response format cannot be diagnosed from a 500.
- Original returns **HTTP 200**: next investigate legacy JSON decoding and whether its history model advances from offset=0 to offset=20.
- Original returns **-1005** again: bypass wasn't sufficient to explain connection failure; another transport layer or broader network issue is possible.
- No task completion: the logger cannot conclude whether the request finished. Check app stability and test-window duration.

This is another control measurement, **not a confirmed repair**. It doesn't change the missing attachment (+) icon in existing conversations. It doesn't expose any personal chat content, account tokens or complete URLs.

Keep the original ChatGPT installation and all chat data in place. To revert this experiment, uninstall only the 551UK companion package.
