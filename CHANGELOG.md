# Changelog

All notable changes to `gaato/req` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). While the version is
0.x, a minor release (0.x → 0.y) may contain breaking changes; a patch release
never does. Every breaking change is listed with a migration note.

## [Unreleased]

### Added

- `Client::new` with a base URL, default headers, query parameters, `Auth`
  (`Basic`, `Bearer`), a timeout (30 s by default) and a buffered body limit
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
  body on the connection, read with `read`, `read_some` or `each_chunk`,
  and closed when the callback returns.
- `Url`, gaato/http's RFC 3986 URL, to take apart, resolve and compare
  response URLs. A call's URL is parsed with it before sending: a bad port,
  IPv6 literal or host raises `InvalidURL`, and the URL sent is normalised
  (lower-case scheme and host, no default port, no dot segments, non-ASCII
  percent-encoded).
- `ReqError`, one error for every failure, naming the phase a transport
  failure happened in, with `is_timeout`, `is_transport_error` and
  `is_unsent`.
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
