///|
/// A body stream that yields `chunks`, then its end, counting reads and
/// closes.
struct Chunks {
  chunks : Array[Bytes]
  mut reads : Int32
  mut closed : Int32
}

///|
fn Chunks::new(chunks : Array[Bytes]) -> Chunks {
  { chunks, reads: 0, closed: 0, }
}

///|
impl @http.BodyStream for Chunks with fn read_some(self) {
  let chunk = self.chunks.get(self.reads)
  self.reads += 1
  chunk
}

///|
impl @http.BodyStream for Chunks with fn close(self) {
  self.closed += 1
}

///|
/// A transport that records each request and streams `body` with `status`
/// and `headers`.
struct ChunksTransport {
  sent : Array[@requesto.Request]
  status : Int32
  headers : Array[(String, String)]
  body : Chunks
}

///|
impl @http.Transport for ChunksTransport with fn send(_, _) {
  raise @http.HttpError::Protocol("buffered calls are not used here")
}

///|
impl @http.Transport for ChunksTransport with fn send_stream(self, request) {
  self.sent.push(request)
  (
    { status: self.status, headers: @http.Headers::from_array(self.headers), },
    self.body,
  )
}

///|
let event_stream : Array[(String, String)] = [
  ("Content-Type", "text/event-stream"),
]

///|
/// A client whose streamed responses carry `chunks`.
fn chunks_client(
  body : Chunks,
  sent~ : Array[@requesto.Request] = [],
  status~ : Int32 = 200,
  headers~ : Array[(String, String)] = event_stream,
  client_headers~ : Array[(String, String)] = [],
  max_body_bytes? : Int32?,
) -> @requesto.Client {
  @requesto.Client::new(
    transport=ChunksTransport::{ sent, status, headers, body, },
    headers=client_headers,
    max_body_bytes?,
    retry=@requesto.Retry::none(),
  )
}

///|
/// The variant a body operation raised, with its message where it has one.
fn failure(error : Error) -> String {
  match error {
    @requesto.RequestoError::Protocol(message~, ..) => "Protocol \{message}"
    @requesto.RequestoError::Decoding(message~) => "Decoding \{message}"
    @requesto.RequestoError::Status(response~, ..) => {
      let text = response.text() catch { _ => "<unread>" }
      "Status \{response.status} \{text}"
    }
    @requesto.RequestoError::StreamConsumed(..) => "StreamConsumed"
    @requesto.RequestoError::UnsupportedProtocol(url~) =>
      "UnsupportedProtocol \{url}"
    error => "unexpected \{error}"
  }
}

///|
async test "each_event parses events across chunks and closes the body at its end" {
  let body = Chunks::new([
    b"", b": comment\ndata: a\r", b"\n\r\nid: 1\nevent: tick\ndata: b\ndata: c\n",
    b"\nretry: 3000\ndata: d\n\ndata: unfinished",
  ])
  let events = []
  chunks_client(body).stream("GET", "https://a.test/events", response => {
    response.each_event(event => events.push(event))
  })
  assert_eq(events, [
    { event: "message", data: "a", id: None, retry: None, },
    { event: "tick", data: "b\nc", id: Some("1"), retry: None, },
    { event: "message", data: "d", id: Some("1"), retry: Some(3000), },
  ])
  assert_eq(body.closed, 1)
}

///|
async test "each_event refuses a body that is not an event stream, unread" {
  let cases : Array[(Array[(String, String)], String)] = [
    (
      [("Content-Type", "application/json")],
      "Decoding expected text/event-stream, got application/json",
    ),
    ([], "Decoding expected text/event-stream, got no Content-Type"),
  ]
  for case in cases {
    let body = Chunks::new([b"{\"error\":\"nope\"}"])
    let (outcome, text) = chunks_client(body, headers=case.0).stream(
      "GET",
      "https://a.test/events",
      response => {
        let outcome = try response.each_event(_ => ()) catch {
          error => failure(error)
        } noraise {
          _ => "read"
        }
        (outcome, response.read() |> @utf8.decode_lossy)
      },
    )
    assert_eq(outcome, case.1)
    assert_eq(text, "{\"error\":\"nope\"}", msg="the body is left to read")
  }
}

///|
async test "each_event holds max_event_bytes of an event and refuses one more" {
  // `data: abcd` is ten bytes.
  let fits = Chunks::new([b"data: abcd\n\n"])
  let events = []
  chunks_client(fits).stream("GET", "https://a.test/events", response => {
    response.each_event(event => events.push(event.data), max_event_bytes=10)
  })
  assert_eq(events, ["abcd"])
  let larger = Chunks::new([b"data: a\n\ndata: abcde\n\n", b"data: never\n\n"])
  let events = []
  let outcome = try
    chunks_client(larger).stream("GET", "https://a.test/events", response => {
      response.each_event(event => events.push(event.data), max_event_bytes=10)
    })
  catch {
    error => failure(error)
  } noraise {
    _ => "ended"
  }
  assert_eq(outcome, "Protocol SSE event larger than 10 bytes")
  assert_eq(events, ["a"], msg="the events before it are dispatched")
  assert_eq(larger.reads, 1, msg="nothing is read after it")
  assert_eq(larger.closed, 1)
}

///|
async test "each_event, each_line and each_chunk stop when f closes the response" {
  let body = Chunks::new([b"data: 1\n\ndata: 2\n\n", b"data: 3\n\n"])
  let events = []
  chunks_client(body).stream("GET", "https://a.test/events", response => {
    response.each_event(event => {
      events.push(event.data)
      response.close()
    })
  })
  assert_eq(events, ["1"])
  assert_eq(body.reads, 1)
  assert_eq(body.closed, 1)
  let body = Chunks::new([b"a\nb\n", b"c"])
  let lines = []
  chunks_client(body).stream("GET", "https://a.test/lines", response => {
    response.each_line(line => {
      lines.push(line)
      if line == "b" {
        response.close()
      }
    })
  })
  assert_eq(lines, ["a", "b"])
  assert_eq(body.reads, 1)
  let body = Chunks::new([b"a", b"b"])
  let chunks = []
  chunks_client(body).stream("GET", "https://a.test/raw", response => {
    response.each_chunk(chunk => {
      chunks.push(chunk)
      response.close()
    })
  })
  assert_eq(chunks, [b"a"])
  assert_eq(body.reads, 1)
  let body = Chunks::new([b"a\nb"])
  let lines = []
  chunks_client(body).stream("GET", "https://a.test/lines", response => {
    response.each_line(line => {
      lines.push(line)
      response.close()
    })
  })
  assert_eq(lines, ["a"], msg="the unterminated last line is not handed over")
}

///|
async test "a body in memory is parsed in slices, so every event arrives" {
  let event = b"data: \{"x".repeat(1000)}\n\n"
  let buffer = Buffer()
  for _ in 0..<200 {
    buffer.write_bytes(event)
  }
  let content = buffer.to_bytes()
  assert_true(content.length() > 3 * 65_536)
  let response = @requesto.Response::new(
    200,
    @http.Request::get("https://a.test/events"),
    headers=@http.Headers::from_array(event_stream),
    content~,
  )
  let mut count = 0
  response.each_event(event => {
    assert_eq(event.data.length(), 1000)
    count += 1
  })
  assert_eq(count, 200)
  let response = @requesto.Response::new(
    200,
    @http.Request::get("https://a.test/lines"),
    content~,
  )
  let mut lines = 0
  response.each_line(_ => lines += 1)
  assert_eq(lines, 400, msg="each event is a data line and a blank one")
}

///|
async test "each_line holds max_line_bytes of a line and refuses one more" {
  let fits = Chunks::new([b"abc\r", b"\nde", b"f"])
  let lines = []
  chunks_client(fits).stream("GET", "https://a.test/lines", response => {
    response.each_line(line => lines.push(line), max_line_bytes=3)
  })
  assert_eq(lines, ["abc", "def"])
  assert_eq(fits.closed, 1)
  let larger = Chunks::new([b"abc\nabcd\n", b"never\n"])
  let lines = []
  let outcome = try
    chunks_client(larger).stream("GET", "https://a.test/lines", response => {
      response.each_line(line => lines.push(line), max_line_bytes=3)
    })
  catch {
    error => failure(error)
  } noraise {
    _ => "ended"
  }
  assert_eq(outcome, "Protocol a line is longer than max_line_bytes (3)")
  assert_eq(lines, ["abc"], msg="the lines before it are handed over")
  assert_eq(larger.reads, 1)
  assert_eq(larger.closed, 1)
}

///|
async test "sse asks for an uncached event stream unless the call says otherwise" {
  let cases : Array[
    (Array[(String, String)], Array[(String, String)], String, String),
  ] = [
    ([], [], "text/event-stream", "no-store"),
    ([("Accept", "application/json")], [], "text/event-stream", "no-store"),
    (
      [],
      [("accept", "text/event-stream, */*")],
      "text/event-stream, */*",
      "no-store",
    ),
    ([], [("Cache-Control", "no-cache")], "text/event-stream", "no-cache"),
  ]
  for case in cases {
    let sent = []
    let events = []
    chunks_client(Chunks::new([b"data: hi\n\n"]), sent~, client_headers=case.0).sse(
      "GET",
      "https://a.test/events",
      headers=case.1,
      event => events.push(event.data),
    )
    assert_eq(sent[0].headers.get_all("accept"), [case.2])
    assert_eq(sent[0].headers.get_all("cache-control"), [case.3])
    assert_eq(events, ["hi"])
  }
}

///|
async test "sse raises Status with the body, returns on 204 and refuses other types" {
  let cases : Array[(Int32, Array[(String, String)], Int32?, String)] = [
    (401, [("Content-Type", "application/json")], None, "Status 401 {\"e\":1}"),
    (500, [], Some(3), "Status 500 <unread>"),
    (204, [], None, "ended"),
    (
      200,
      [("Content-Type", "text/html")],
      None,
      "Decoding expected text/event-stream, got text/html",
    ),
  ]
  for case in cases {
    let (status, headers, max_body_bytes, expected) = case
    let body = Chunks::new([b"{\"e\":1}"])
    let mut events = 0
    let outcome = try
      chunks_client(body, status~, headers~, max_body_bytes~).sse(
        "GET",
        "https://a.test/events",
        _ => events += 1,
      )
    catch {
      error => failure(error)
    } noraise {
      _ => "ended"
    }
    assert_eq(outcome, expected, msg="status \{status}")
    assert_eq(events, 0)
    assert_eq(body.closed, 1)
  }
}

///|
async test "sse with a throw-away client refuses what Client::sse refuses" {
  let outcome = try @requesto.sse("GET", "ftp://a.test/events", _ => ()) catch {
    error => failure(error)
  } noraise {
    _ => "ended"
  }
  assert_eq(outcome, "UnsupportedProtocol ftp://a.test/events")
}

///|
async test "close in a callback stops each_line and each_event on a buffered body" {
  let request = @http.Request::get("https://a.test/")
  let lines = []
  let buffered = @requesto.Response::new(200, request, content=b"a\nb\nc\n")
  buffered.each_line(line => {
    lines.push(line)
    buffered.close()
  })
  assert_eq(lines, ["a"])
  let events = []
  let stream = @requesto.Response::new(
    200,
    request,
    headers=@http.Headers::from_array([("Content-Type", "text/event-stream")]),
    content=b"data: 1\n\ndata: 2\n\n",
  )
  stream.each_event(event => {
    events.push(event.data)
    stream.close()
  })
  assert_eq(events, ["1"])
  assert_eq(buffered.text(), "a\nb\nc\n", msg="the body stays readable")
}

///|
/// A body stream fed from a queue: each `put` is one chunk, `None` the end.
struct Queued {
  queue : @aqueue.Queue[Bytes?]
}

///|
impl @http.BodyStream for Queued with fn read_some(self) {
  self.queue.get() catch {
    _ => None
  }
}

///|
impl @http.BodyStream for Queued with fn close(_) {
  ()
}

///|
/// A transport streaming an event stream from `body`.
struct QueuedTransport {
  body : Queued
}

///|
impl @http.Transport for QueuedTransport with fn send(_, _) {
  raise @http.HttpError::Protocol("buffered calls are not used here")
}

///|
impl @http.Transport for QueuedTransport with fn send_stream(self, _) {
  (
    { status: 200, headers: @http.Headers::from_array(event_stream), },
    self.body,
  )
}

///|
/// Runs `call` in the background; the outcome lands in the returned cell as
/// `"ended"` or the error's variant, phase and limit.
fn sse_bg(
  group : @async.TaskGroup[Unit],
  call : async () -> Unit,
) -> Ref[String?] {
  let outcome = Ref(None)
  group.spawn_bg(() => {
    outcome.val = Some(
      try call() catch {
        @requesto.RequestoError::Timeout(phase~, timeout~, ..) =>
          "Timeout \{@debug.to_string(phase)} \{timeout}"
        error => "unexpected \{error}"
      } noraise {
        _ => "ended"
      },
    )
  })
  outcome
}

///|
async test "sse waits 5 minutes for the next bytes by default, and idle_timeout replaces it" {
  let clock = @simclock.VirtualClock()
  let body = Queued::{ queue: Queue(kind=Unbounded), }
  let client = @requesto.Client::new(
    transport=QueuedTransport::{ body, },
    clock~,
    retry=@requesto.Retry::none(),
  )
  @async.with_task_group(group => {
    let seen = []
    let outcome = sse_bg(group, () => {
      client.sse("GET", "https://a.test/events", event => seen.push(event.data))
    })
    clock.advance(240_000)
    body.queue.put(Some(b"data: after 4 minutes\n\n"))
    clock.settle()
    assert_eq(seen, ["after 4 minutes"], msg="past the 30 s timeout")
    clock.advance(299_999)
    assert_eq(outcome.val, None)
    clock.advance(1)
    assert_eq(outcome.val, Some("Timeout Body 300000"))
  })
  @async.with_task_group(group => {
    let short = sse_bg(group, () => {
      client.sse("GET", "https://a.test/events", idle_timeout=Some(1000), _ => {
        ()
      })
    })
    let unbounded = sse_bg(group, () => {
      client.sse("GET", "https://a.test/events", idle_timeout=None, _ => ())
    })
    clock.advance(1000)
    assert_eq(short.val, Some("Timeout Body 1000"))
    clock.advance(10_000_000)
    assert_eq(unbounded.val, None, msg="no bound")
    body.queue.put(None)
    clock.settle()
    assert_eq(unbounded.val, Some("ended"))
    assert_eq(clock.pending(), [])
  })
}

///|
async test "each_event on a streamed response keeps the call's timeout unless idle_timeout replaces it" {
  let clock = @simclock.VirtualClock()
  let body = Queued::{ queue: Queue(kind=Unbounded), }
  let client = @requesto.Client::new(
    transport=QueuedTransport::{ body, },
    clock~,
    timeout=100,
    retry=@requesto.Retry::none(),
  )
  @async.with_task_group(group => {
    let kept = sse_bg(group, () => {
      client.stream("GET", "https://a.test/events", response => {
        response.each_event(_ => ())
      })
    })
    let replaced = sse_bg(group, () => {
      client.stream("GET", "https://a.test/events", response => {
        response.each_event(_ => (), idle_timeout=Some(500))
      })
    })
    clock.advance(100)
    assert_eq(kept.val, Some("Timeout Body 100"))
    assert_eq(replaced.val, None)
    clock.advance(400)
    assert_eq(replaced.val, Some("Timeout Body 500"))
    assert_eq(clock.pending(), [])
  })
}
