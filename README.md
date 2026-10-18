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
- Client defaults: `base_url` (always appended to), `headers`, `params` (merged into any query already in the URL), `auth` (`Basic`, `Bearer`), `timeout`.
- One body per call: `content` (bytes), `text`, `data` (form), `files` (multipart, `@req.Part`) or `json`.
- A response is a value whatever its status; `raise_for_status()` turns non-2xx into `ReqError::Status`.
- Bounded by default: 30 s per exchange, 64 MiB per buffered body.
- `steps`, links of the chain around the transport, with `on_request` and `on_response` hooks.
- Tests swap the transport for `MockTransport::new(request => response)` and the clock for `VirtualClock` from `gaato/http-async/mock`.

Not yet: retries, following redirects, cookies, streaming, proxies. On JS, `fetch` follows redirects and applies cookies by itself.

## Coming from

| | requests / httpx | axios / ky | Req | gaato/req |
|---|---|---|---|---|
| Call | `httpx.get(url, params=...)` | `ky.get(url, {searchParams})` | `Req.get!(url, params: ...)` | `@req.get(url, params=[...])` |
| Client | `httpx.Client(base_url=...)` | `axios.create({baseURL})` | `Req.new(base_url: ...)` | `@req.Client::new(base_url=...)` |
| JSON body | `json=...` | `json: ...` (ky) | `json: ...` | `json=...` |
| Non-2xx | value, `raise_for_status()` | throws | value | value, `raise_for_status()` |
| Read JSON | `.json()` | `.json()` / `data` | `.body` | `.json()`, `.json_as()` |
| Hooks | `event_hooks` | interceptors / hooks | steps | `steps=[on_request(...), ...]` |
| Mock | `httpx.MockTransport` | — | `Req.Test` | `@req.MockTransport` |

Unofficial and experimental. Apache-2.0.
