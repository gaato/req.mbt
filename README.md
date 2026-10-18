# gaato/req

An async HTTP client for MoonBit: verb functions, a client with defaults, body encoders, and responses as values. Native, JS and moonrun Wasm.

```fish
moon add gaato/req
```

```mbt nocheck
///|
struct User {
  id : Int
  name : String
} derive(FromJson)

///|
async fn example() -> Unit raise {
  let client = @req.Client::new(
    base_url="https://api.example.com/v1",
    headers=[("Accept", "application/json")],
    auth=Bearer("token"),
  )
  defer client.close()
  let user : User = client
    .get("users/42", params=[("expand", "teams")])
    .raise_for_status()
    .json_as()
  client.post("users", json={ "name": user.name }) |> ignore
  println(@req.get("https://example.com/").text())
}
```

## What it does

- `get`, `post`, `put`, `patch`, `delete`, `head`, `options` and `request`, on a `Client` or as top-level functions.
- Client defaults: `base_url` (always appended to), `headers`, `params` (merged into any query already in the URL), `auth` (`Basic`, `Bearer`, `Digest`), `timeout`, `retry`.
- Retries by default: idempotent methods on 408, 429, 500, 502, 503, 504 and transport failures, any method when nothing was sent; `Retry-After` up to 60 s, else backoff with jitter. `retry=Retry::none()` turns them off.
- One body per call: `content` (bytes), `text`, `data` (form), `files` (multipart, `@req.Part`), `json` or `body_stream`.
- A response is a value whatever its status; `raise_for_status()` turns non-2xx into `ReqError::Status`.
- Redirects followed (at most 10, credentials dropped across origins, no `https` to `http`), with `history`; `follow_redirects=false` per client or call.
- Cookies kept per client in an RFC 6265 jar, `client.cookies()`; `cookies=Jar(jar)` shares one, `cookies=Off` keeps none.
- Streaming both ways: `stream` hands over the response while its body is still arriving (`read_some`, `each_chunk`, `each_line`); `body_stream` and `Part::file_stream` send a body as it is read.
- Server-sent events: `client.sse("GET", url, event => ...)`, or `each_event` on a streamed response.
- URLs checked and normalised before sending; `@req.Url` takes response URLs apart and resolves links.
- Timeouts per call and per phase (`connect_timeout`, `write_timeout`, `read_timeout`, `pool_timeout`), `proxy` (or `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`), and connection limits (`max_connections`, `max_connections_per_origin`).
- Bounded by default: 30 s per exchange, 64 MiB per buffered body, 16 MiB per event or line.
- `steps`, links of the chain around the transport, with `on_request` and `on_response` hooks.
- Tests swap the transport for `MockTransport::new(request => response)` and the clock for `VirtualClock` from `gaato/http-async/mock`.

Not yet: HTTP/2, response caching. On JS, `fetch` follows redirects before the client sees them, and in browsers handles cookies itself.

## Coming from

| | requests / httpx | axios / ky | Req | gaato/req |
|---|---|---|---|---|
| Call | `httpx.get(url, params=...)` | `ky.get(url, {searchParams})` | `Req.get!(url, params: ...)` | `@req.get(url, params=[...])` |
| Client | `httpx.Client(base_url=...)` | `axios.create({baseURL})` | `Req.new(base_url: ...)` | `@req.Client::new(base_url=...)` |
| JSON body | `json=...` | `json: ...` (ky) | `json: ...` | `json=...` |
| Non-2xx | value, `raise_for_status()` | throws | value | value, `raise_for_status()` |
| Read JSON | `.json()` | `.json()` / `data` | `.body` | `.json()`, `.json_as()` |
| Redirects | `follow_redirects=`, `.history` | `maxRedirects` / `redirect` | `redirect:`, `max_redirects:` | `follow_redirects=`, `max_redirects=`, `.history` |
| Cookies | `client.cookies` | the browser's | — | `client.cookies()`, `cookies=Jar(jar)` |
| Streaming | `client.stream(...)`, `iter_lines()` | `responseType: 'stream'` | `into: fun` | `client.stream(...)`, `each_line` |
| SSE | `httpx_sse.connect_sse` | `EventSource` | — | `client.sse(...)`, `each_event` |
| Timeouts | `httpx.Timeout(connect=...)` | `timeout` | `receive_timeout:` | `timeout=`, `connect_timeout=`, ... |
| Proxy | `proxy=` | `proxy` (axios) | `connect_options:` | `proxy=`, `trust_env` |
| Hooks | `event_hooks` | interceptors / hooks | steps | `steps=[on_request(...), ...]` |
| Retries | `HTTPAdapter(max_retries=Retry(...))` (off) | `retry` (ky, on) | `retry: :safe_transient` (on) | `retry=Retry::new(...)` (on) |
| Digest | `HTTPDigestAuth` / `DigestAuth` | — | — | `auth=Digest(username=u, password=p)` |
| Mock | `httpx.MockTransport` | — | `Req.Test` | `@req.MockTransport` |

Unofficial and experimental. Apache-2.0.
