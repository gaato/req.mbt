///|
/// A body stream fed from a queue: each `put` is one chunk, `None` the end.
/// It records how many times it was closed.
struct Fed {
  queue : @aqueue.Queue[Bytes?]
  mut closed : Int32
}

///|
fn Fed::new() -> Fed {
  { queue: Queue(kind=Unbounded), closed: 0, }
}

///|
impl @http.BodyStream for Fed with fn read_some(self) {
  self.queue.get() catch {
    _ => None
  }
}

///|
impl @http.BodyStream for Fed with fn close(self) {
  self.closed += 1
}

///|
/// A transport whose streamed responses read from `body`, and whose
/// buffered responses carry `buffered`.
struct FedTransport {
  body : Fed
  buffered : Bytes
}

///|
impl @http.Transport for FedTransport with fn send(self, _) {
  { status: 200, headers: @http.Headers::new(), body: self.buffered, }
}

///|
impl @http.Transport for FedTransport with fn send_stream(self, _) {
  ({ status: 200, headers: @http.Headers::new(), }, self.body)
}

///|
fn fed_client(
  body : Fed,
  buffered~ : Bytes = b"",
  clock? : &@clock.Clock,
  max_body_bytes? : Int32?,
) -> @req.Client {
  @req.Client::new(
    transport=FedTransport::{ body, buffered, },
    clock?,
    max_body_bytes?,
  )
}

///|
/// What a body operation returned, or the variant it raised.
fn variant(error : Error) -> String {
  match error {
    @req.ReqError::ResponseNotRead(..) => "ResponseNotRead"
    @req.ReqError::StreamConsumed(..) => "StreamConsumed"
    @req.ReqError::Timeout(phase~, timeout~, ..) =>
      "Timeout \{@debug.to_string(phase)} \{timeout}"
    @req.ReqError::Protocol(message~, ..) => "Protocol \{message}"
    error => "unexpected \{error}"
  }
}

///|
async test "a streamed body is unread until read, then content works" {
  let body = Fed::new()
  body.queue.put(Some(b"ab"))
  body.queue.put(Some(b"c"))
  body.queue.put(None)
  let client = fed_client(body)
  let (before, read, after) = client.stream("GET", "https://a.test/", response => {
    let before = try response.content() catch {
      error => variant(error)
    } noraise {
      _ => "content"
    }
    let read = response.read()
    (before, read, response.text())
  })
  assert_eq(before, "ResponseNotRead")
  assert_eq(read, b"abc")
  assert_eq(after, "abc")
  assert_eq(body.closed, 1, msg="the end of the body closes the stream once")
}

///|
async test "a body taken chunk by chunk is consumed: content and read refuse" {
  let body = Fed::new()
  body.queue.put(Some(b"ab"))
  body.queue.put(Some(b"c"))
  body.queue.put(None)
  let client = fed_client(body)
  let (chunks, content, read, again) = client.stream("GET", "https://a.test/", response => {
    let chunks = []
    response.each_chunk(chunk => chunks.push(chunk))
    let content = try response.content() catch {
      error => variant(error)
    } noraise {
      _ => "content"
    }
    let read = try response.read() catch {
      error => variant(error)
    } noraise {
      _ => "read"
    }
    (chunks, content, read, response.read_some())
  })
  assert_eq(chunks, [b"ab", b"c"])
  assert_eq(content, "StreamConsumed")
  assert_eq(read, "StreamConsumed")
  assert_eq(again, None, msg="the end stays the end")
  assert_eq(body.closed, 1)
}

///|
async test "a streamed body f leaves unread is closed when f returns" {
  let body = Fed::new()
  body.queue.put(Some(b"ab"))
  let client = fed_client(body)
  let first : Bytes? = client.stream("GET", "https://a.test/", response => {
    response.read_some()
  })
  assert_eq(first, Some(b"ab"))
  assert_eq(body.closed, 1)
}

///|
suberror Stop

///|
async test "a streamed body is closed when f raises, and reads after close refuse" {
  let body = Fed::new()
  let client = fed_client(body)
  let kept : Ref[@req.Response?] = Ref(None)
  let outcome = try {
    let _ : Unit = client.stream("GET", "https://a.test/", response => {
      kept.val = Some(response)
      raise Stop
    })
    "returned"
  } catch {
    Stop => "Stop"
    error => "unexpected \{error}"
  }
  assert_eq(outcome, "Stop")
  assert_eq(body.closed, 1)
  guard kept.val is Some(response) else { fail("no response") }
  let read = try response.read_some() catch {
    error => variant(error)
  } noraise {
    _ => "chunk"
  }
  assert_eq(read, "StreamConsumed")
  response.close()
  assert_eq(body.closed, 1, msg="closing again does nothing")
}

///|
async test "each read of a streamed body is bounded by the call's timeout" {
  let clock = @simclock.VirtualClock()
  let body = Fed::new()
  let client = fed_client(body, clock~)
  @async.with_task_group(group => {
    let outcome : Ref[String?] = Ref(None)
    group.spawn_bg(() => {
      outcome.val = Some(
        try
          client.stream("GET", "https://a.test/", timeout=100, response => {
            response.each_chunk(_ => ())
          })
        catch {
          error => variant(error)
        } noraise {
          _ => "ended"
        },
      )
    })
    clock.advance(99)
    body.queue.put(Some(b"x"))
    clock.advance(99)
    assert_eq(outcome.val, None, msg="each read gets its own 100 ms")
    clock.advance(1)
    assert_eq(outcome.val, Some("Timeout Body 100"))
    assert_eq(body.closed, 1)
    assert_eq(clock.pending(), [])
  })
}

///|
async test "read buffers at most max_body_bytes and closes a larger body" {
  let fits = Fed::new()
  fits.queue.put(Some(b"abc"))
  fits.queue.put(Some(b"d"))
  fits.queue.put(None)
  let read = fed_client(fits, max_body_bytes=Some(4)).stream(
    "GET",
    "https://a.test/",
    response => response.read(),
  )
  assert_eq(read, b"abcd")
  let larger = Fed::new()
  larger.queue.put(Some(b"abc"))
  larger.queue.put(Some(b"de"))
  let outcome = try
    fed_client(larger, max_body_bytes=Some(4)).stream(
      "GET",
      "https://a.test/",
      response => response.read(),
    )
  catch {
    error => variant(error)
  } noraise {
    _ => "read"
  }
  assert_eq(outcome, "Protocol the body is larger than max_body_bytes (4)")
  assert_eq(larger.closed, 1)
  let unbounded = Fed::new()
  unbounded.queue.put(Some(b"abcdef"))
  unbounded.queue.put(None)
  let read = fed_client(unbounded, max_body_bytes=None).stream(
    "GET",
    "https://a.test/",
    response => response.read(),
  )
  assert_eq(read, b"abcdef")
}

///|
async test "a buffered response reads as one chunk and keeps its content" {
  let client = fed_client(Fed::new(), buffered=b"whole")
  let response = client.get("https://a.test/")
  assert_eq(response.read_some(), Some(b"whole"))
  assert_eq(response.read_some(), None)
  assert_eq(response.read(), b"whole")
  assert_eq(response.content(), b"whole")
  response.close()
  assert_eq(response.text(), "whole", msg="close leaves a buffered body")
  let empty = @req.Response::new(204, @http.Request::get("https://a.test/"))
  assert_eq(empty.read_some(), None)
}

///|
/// A body stream that yields one chunk, then fails as a reset connection.
struct Reset {
  mut sent : Bool
  mut closed : Int32
}

///|
impl @http.BodyStream for Reset with fn read_some(self) {
  guard !self.sent else {
    raise @http.HttpError::Network(phase=Body, message="reset")
  }
  self.sent = true
  Some(b"a")
}

///|
impl @http.BodyStream for Reset with fn close(self) {
  self.closed += 1
}

///|
struct ResetTransport {
  body : Reset
}

///|
impl @http.Transport for ResetTransport with fn send(_, _) {
  raise @http.HttpError::Protocol("buffered calls are not used here")
}

///|
impl @http.Transport for ResetTransport with fn send_stream(self, _) {
  ({ status: 200, headers: @http.Headers::new(), }, self.body)
}

///|
async test "a connection lost while reading a streamed body raises Network and closes it" {
  let body = Reset::{ sent: false, closed: 0, }
  let client = @req.Client::new(transport=ResetTransport::{ body, })
  let outcome = try {
    let _ : Unit = client.stream("GET", "https://a.test/", response => {
      response.each_chunk(_ => ())
    })
    "ended"
  } catch {
    @req.ReqError::Network(phase~, message~, ..) =>
      "Network \{@debug.to_string(phase)} \{message}"
    error => "unexpected \{error}"
  }
  assert_eq(outcome, "Network Body reset")
  assert_eq(body.closed, 1)
}

///|
async test "a step that raises over a streamed response still closes it" {
  let refused = Fed::new()
  let failing = @req.Client::new(
    transport=FedTransport::{ body: refused, buffered: b"", },
    steps=[
      @req.on_response(response => {
        raise @req.ReqError::Status(request=response.request, response~)
      }),
    ],
  )
  let outcome = try {
    let _ : Unit = failing.stream("GET", "https://a.test/", _ => ())
    "returned"
  } catch {
    @req.ReqError::Status(..) => "Status"
    error => "unexpected \{error}"
  }
  assert_eq(outcome, "Status")
  assert_eq(refused.closed, 1, msg="the hook raised, the stream is closed")
}

///|
async test "json on an unread or consumed stream says so, not that it is malformed" {
  let body = Fed::new()
  body.queue.put(Some(b"{}"))
  body.queue.put(None)
  let (unread, consumed) = fed_client(body).stream("GET", "https://a.test/", response => {
    let unread = try response.json() catch {
      error => variant(error)
    } noraise {
      _ => "json"
    }
    response.each_chunk(_ => ())
    let consumed = try response.json() catch {
      error => variant(error)
    } noraise {
      _ => "json"
    }
    (unread, consumed)
  })
  assert_eq(unread, "ResponseNotRead")
  assert_eq(consumed, "StreamConsumed")
}
