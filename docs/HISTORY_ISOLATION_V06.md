## v0.6.0 — isolated history-route test

The latest v0.5.0 log has `delegate hooks data=1 finished=1` but no completed history or init responses during the logging window. This does not prove failure: callbacks might be delivered through another transport or later.

We inspected the exact user-provided ChatGBeFree 2.3.5 binary and confirmed it defines `LVBVoiceURLProtocol`, its own NSURLProtocol network interceptor. The next **experimental** test isolates whether that interceptor is obstructing sidebar fetching:

- Find `LVBVoiceURLProtocol` at runtime and override *only its* `+canInitWithRequest:` for **GET /backend-api/conversations** (plus its known path variants) on OpenAI/ChatGPT hosts.
- For those history GETs alone, return `NO`, allowing the normal session to handle the request. All other requests use the original interceptor unchanged. The URL, auth headers, parameters, cookies and account are not modified.
- Record `original_would_intercept` and `force_bypass` in the app cache log. If no `original_would_intercept=1` appears, this particular ChatGBeFree protocol likely was not responsible for capturing the history request.
- The diagnostic intentionally does **not** implement attachment-button repairs yet; it does not touch conversation-detail, init, model, image or voice routes.

**This build changes handling of history requests and may fail to load them if the external tweak's custom forwarding is actually required.** Remove `com.551uk.chatgptrepair` to undo the test. Keep ChatGBeFree 2.3.5 installed. Do not uninstall or reinstall the ChatGPT app, which could risk local data.

Test: force-close/reopen ChatGPT, check the visible chat count, pull down once to refresh, then send `ChatGPT551Repair.log` and say if more than the original few chats appeared. A working fix is not established until tested on-device.
