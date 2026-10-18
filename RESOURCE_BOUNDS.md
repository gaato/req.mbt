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
| Buffered response body (`src/client.mbt`, `Client::new`, `max_body_bytes`, passed to `@adapter.AsyncTransport::new`) | 64 MiB by default (`default_max_body_bytes`), decoded bytes after gzip decoding; `max_body_bytes=None` lifts it. Enforced by the default transport (`http-async/src/transport.mbt`, `read_bounded`, tested there); a transport passed to `Client::new` sets its own | The transport refuses the chunk that crosses it and closes the connection; the call raises `ReqError::Protocol` | `src/client_wbtest.mbt`: "defaults: 30 s per exchange, 64 MiB per buffered body, a versioned User-Agent" |
| Exchange time (`src/client.mbt`, `Client::exchange`, `@adapter.with_timeout_opt` on the client's clock) | `timeout`, 30 s by default (`default_timeout`), per client and replaceable per call: the transport's `send`, from the request to the whole buffered response. The default transport's own deadline is set to `Int` max (`transport_ceiling_ms`) so it never cuts a longer call timeout short | The exchange is cancelled and the call raises `ReqError::Timeout` | `src/timing_test.mbt`: "an exchange times out after 30 s on the client's clock by default", "timeout is set per client and replaced per call"; `src/client_wbtest.mbt`: "defaults: 30 s per exchange, 64 MiB per buffered body, a versioned User-Agent" |

## Bounded by rate and lifetime

| Structure | Grows with | Bound |
|---|---|---|
| The default transport's parked connections (`@adapter.AsyncTransport`) | Origins a client talks to | `gaato/http-async`'s defaults: 4 per origin, closed after 10 s idle. `Client::close` drops them; a throw-away client of a top-level function closes them when the call returns |
| Steps and hooks (`src/step.mbt`, `run_steps`) | Calls in flight | One closure per step per call, released when the call returns |

## Left to the caller

| Structure | Grows with | Why it is not bounded here |
|---|---|---|
| Request bodies (`content`, `text`, `data`, `files`, `json`) | What the caller sends | The caller builds them in memory before the call |
| Time spent in steps and hooks | What a step does | `timeout` covers each exchange with the transport, not the caller's own code around it; a step that waits is the caller's policy |
| A transport passed to `Client::new` | Its own buffers | Its owner sets its limits; `max_body_bytes` applies only to the default transport |

## Known gaps

| Structure | Grows with | What limits it | Suggested fix |
|---|---|---|---|
| Response heads (moonbitlang/async `src/http/parser.mbt`) | Header size from the server | `timeout` times bandwidth | A head size limit upstream in moonbitlang/async |
