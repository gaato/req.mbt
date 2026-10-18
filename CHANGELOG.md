# Changelog

All notable changes to `gaato/req` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). While the version is
0.x, a minor release (0.x → 0.y) may contain breaking changes; a patch release
never does. Every breaking change is listed with a migration note.

## [Unreleased]

### Added

- `Client::new` with a base URL, default headers, query parameters, `Auth`
  (`Basic`, `Bearer`), a timeout (30 s by default) and a buffered body limit
  for the default transport (64 MiB by default), plus `steps`, `transport`
  and `clock`.
- `request` and the `get`, `head`, `options`, `delete`, `post`, `put` and
  `patch` shortcuts, on a client and as top-level functions that use a
  throw-away client.
- Body encoders: `content` (bytes), `text`, `data` (URL-encoded form),
  `files` (multipart) and `json`, one per call, each setting its
  `Content-Type` unless the call sets one.
- `Response` with `status`, `headers`, `content`, `url`, `request` and
  `elapsed`; `text`, `json`, `json_as`, status-class predicates and
  `raise_for_status`.
- `ReqError`, one error for every failure, with `is_timeout` and
  `is_transport_error`.
- `Step`, a link of the chain around the transport, and the `on_request` and
  `on_response` hooks built on it.
- `MockTransport`, a transport that answers with a function, for tests.
