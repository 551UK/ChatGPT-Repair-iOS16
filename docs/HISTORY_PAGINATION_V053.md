# v0.53 older-history continuation

Scope: `GET /backend-api/conversations`, authenticated pages `offset>=20`, only on HTTP 429 when no exact v0.52 cached page exists. The native scrolling controller has already asked for the next 20; its completion is kept alive while a strictly bounded retry happens.

Retries: up to three (15, 35, 70 seconds minimum; honor Retry-After up to 300 seconds). Requests for the same page key share a single retry chain, no more than four distinct page keys queued; extra requests get their original error. A shared gate avoids a burst across multiple offsets. The retry uses an independently owned NSURLSession to avoid a session-invalidated crash from native short-lived sessions. Requests carry a marker header to prevent swizzle recursion and to avoid replacing pin-menu auth/session state. Normal conversations, pins, init, chat detail, and POST are unmodified.

Logs: `history52 older_page_retry_scheduled`, `older_page_retry_response`, `older_page_finished`. A final 429 means the server rate limit remained active; the client cannot bypass it. The existing successful-page cache still falls back when an exact page was previously fetched.

This fix is separate from the issue of phone-created conversations not synchronizing to the browser; it does not claim to solve that.
