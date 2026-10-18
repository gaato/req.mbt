# Design notes: a human-facing HTTP client for MoonBit

Status: draft (2026-10-18). Nothing is implemented yet. Module: `gaato/req`.

## Approach

The well-known HTTP clients — Python requests and httpx (httpx2), JS axios
and ky, Elixir Req — share one skeleton and differ in names and defaults.
This client implements that skeleton the MoonBit way, and does not copy any
one of them:

- **Vocabulary:** where the references agree on a name (`params`, `headers`,
  `json`, `timeout`, `auth`), use it. Where they disagree, choose by MoonBit
  convention and record the choice below.
- **Defaults:** where they disagree, choose by this client's principle:
  safe by default, bounded by default, deterministic to test.
- **Idiom:** labelled optional arguments instead of option objects or
  builders; methods on `Client` and `Response`; one suberror for failures;
  closures for scoped resources; traits and functions for extension points.

The README carries a table for users coming from each reference.

## The common skeleton

1. **Verb shortcuts and a general call:** `get`, `post`, … and
   `request(method, url, …)`, both on a client and as top-level functions.
2. **A client holding defaults** (base URL, headers, query parameters, auth,
   timeout, policies) that each call can override.
3. **Body encoders by kind:** JSON, form, multipart, raw bytes or text, each
   setting `Content-Type`.
4. **The response as a value:** status, headers, body, with readers (bytes,
   text, JSON) and a way to turn a non-success status into an error.
5. **A chain around the transport:** interceptors (axios), steps (Req),
   hooks (httpx, ky), adapters — the same structure under different names.
6. **Policies as links of that chain:** timeout, redirects, retries,
   decompression, cookies, auth.
7. **Streaming with a scope** that guarantees the response is closed.
8. **Tests by swapping the transport.**

## Layers

| Layer | Module | Role |
|---|---|---|
| Vocabulary | `gaato/http` | `Request`, `Response`, `Headers`, the `Transport` and `BodyStream` traits, bounded SSE, a scripted mock |
| Transport | `gaato/http-async` | `AsyncTransport` over moonbitlang/async: keep-alive pool, timeouts, `max_body_bytes`, `with_timeout_opt`, `VirtualClock` |
| Policy | `gaato/sdk-runtime` | retry policy (Retry-After aware, capped), rate-limit windows, multipart, error taxonomy |
| Entry point | `gaato/req` | the skeleton above, default policies, cookies, auth |

The client's logic is written against the `Transport` and `Clock` traits; the
module depends on `gaato/http-async` so `Client::new()` needs no setup.
Capabilities the SDKs need too (redirects, URL joining, proxies, finer
timeouts) go into the lower layers.

## Where the references disagree

Values are each library's defaults (requests 2.x, httpx2 2.13, axios 1.x,
ky 1.x, Req 0.7.5).

| Decision | requests | httpx2 | axios | ky | Req | **Here** | Why |
|---|---|---|---|---|---|---|---|
| Non-2xx status | value | value | throws | throws | value | **value**, plus `raise_for_status()` returning the response | a status is data; MoonBit's `raise` makes the explicit form read naturally |
| JSON body | `.json()` | `.json()` | auto-parsed | `.json()` | auto-decoded | **explicit** `json()` and typed `json_as[T]()` | a typed language decodes into a type at the call site |
| Redirects | followed (30) | not followed | followed (21, Node) | followed (fetch) | followed (10) | **followed, 10**; `Authorization` and cookies not carried across origins; https→http refused | the majority follows; the limit and stripping make it safe |
| Retries | none | none (connect-only, opt-in) | none | GET, PUT, HEAD, DELETE, OPTIONS, TRACE on 408/413/429/5xx, 2 tries | GET, HEAD on 408/429/5xx and transient errors, 3 tries | **idempotent requests** (or with `Idempotency-Key`) on transient failures and 408/429/500/502/503/504, **3 tries**, jittered backoff | resilience by default, never for requests that may not be repeated |
| `Retry-After` | — | — | — | honoured | honoured, uncapped | **honoured up to 60 s**, longer → the response is returned | a server should not park a client indefinitely |
| Timeout | none | 5 s per phase | none | 10 s | connect 5 s, receive 15 s | **30 s** per buffered exchange and per stream read (what `http-async` measures); per-phase later | waiting forever is never a default |
| Buffered body size | unbounded | unbounded | unbounded (`maxContentLength` opt-in) | unbounded | unbounded | **64 MiB**, `max_body_bytes=None` lifts it; streams are left to the reader | memory should not depend on the server |
| Decompression | on | on | on (Node) | on (fetch) | off | **on** (gzip; counted after decoding) | the majority; bounded because decoded bytes count against the limit |
| Cookies across calls | `Session` keeps them | client keeps them | browser only | browser only | not kept | **the client keeps them** | a client is a session |
| Base URL join | — | always appends | `baseURL` joins | `prefixUrl` prefixes | appends | **always appends** (a leading `/` on the path is not absolute) | RFC joining surprises people who set `/v1` |
| `params` vs. a query already in the URL | merged | replaced | merged | replaced (`searchParams`) | merged | **merged** | the majority; replacing drops data silently |
| Top-level functions | throw-away session | throw-away client | default instance | default instance | default | **throw-away client** | no global mutable state |
| Extension point | response hooks | event hooks, transports | interceptors | hooks | steps | **steps**: links of the chain, added or removed by name | one mechanism covers interceptors, hooks and policies |
| Errors | exception tree | exception tree | `AxiosError` + code | `HTTPError`, `TimeoutError` | exception structs | **one suberror** with variants and group predicates | MoonBit's error model |
| Streaming | `stream=True` | `client.stream` scope | `responseType: 'stream'` | `response.body` | `into:` | **a closure scope** `stream(…, response => …)` | the scope closes the response |
| Testing | third-party | `MockTransport` | third-party | third-party | `Req.Test` | **mock transport and virtual clock** | retries and timeouts run in virtual time |
| Sync API | sync only | both | async | async | process-based | **async only** | MoonBit async is cheap to adopt; JS has no sync networking |

## API sketch

```mbt nocheck
let client = Client::new(
  base_url="https://api.example.com/v1",
  headers=[("Accept", "application/json")],
  auth=Bearer(token),
)
let user = client.get("users/42", params=[("expand", "teams")])
  .raise_for_status()
  .json_as[User]()
client.post("users", json=new_user.to_json()) |> ignore
client.stream("GET", "export", response => {
  for chunk in response.iter_bytes() { sink.write(chunk) }
})
```

- **Calls:** `request(method, url, params?, headers?, content?, data?, files?,
  json?, timeout?, follow_redirects?, retry?, …)`; verbs as shortcuts.
- **Response:** `status`, `headers`, `content`, `text()`, `json()`,
  `json_as[T]()`, `is_success()` and siblings, `raise_for_status()`,
  `history`, `url`, `request`, `elapsed`.
- **Client options:** `base_url`, `headers`, `params`, `auth`, `cookies`,
  `timeout`, `follow_redirects`, `max_redirects`, `retry`, `max_body_bytes`,
  `steps`, `transport`, `clock`.
- **Steps:** a `Step` is `async (Request, Next) -> Response`; defaults, outermost
  first: hooks, retry, redirect, cookies, auth, transport. Each built-in step
  is a pure policy plus a thin wrapper, tested with tables, the mock transport
  and the virtual clock.
- **Errors:** `Timeout(kind~, request~)`, `Network(kind~, request~, message~)`,
  `Protocol`, `Proxy`, `UnsupportedProtocol`, `Decoding`,
  `TooManyRedirects(request~)`, `Status(request~, response~)`,
  `InvalidURL(message~)`; predicates `is_request_error()`,
  `is_transport_error()`, `is_timeout()`.
- **Models:** `URL` with an RFC 3986 resolver (port moonbitstack/moonhttp's
  vector-tested algorithm rather than depend on it), `QueryParams`, `Headers`
  over `gaato/http`'s, status-code constants.

Names in this sketch are provisional where the references disagree
(`raise_for_status`, `json_as`, `Status`); they are settled in the skeleton
milestone and listed in the README's mapping table.

## Not planned for the first release

HTTP/2 and HTTP/3, WebSockets, proxies and `trust_env`, per-phase timeouts,
connection-count limits with queueing, Digest auth, IDNA, public-suffix
cookie rules, streaming uploads. Proxies, timeouts and queueing need
`http-async` work first.

## Targets

native and moonrun wasm: everything above. JS: `http-async` uses `fetch`,
which follows redirects, applies cookies and decompresses by itself in
browsers; the README lists what the platform overrides there.

## Work in the lower layers

| Need | Layer | Also helps |
|---|---|---|
| RFC 3986 URL resolution | `gaato/http` (replacing `sdk-runtime`'s `resolve_url`) | every SDK's `base_url` |
| Redirect step with safe header stripping | `gaato/http` | the GitHub SDK's downloads |
| Connect / read / write kinds in `HttpError` | `gaato/http`, `http-async` | SDK error reports |
| Proxies, `trust_env` | `http-async` | SDK users behind proxies |
| Streaming request bodies | `gaato/http`, `http-async` | large uploads |
| Response head size limit | moonbitlang/async (upstream) | everyone |

## Milestones

1. **Skeleton:** module, README written first (with the mapping table),
   `Client`, top-level functions, body encoders, `Response`, errors, the step
   chain, mock transport.
2. **Default policies and session:** retry, redirect, cookies, base URL and
   params, auth, streaming, SSE, `URL`, `QueryParams`. First publication.
3. **Transport work:** per-phase timeouts, proxies, connection limits,
   deflate and br, Digest auth.

Each milestone keeps the stack's quality bar: table-driven tests with no real
sleeps, a closed coverage ledger, a resource-bounds ledger whose rows name
their tests, and a CHANGELOG.
