///|
/// One server-sent event: `@sse.SseEvent` of gaato/http, with its `event`
/// type (`"message"` unless the stream names one), its `data` lines joined
/// with `\n`, the last `id` the stream set, and the `retry` delay it asked
/// for, in milliseconds and capped at one hour.
pub type SseEvent = @sse.SseEvent

///|
/// Whether a `Content-Type` value names `text/event-stream`, whatever its
/// case and parameters.
fn is_event_stream(content_type : String?) -> Bool {
  guard content_type is Some(value) else { return false }
  let media_type = match value.find(";") {
    Some(i) => value[:i]
    None => value[:]
  }
  media_type.trim(chars=" \t").to_owned().to_lower() == "text/event-stream"
}

///|
/// `headers` with `(name, value)` added unless they already name it.
fn with_default_header(
  headers : Array[(String, String)],
  name : String,
  value : String,
) -> Array[(String, String)] {
  let lower = name.to_lower()
  if headers.iter().any(pair => pair.0.to_lower() == lower) {
    headers
  } else {
    [..headers, (name, value)]
  }
}

///|
/// The events `bytes` completes. An event over the parser's bound closes
/// the body and raises `Protocol`.
fn Response::parse_events(
  self : Response,
  parser : @sse.SseParser,
  bytes : Bytes,
) -> Array[SseEvent] raise ReqError {
  parser.feed(bytes) catch {
    error => {
      self.close()
      raise map_transport_error(error, self.request)
    }
  }
}

///|
/// Calls `f` with each server-sent event of the body, in order, until its
/// end. Calling `close` in `f` stops there.
///
/// Raises `Decoding` without reading when the response's `Content-Type` is
/// not `text/event-stream`, such as an error page. An event larger than
/// `max_event_bytes` (16 MiB by default) closes the body and raises
/// `Protocol`, after the events before it. Each read waits at most the
/// call's `timeout`, so a stream that stays silent longer needs a longer
/// one.
///
/// ```mbt check
/// async test {
///   let client = @req.Client::new(
///     transport=@req.MockTransport::new(_ => {
///       status: 200,
///       headers: @http.Headers::from_array([("Content-Type", "text/event-stream")]),
///       body: b"data: one\n\nevent: done\ndata: two\n\n",
///     }),
///   )
///   let seen = []
///   client.stream("GET", "https://example.com/events", response => {
///     response.each_event(event => seen.push("\{event.event} \{event.data}"))
///   })
///   assert_eq(seen, ["message one", "done two"])
/// }
/// ```
pub async fn Response::each_event(
  self : Response,
  f : async (SseEvent) -> Unit,
  max_event_bytes? : Int32,
) -> Unit {
  let content_type = self.headers.get("content-type")
  guard is_event_stream(content_type) else {
    raise Decoding(
      message="expected text/event-stream, got \{content_type.unwrap_or("no Content-Type")}",
    )
  }
  let parser = @sse.SseParser::new(max_event_bytes?)
  self.each_slice(slice => {
    for event in self.parse_events(parser, slice) {
      f(event)
      if self.is_closed() {
        return
      }
    }
    // Raises an overflow that followed those events in the same slice, so
    // none is left for `SseParser::finish`, and an unfinished event at the
    // end is dropped as the parser's `finish` would drop it.
    ignore(self.parse_events(parser, b""))
  })
}

///|
/// Sends a request for a server-sent event stream and calls `f` with each
/// event, until the stream ends. The arguments are those of
/// `Client::stream`; `Accept: text/event-stream` and `Cache-Control:
/// no-store` are sent unless `headers` set them, so that no cache in
/// between holds the stream back.
///
/// A status outside 200 through 299 raises `Status`, with as much of the
/// body as `max_body_bytes` lets it read; 204 No Content, a server's way to
/// say there are no events, returns at once. Otherwise the body is read as
/// `Response::each_event` reads it.
///
/// There is no reconnection: when the stream ends, so does the call. To
/// resume, call again with a `Last-Event-ID` header holding the last
/// event's `id`, after waiting its `retry`. For the response itself, its
/// headers or stopping early, use `stream` and `each_event`.
///
/// ```mbt check
/// async test {
///   let client = @req.Client::new(
///     transport=@req.MockTransport::new(_ => {
///       status: 200,
///       headers: @http.Headers::from_array([("Content-Type", "text/event-stream")]),
///       body: b"id: 7\ndata: hello\n\n",
///     }),
///   )
///   let seen = []
///   client.sse("GET", "https://example.com/events", event => seen.push(event))
///   assert_eq(seen.map(event => (event.data, event.id)), [("hello", Some("7"))])
/// }
/// ```
pub async fn Client::sse(
  self : Client,
  http_method : String,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
  body_stream? : &@http.BodyStream,
  body_length? : Int64,
  timeout? : Int32,
  max_event_bytes? : Int32,
  f : async (SseEvent) -> Unit,
) -> Unit {
  self.stream(
    http_method,
    url,
    params~,
    headers=with_default_header(
      with_default_header(headers, "Accept", "text/event-stream"),
      "Cache-Control",
      "no-store",
    ),
    content?,
    text?,
    data?,
    files?,
    json?,
    body_stream?,
    body_length?,
    timeout?,
    response => {
      if response.status == 204 {
        return
      }
      if !response.is_success() {
        // The error keeps what of the body can be read; the status wins
        // over a failure to read it.
        ignore(response.read()) catch {
          _ => ()
        }
        raise Status(request=response.request, response~)
      }
      response.each_event(f, max_event_bytes?)
    },
  )
}

///|
/// Reads a server-sent event stream with a throw-away client, closed
/// afterwards. The arguments are those of `Client::sse`.
pub async fn sse(
  http_method : String,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
  body_stream? : &@http.BodyStream,
  body_length? : Int64,
  timeout? : Int32,
  max_event_bytes? : Int32,
  f : async (SseEvent) -> Unit,
) -> Unit {
  let client = Client::new()
  defer client.close()
  client.sse(
    http_method,
    url,
    params~,
    headers~,
    content?,
    text?,
    data?,
    files?,
    json?,
    body_stream?,
    body_length?,
    timeout?,
    max_event_bytes?,
    f,
  )
}
