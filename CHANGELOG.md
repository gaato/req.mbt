# Changelog

All notable changes to `gaato/req` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). While the version is
0.x, a minor release (0.x → 0.y) may contain breaking changes; a patch release
never does. Every breaking change is listed with a migration note.

## [Unreleased]

## [0.1.0] - 2026-10-18

### Added

- `Client::new` with a base URL, default headers, query parameters, `Auth`
  (`Basic`, `Bearer`, `Digest`), a timeout (30 s by default) and a buffered body limit
  (64 MiB by default), plus `steps`, `transport` and `clock`. For the
  default transport: `connect_timeout`, `write_timeout`, `read_timeout`,
  `pool_timeout`, `max_connections`, `max_connections_per_origin`,
  `max_idle_per_origin`, `proxy` and `trust_env` (on by default).
- `request` and the `get`, `head`, `options`, `delete`, `post`, `put` and
  `patch` shortcuts, on a client and as top-level functions that use a
  throw-away client.
- Body encoders: `content` (bytes), `text`, `data` (URL-encoded form),
  `files` (multipart, with parts that stream), `json` and `body_stream`
  (sent as it is read), one per call, each setting its `Content-Type`
  unless the call sets one.
- `Response` with `status`, `headers`, `url`, `request`, `history` and
  `elapsed`; `content`, `text`, `json`, `json_as`, status-class predicates
  and `raise_for_status`; `Response::new` for steps and tests.
- `Client::stream` and the top-level `stream`: the response arrives with its
  body on the connection, read with `read`, `read_some`, `each_chunk` or
  `each_line` (lines up to `max_line_bytes`, 16 MiB by default), and closed
  when the callback returns. Calling `close` in an `each_*` callback stops
  the loop there.
- Server-sent events: `Response::each_event` parses a `text/event-stream`
  body into `SseEvent`s (each up to `max_event_bytes`, 16 MiB by default),
  and `Client::sse` and the top-level `sse` send the request with
  `Accept: text/event-stream` and `Cache-Control: no-store` and call back with each event, raising
  `Status` for a non-2xx response. No automatic reconnection.
- `Url`, gaato/http's RFC 3986 URL, to take apart, resolve and compare
  response URLs. A call's URL is parsed with it before sending: a bad port,
  IPv6 literal or host raises `InvalidURL`, and the URL sent is normalised
  (lower-case scheme and host, no default port, no dot segments, non-ASCII
  percent-encoded). Credentials in the URL (`user:pass@`) leave it and are
  sent as Basic `Authorization`, in place of the client's `auth`, unless
  the call sets `Authorization`, as requests and httpx do; error messages
  and debug output show them as `<redacted>`.
- `ReqError`, one error for every failure, naming the phase a transport
  failure happened in, with `is_timeout`, `is_transport_error` and
  `is_unsent`.
- Retries, on by default: `Retry::new` (3 retries of GET, HEAD, OPTIONS,
  PUT, DELETE and TRACE on 408, 429, 500, 502, 503, 504, `Timeout` and
  `Network`, and of any method when nothing reached the server) and
  `Retry::none()`, per client and per call (`retry`). `Retry-After` is
  honoured up to 60 s, otherwise the wait is exponential with full jitter on
  the client's clock; a body that streams is never sent twice. Retries and
  auth run per redirect hop, as in requests and Req: only the hop that
  failed is sent again, and auth answers each hop on the call's origin
  with that hop's method and URI.
- `Auth::Digest` (RFC 7616 and RFC 2617): MD5, SHA-256 and their `-sess`
  forms, qop `auth` and `auth-int`, `userhash`, stale nonces, and nonce
  reuse per origin with a counted `nc`.
- `Client::new(random~)`, the source of retry jitter, Digest client nonces
  and multipart boundaries.
- `Step`, a link of the chain around the transport, and the `on_request` and
  `on_response` hooks built on it.
- `MockTransport`, a transport that answers with a function, for tests.
- Redirects, followed by default with gaato/http's `follow_redirects`:
  `follow_redirects` per client and per call, `max_redirects` (10 by
  default). 303, and 301 or 302 after `POST`, become `GET` without the
  body; `Authorization`, `Cookie` and `Proxy-Authorization` are dropped
  when the origin changes; `https` to `http` and resending a stream body
  are refused with `InvalidRedirect`, a longer chain with
  `TooManyRedirects`. `history` holds the redirect responses, oldest first,
  and `url` the final URL; a streamed call closes each redirect before the
  next request.
- Cookies: a client keeps an RFC 6265 jar of its own on its clock (50
  cookies per domain, 3000 in all) and applies it on every redirect hop;
  `cookies=Jar(jar)` shares or seeds one, `cookies=Off` keeps none.
  `Client::cookies`, and `CookieJar`, `Cookie` and `SameSite` from
  gaato/http.
