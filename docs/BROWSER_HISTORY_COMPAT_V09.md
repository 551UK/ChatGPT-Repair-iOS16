# v0.9 — browser-compatible conversation-list request experiment

## Browser evidence supplied 14 October 2026

Firefox Network screenshots show two **HTTP 200** history GETs from the user's working ChatGPT browser session:

```
GET https://chatgpt.com/backend-api/conversations?exclude_conversation_origin=tpp&expand=false&hide_snorlax=false&is_archived=false&is_starred=false&limit=20&order=updated&offset=0

GET https://chatgpt.com/backend-api/conversations?conversation_origin=tpp&expand=false&hide_snorlax=false&is_archived=false&is_starred=false&limit=20&order=updated&offset=0
```

The two requests are *different* groups, one excluding TPP-origin conversations and one selecting them. Both return HTTP 200. Browser query parameters are public URL metadata; no account credentials, response payloads, titles, chat IDs or tokens are included.

The original iOS 2024 request in logs used `offset=0&limit=20`, included `order`, and **did not include `is_archived`**. With ChatGBeFree 2.3.5 interceptor enabled, it repeatedly timed out or returned HTTP 500 (28 response bytes). The browser working against the same account substantially weakens an account-wide outage explanation.

## What this experiment changes

For the exact non-archived, unstarred **history-list GET endpoint only**, the 551UK source adapts the URL to the browser's proven normal-list shape:

```
exclude_conversation_origin=tpp
expand=false
hide_snorlax=false
is_archived=false
is_starred=false
limit=<original page size, default 20>
order=updated
offset=<original offset, default 0>
```

Uses NSURLSession data-task creation methods (both request and URL variants, with and without completion handlers). No response body replacement, new protocol registration, fake HTTP 200, request header changes, session-cookie modifications, credentials access or message-body changes.

An explicit `conversation_origin`, search query, project selector or true archived/starred view is not altered. The original ChatGBeFree protocol routing decision is preserved; bypass=0. The task KVO probe still logs whether each history request completes and its HTTP status/bytes/error.

The query adapter is **idempotent** for already-adapted requests. It does not by itself combine the separate TPP-origin list into the old app's history view. Full-history parity requires checking both groups and the old app's pagination and state handling once the normal-list request returns HTTP 200.

## How to test

1. Keep ChatGBeFree 2.3.5 installed and update only `com.551uk.chatgptrepair` to v0.9.0.
2. Force-close ChatGPT 1.2024.200, reopen, observe how many chats appear. Pull down to refresh once.
3. Leave the app open long enough for the request to finish, then share `Library/Caches/ChatGPT551Repair.log`.
4. Look for `v0.9 history_browser_query applied=1`; `v0.9 protocol_probe ... force_bypass=0`; and `v0.9 history_task=... completed=1 http_status=...`.
5. Report how many chats were visible before and after, and if scrolling loaded additional pages.

**Interpretation:** HTTP 200 means the query workaround at least obtained a successful list and we should investigate iOS decoding/pagination next. HTTP 500 means that query alone was insufficient; client-specific session headers or forwarding may be relevant. HTTP 0/-1001 or -1005 means transport was not working. No `applied=1` means the Swift app's creation path was missed by the hook and a different interception strategy is necessary.

The missing upload (+) button in all existing chats remains an independent unresolved issue. v0.9 does not modify composer UI.

**This is a compatibility experiment, not a verified complete repair.** If it worsens behaviour, uninstall only the 551UK companion; do not remove the app or your existing chat history.
