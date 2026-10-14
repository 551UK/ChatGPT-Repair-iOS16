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


## v0.8.0 completed request evidence — 14 October 2026

The next user-supplied full log shows three attempts with the **original ChatGBeFree network interceptor enabled** (`force_bypass=0`):

| Outer/forwarded tasks | Start (UTC) | Finish (UTC) | HTTP | NSURL error | Bytes |
|---|---|---|---|---|---|
| 1 and 2 | 17:25:01 | 17:26:20 | 0 | -1001 timeout | 0 |
| 3 and 4 | 17:26:21 | 17:26:51 | 500 | 0 | 28 |
| 5 and 6 | 17:26:51 | 17:27:22 | 500 | 0 | 28 |

The pairs likely represent original and internally forwarded NSURLSession tasks; do not interpret them as six separate user refreshes. The three attempts each requested `offset=0&limit=20`. **No HTTP 200 list response was observed.** The preceding v0.7 history-only bypass had instead produced error **-1005**, no response and 0 bytes. Thus neither routing approach has established a working first-page fetch.

### External corroboration (not proof of the same root cause)

An OpenAI Developer Community report dated **8 July 2026** describes a ChatGPT *web* request `GET https://chatgpt.com/backend-api/conversations?offset=0&limit=28&order=updated&is_archived=false&is_starred=false` returning **HTTP 500 with Content-Length 28** — the same status/response size as the current iPhone test. Source: https://community.openai.com/t/unable-to-load-history-recent-chats-are-not-loading/1385975/7

A separate August 2026 ChatGPT Web/Desktop community report describes a large account history where `/backend-api/conversations` returned HTTP 429 while other chat requests succeeded: https://community.openai.com/t/chatgpt-web-conversation-history-returns-persistent-429-rate-limit-and-fails-to-load/1391615

These are user reports, **not official confirmation** that the specific iPhone error is server-side. The older app or ChatGBeFree may generate a different request than the current desktop client, and its interceptor could affect forwarding. Note that the 2026 web report includes `is_starred=false` as well as `is_archived=false`; it still returned HTTP 500. Therefore blindly appending either query parameter is not a justified fix.

### Evidence needed before another history patch

Compare the response status and **sanitized query parameter names/values** of the normal working desktop client's first history GET to the 2024 app's GET, without capturing Authorization, cookies, account identifiers, conversation IDs or response bodies. If PC returns 200 but the iPhone returns 500 for the same account, determine route, sort, and header *presence* differences first. If the PC also returns 500, diagnose an account/service issue rather than inventing a successful list.

Treat the existing-chat attachment (+) button as independent: the source-only 551UK project has not yet established the conversation-init metadata that controls it. No active rewrite should be introduced for this feature until its real gate is identified.

**Decision:** keep v0.8.0 as a diagnostic control. Do not publish another speculative DEB based solely on a 28-byte HTTP 500.
