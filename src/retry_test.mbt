///|
/// One scripted answer of a transport.
enum Answer {
  Status(Int32, Array[(String, String)])
  Fail(@http.HttpError)
}

///|
/// A transport that records each request and gives `answers` in turn, the
/// last one again once they run out. Like a real transport, it takes a
/// stream body when it answers, and not when it fails to connect.
fn scripted(
  sent : Array[@req.Request],
  answers : Array[Answer],
) -> @req.MockTransport {
  @req.MockTransport::new(request => {
    sent.push(request)
    match answers[(sent.length() - 1).min(answers.length() - 1)] {
      Status(status, headers) => {
        if request.body is Stream(body) {
          ignore(body.take())
        }
        { status, headers: @http.Headers::from_array(headers), body: b"", }
      }
      Fail(error) => raise error
    }
  })
}

///|
/// Runs `call` in the background; the result lands in the returned cell as
/// the status, or the error's message.
fn run_bg(
  group : @async.TaskGroup[Unit],
  call : async () -> @req.Response raise @req.ReqError,
) -> Ref[String?] {
  let outcome = Ref(None)
  group.spawn_bg(() => {
    outcome.val = Some(
      try call() catch {
        error => error.to_string()
      } noraise {
        response => "status \{response.status}"
      },
    )
  })
  outcome
}

///|
async test "a GET is sent again after 503, after a backoff on the client's clock" {
  let clock = @simclock.VirtualClock()
  let sent = []
  let client = @req.Client::new(
    transport=scripted(sent, [Status(503, []), Status(503, []), Status(200, [])]),
    clock~,
    random=() => 0.5,
  )
  @async.with_task_group(group => {
    let outcome = run_bg(group, () => client.get("https://a.test/"))
    clock.settle()
    assert_eq(sent.length(), 1)
    clock.advance(499)
    assert_eq(sent.length(), 1, msg="half of 1 s, drawn with 0.5")
    clock.advance(1)
    assert_eq(sent.length(), 2)
    clock.advance(999)
    assert_eq(sent.length(), 2, msg="half of 2 s")
    clock.advance(1)
    assert_eq(outcome.val, Some("status 200"))
    assert_eq(sent.length(), 3)
    assert_eq(clock.pending(), [])
  })
}

///|
async test "Retry-After is honoured in seconds and as an HTTP date on the client's clock" {
  // Sun, 06 Nov 1994 08:49:37 GMT
  let clock = @simclock.VirtualClock(start_ms=784_111_777_000L)
  let sent = []
  let client = @req.Client::new(
    transport=scripted(sent, [
      Status(429, [("Retry-After", "2")]),
      Status(503, [("Retry-After", "Sun, 06 Nov 1994 08:49:42 GMT")]),
      Status(200, []),
    ]),
    clock~,
    random=() => 0.5,
  )
  @async.with_task_group(group => {
    let outcome = run_bg(group, () => client.get("https://a.test/"))
    clock.advance(1999)
    assert_eq(sent.length(), 1)
    clock.advance(1)
    assert_eq(sent.length(), 2, msg="2 s")
    clock.advance(2999)
    assert_eq(sent.length(), 2)
    clock.advance(1)
    assert_eq(outcome.val, Some("status 200"), msg="until 08:49:42")
  })
}

///|
async test "a Retry-After beyond max_retry_after keeps the response" {
  let clock = @simclock.VirtualClock()
  let sent = []
  let client = @req.Client::new(
    transport=scripted(sent, [Status(503, [("Retry-After", "120")])]),
    clock~,
  )
  let response = client.get("https://a.test/")
  assert_eq(response.status, 503)
  assert_eq(sent.length(), 1)
  assert_eq(clock.pending(), [])
  @async.with_task_group(group => {
    let outcome = run_bg(group, () => {
      client.get(
        "https://a.test/",
        retry=@req.Retry::new(max_retries=1, max_retry_after=120_000),
      )
    })
    clock.advance(119_999)
    assert_eq(sent.length(), 2)
    clock.advance(1)
    assert_eq(outcome.val, Some("status 503"))
    assert_eq(sent.length(), 3)
  })
}

///|
async test "after max_retries the last response or failure is kept" {
  let clock = @simclock.VirtualClock()
  let cases : Array[(Answer, String)] = [
    (Status(500, []), "status 500"),
    (
      Fail(Timeout(phase=Head, ms=10)),
      "GET https://a.test/: timed out after 10 ms waiting for the response",
    ),
  ]
  for case in cases {
    let sent = []
    let client = @req.Client::new(transport=scripted(sent, [case.0]), clock~, random=() => {
      0.5
    })
    @async.with_task_group(group => {
      let outcome = run_bg(group, () => client.get("https://a.test/"))
      clock.advance(500 + 1000 + 2000)
      assert_eq(outcome.val, Some(case.1))
      assert_eq(sent.length(), 4, msg="the first send and 3 retries")
    })
  }
}

///|
async test "other methods are sent again only when nothing reached the server" {
  let clock = @simclock.VirtualClock()
  let cases : Array[(Array[Answer], String, Int32)] = [
    ([Status(503, [])], "status 503", 1),
    (
      [Fail(Network(phase=Write, message="reset"))],
      "POST https://a.test/: network error sending the request: reset",
      1,
    ),
    ([Fail(Connect("refused")), Status(201, [])], "status 201", 2),
    ([Fail(Timeout(phase=Pool, ms=5)), Status(201, [])], "status 201", 2),
  ]
  for case in cases {
    let sent = []
    let client = @req.Client::new(transport=scripted(sent, case.0), clock~, random=() => {
      0.0
    })
    @async.with_task_group(group => {
      let outcome = run_bg(group, () => {
        client.post("https://a.test/", json={ "a": 1 })
      })
      clock.advance(0)
      assert_eq(outcome.val, Some(case.1))
      assert_eq(sent.length(), case.2)
      for request in sent {
        assert_eq(request.body, Bytes(b"{\"a\":1}"), msg="the same body")
      }
    })
  }
}

///|
/// A body stream with nothing in it.
struct Empty {}

///|
impl @http.BodyStream for Empty with fn read_some(_) {
  None
}

///|
impl @http.BodyStream for Empty with fn close(_) {
  ()
}

///|
async test "a body that streams is sent once, and again only if never read" {
  let clock = @simclock.VirtualClock()
  let sent = []
  let client = @req.Client::new(
    transport=scripted(sent, [Status(503, [])]),
    clock~,
  )
  let response = client.put("https://a.test/", body_stream=Empty::{ })
  assert_eq(response.status, 503)
  assert_eq(sent.length(), 1)
  let sent = []
  let client = @req.Client::new(
    transport=scripted(sent, [Fail(Connect("refused")), Status(200, [])]),
    clock~,
    random=() => 0.0,
  )
  @async.with_task_group(group => {
    let outcome = run_bg(group, () => {
      client.post("https://a.test/", body_stream=Empty::{ })
    })
    clock.advance(0)
    assert_eq(outcome.val, Some("status 200"))
    assert_eq(sent.length(), 2)
  })
}

///|
/// A streamed body that records how many times it was closed.
struct Counted {
  mut closed : Int32
}

///|
impl @http.BodyStream for Counted with fn read_some(_) {
  None
}

///|
impl @http.BodyStream for Counted with fn close(self) {
  self.closed += 1
}

///|
/// A transport whose streamed responses have `statuses` in turn.
struct Statuses {
  statuses : Array[Int32]
  bodies : Array[Counted]
}

///|
impl @http.Transport for Statuses with fn send(_, _) {
  raise @http.HttpError::Protocol("buffered calls are not used here")
}

///|
impl @http.Transport for Statuses with fn send_stream(self, _) {
  let body = Counted::{ closed: 0, }
  self.bodies.push(body)
  let status = self.statuses[self.bodies.length() - 1]
  ({ status, headers: @http.Headers::new(), }, body)
}

///|
async test "a streamed response that is retried is closed first" {
  let clock = @simclock.VirtualClock()
  let transport = Statuses::{ statuses: [502, 200], bodies: [], }
  let client = @req.Client::new(transport~, clock~, random=() => 0.0)
  @async.with_task_group(group => {
    let seen = Ref([])
    group.spawn_bg(() => {
      client.stream("GET", "https://a.test/", response => {
        seen.val = [
          response.status,
          transport.bodies[0].closed,
          transport.bodies[1].closed,
        ]
      })
    })
    clock.advance(0)
    assert_eq(seen.val, [200, 1, 0])
  })
  assert_eq(transport.bodies[1].closed, 1, msg="closed when the call ends")
}

///|
async test "retry is set per client and replaced per call" {
  let clock = @simclock.VirtualClock()
  let sent = []
  let client = @req.Client::new(
    transport=scripted(sent, [Status(503, [])]),
    clock~,
    retry=@req.Retry::none(),
    random=() => 0.0,
  )
  assert_eq(client.get("https://a.test/").status, 503)
  assert_eq(sent.length(), 1)
  @async.with_task_group(group => {
    let outcome = run_bg(group, () => {
      client.get("https://a.test/", retry=@req.Retry::new(max_retries=1))
    })
    clock.advance(0)
    assert_eq(outcome.val, Some("status 503"))
    assert_eq(sent.length(), 3)
  })
}

///|
async test "steps run once per call, and auth again for each retry" {
  let clock = @simclock.VirtualClock()
  let sent = []
  let calls = Ref(0)
  let client = @req.Client::new(
    transport=scripted(sent, [Status(503, []), Status(200, [])]),
    clock~,
    auth=Bearer("t"),
    steps=[@req.on_request(_ => calls.val += 1)],
    random=() => 0.0,
  )
  @async.with_task_group(group => {
    let outcome = run_bg(group, () => client.get("https://a.test/"))
    clock.advance(0)
    assert_eq(outcome.val, Some("status 200"))
  })
  assert_eq(calls.val, 1)
  assert_eq(sent.map(r => r.headers.get_all("authorization")), [
    ["Bearer t"],
    ["Bearer t"],
  ])
}
