# v0.7.0 — history task outcome instrumentation

The user supplied a v0.6.0 log confirming:

```
v0.6 original protocol located; conversation-list GET bypass installed
v0.6 protocol_probe history original_would_intercept=1 force_bypass=1 offset=0 limit=20
```

This proves ChatGBeFree 2.3.5's `LVBVoiceURLProtocol` wanted to intercept the history GET and the experiment made it return `NO`. **It does not prove this caused the missing history or that the bypass produced a successful response**.

v0.7.0 retains the narrowly scoped GET bypass and adds a passive KVO observation of the `NSURLSessionTask.state` property for history requests. If a task reaches `NSURLSessionTaskStateCompleted`, it records:

- an ephemeral local sequence number, not a conversation ID
- HTTP status (if available)
- network error code (if any)
- total received byte count

No request header, URL, token, prompt, chat ID, response body or personal message content is saved. No request or response is rewritten; all other ChatGBeFree routes continue to use the original interceptor.

**Log interpretation:**
- `original_would_intercept=1`: old interceptor would have taken the history GET.
- `force_bypass=1`: our current experiment asks it to decline just that GET.
- `history_task=N started ... kvo=1`: task observer successfully attached.
- `history_task=N completed=1 http_status=200`: underlying HTTP request returned successfully; app parsing/state is the next suspect if chats are missing.
- `http_status=500`: backend or upstream route responded with server error despite bypass.
- `error_code=-1001`: request timed out.
- No completed entry: task did not reach a KVO-observed completed state in the recorded window, or the observer is not working on this specific task implementation. It does **not** establish an error or successful history.
- `kvo=0`: the observer could not attach, so completion status cannot be concluded from this log.

Test while keeping ChatGBeFree 2.3.5: force close/reopen ChatGPT, open sidebar, pull once to refresh, check whether the number of chats changes, allow the request to finish naturally, then export the app's `Library/Caches/ChatGPT551Repair.log`.

**Known issues:** This is still an experimental diagnostic. NSURLSessionTask KVO behaviour may vary across private task subclasses. If the app becomes unstable, uninstall the 551UK companion (package `com.551uk.chatgptrepair`) without removing ChatGBeFree or the ChatGPT app. No upload-button changes are made in this version.
