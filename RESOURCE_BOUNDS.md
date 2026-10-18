# Resource bounds

What a client and its calls can accumulate, and what keeps each structure
from growing without limit. The rule: **every structure that grows with input
from the network or with the number of calls is listed here with its bound**.
A new one needs a row before it ships.

**Every row of "Enforced limits" names a test that checks the bound**, in its
Tests column: a backticked file path, then the quoted names of that file's
tests. A test counts only if it drives the structure to its limit and one past
it, or pins a default the row states. `scripts/bounds_check.sh`, run by
`scripts/gates.sh`, enforces the naming; whether a named test really reaches
the bound is checked in review. The other tables are prose.

Limits enforced by the lower layers (`gaato/http`, `gaato/http-async`,
`gaato/sdk-runtime`) are listed in their own ledger,
https://github.com/gaato/mbt-sdk/blob/main/RESOURCE_BOUNDS.md; rows here say
which defaults this module sets on them.

## Enforced limits

| Structure | Bound | On overflow | Tests |
|---|---|---|---|
| Buffered response body (`src/client.mbt`, `Client::new`, `max_body_bytes`, passed to `@adapter.AsyncTransport::new`) | 64 MiB by default (`default_max_body_bytes`), decoded bytes after decoding; `max_body_bytes=None` lifts it. Enforced by the default transport (`http-async/src/transport.mbt`, `read_bounded`, tested there); a transport passed to `Client::new` sets its own | The transport refuses the chunk that crosses it and closes the connection; the call raises `RequestoError::Protocol` | `src/client_wbtest.mbt`: "defaults: 30 s per exchange, 64 MiB per buffered body, a versioned User-Agent" |
| A streamed body read into memory (`src/response.mbt`, `Response::read`) | The client's `max_body_bytes`, whatever the transport | The chunk that crosses it is not kept; the body is closed and `read` raises `RequestoError::Protocol` | `src/stream_test.mbt`: "read buffers at most max_body_bytes and closes a larger body" |
| Each read of a streamed body (`src/response.mbt`, `Response::next_chunk`) | The call's `timeout` per read, on the client's clock | The read is cancelled, the body closed, and the call raises `RequestoError::Timeout(phase=Body)` | `src/stream_test.mbt`: "each read of a streamed body is bounded by the call's timeout" |
| One server-sent event (`src/sse.mbt`, `Response::each_event`, `max_event_bytes`, passed to `@sse.SseParser::new`) | 16 MiB by default, gaato/http/sse's default (tested there): the raw bytes of the event's `data`, `event` and `id` lines and of the line being read; replaceable per call, here and on `sse` | The event is not kept; the body is closed and `each_event` raises `RequestoError::Protocol` after the events before it, reading nothing more | `src/sse_test.mbt`: "each_event holds max_event_bytes of an event and refuses one more" |
| One line (`src/lines.mbt`, `Response::each_line`, `max_line_bytes`, `LineSplitter`) | 16 MiB by default (`default_max_line_bytes`), the line's bytes without its terminator; replaceable per call | The line is not kept; the body is closed and `each_line` raises `RequestoError::Protocol` after the lines before it, reading nothing more | `src/lines_wbtest.mbt`: "LineSplitter holds max_bytes of a line and refuses one more"; `src/sse_test.mbt`: "each_line holds max_line_bytes of a line and refuses one more" |
| Exchange time (`src/client.mbt`, `Client::exchange`, `@adapter.with_timeout_opt` on the client's clock) | `timeout`, 30 s by default (`default_timeout`), per client and replaceable per call: the transport's `send`, from the request to the whole buffered response. The default transport's own deadline is set to `Int` max (`transport_ceiling_ms`) so it never cuts a longer call timeout short | The exchange is cancelled and the call raises `RequestoError::Timeout` | `src/timing_test.mbt`: "an exchange times out after 30 s on the client's clock by default", "timeout is set per client and replaced per call"; `src/client_wbtest.mbt`: "defaults: 30 s per exchange, 64 MiB per buffered body, a versioned User-Agent" |
| Retries of one hop (`src/retry.mbt`, `retry_step`, `Retry::new(max_retries~)`; `src/client.mbt`, `Client::chain`, inside the redirect step) | 3 by default, per client (`Client::new(retry~)`) and per call (`retry?`); `Retry::none()` sends once. Each send has its own `timeout`, so a hop takes at most `max_retries + 1` exchanges plus the waits, and a call at most `(max_redirects + 1) * (max_retries + 1)` | The last response is returned, or the last failure raised | `src/retry_wbtest.mbt`: "Retry defaults: 3 retries, transient statuses, idempotent methods, 60 s cap", "delay_ms: the count, the body, Retry-After and its cap, else the backoff"; `src/retry_test.mbt`: "after max_retries the last response or failure is kept" |
| Wait before a retry (`src/retry.mbt`, `Retry::delay_ms`, `full_jitter`, on the client's clock) | A `Retry-After` of at most `max_retry_after` (60 s by default); without one, a draw below `base_delay * 2 ^ retry` capped at `max_delay` (1 s and 30 s by default) | A longer `Retry-After` is not waited for: the response is returned as it is | `src/retry_wbtest.mbt`: "delay_ms: the count, the body, Retry-After and its cap, else the backoff", "full_jitter draws below base * 2 ^ retries, capped"; `src/retry_test.mbt`: "a Retry-After beyond max_retry_after keeps the response" |
| Digest nonces a client keeps (`src/digest.mbt`, `DigestState`) | 16 origins (`max_digest_origins`), one nonce each; its `nc` up to `0xFFFFFFFF` (`max_nonce_count`), the most eight hex digits hold | Adopting a 17th origin forgets the oldest; a nonce whose count runs out is forgotten, and the next call is challenged again | `src/digest_wbtest.mbt`: "nonce state: counted per origin, bounded, forgotten when nc runs out" |
| Digest answers on one hop (`src/digest.mbt`, `digest_step`, `should_answer`) | One answer to a challenge, and one more when that answer's nonce was stale: at most 3 sends per hop and retry | The last 401 is returned | `src/digest_wbtest.mbt`: "should_answer: once, and once more for a stale nonce"; `src/digest_test.mbt`: "a refused answer returns the 401, and a stale one is answered once more" |
| Redirects followed per call (`src/redirect.mbt`, `redirect_step`; `Response.history`) | `max_redirects`, 10 by default (`default_max_redirects`), per client; `history` holds at most that many responses, each closed before the next hop, so a streamed call keeps no connection open for them | The redirect past it is closed unread and the call raises `RequestoError::TooManyRedirects` | `src/redirect_test.mbt`: "more than max_redirects raises TooManyRedirects; 10 by default", "a streamed call closes each redirect response before the next hop"; `src/redirect_wbtest.mbt`: "defaults: 10 redirects in a row, a jar of 50 cookies per domain and 3000 in all" |
| A client's own cookie jar (`src/cookies.mbt`, `cookie_jar`, passed to `@cookie.CookieJar::new`) | 50 cookies per domain (`default_max_cookies_per_domain`) and 3000 in all (`default_max_cookies`), the RFC 6265 §6.1 minimums. Enforced by gaato/http's jar (`http/src/cookie/jar.mbt`, tested there); a jar passed as `cookies=Jar(jar)` keeps the limits it was made with | Expired cookies are evicted first, then the least recently accessed | `src/cookies_test.mbt`: "the client's jar keeps 50 cookies per domain and 3000 in all"; `src/redirect_wbtest.mbt`: "defaults: 10 redirects in a row, a jar of 50 cookies per domain and 3000 in all" |

## Bounded by rate and lifetime

| Structure | Grows with | Bound |
|---|---|---|
| The default transport's parked connections (`@adapter.AsyncTransport`) | Origins a client talks to | `gaato/http-async`'s defaults: 4 per origin, closed after 10 s idle. `Client::close` drops them; a throw-away client of a top-level function closes them when the call returns |
| Events or lines parsed together (`src/response.mbt`, `Response::each_slice`) | Size of one read; a body in memory is one read of any size | Each read is parsed in slices of at most 64 KiB (`slice_bytes`), and a slice's events or lines are handed to `f` before the next is parsed |
| Steps and hooks (`src/step.mbt`, `run_steps`; `src/client.mbt`, `Client::chain`) | Calls in flight | One closure per step per call, the redirect and cookie steps included, released when the call returns |

## Left to the caller

| Structure | Grows with | Why it is not bounded here |
|---|---|---|
| Request bodies (`content`, `text`, `data`, `files`, `json`) | What the caller sends | The caller builds them in memory before the call; `body_stream` and stream parts are sent as they are read |
| A streamed body taken with `read_some` or `each_chunk` | What the caller keeps | Each chunk is handed over and not kept by the response |
| Time spent in steps and hooks | What a step does | `timeout` covers each exchange with the transport, not the caller's own code around it; a step that waits is the caller's policy |
| Reconnecting to an event stream (`Client::sse`) | What the caller does after a stream ends | `sse` never reconnects; a caller that does chooses how often. The `retry` delay an event carries is capped at one hour by gaato/http/sse |
| A transport passed to `Client::new` | Its own buffers | Its owner sets its limits; `max_body_bytes` applies only to the default transport |

## Known gaps

| Structure | Grows with | What limits it | Suggested fix |
|---|---|---|---|
| Response heads (moonbitlang/async `src/http/parser.mbt`) | Header size from the server | `timeout` times bandwidth | A head size limit upstream in moonbitlang/async |
