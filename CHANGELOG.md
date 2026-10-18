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
- `ReqError`, one error for every failure, naming the phase a transport
  failure happened in, with `is_timeout`, `is_transport_error` and
  `is_unsent`.
- `Step`, a link of the chain around the transport, and the `on_request` and
  `on_response` hooks built on it.
- `MockTransport`, a transport that answers with a function, for tests.
