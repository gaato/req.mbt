///|
/// A mock transport that records each request and answers from `table`:
/// the status and headers given for the request's URL, its body naming the
/// URL, and 200 for any other URL. It takes a stream body, as a transport
/// sending it does.
fn routes(
  sent : Array[@req.Request],
  table : Array[(String, Int32, Array[(String, String)])],
) -> @req.MockTransport {
  @req.MockTransport::new(request => {
    sent.push(request)
    if request.body is Stream(body) {
      body.take().close()
    }
    let body = @utf8.encode("from \{request.url}")
    for route in table {
      if route.0 == request.url {
        return {
          status: route.1,
          headers: @http.Headers::from_array(route.2),
          body,
        }
      }
    }
    { status: 200, headers: @http.Headers::new(), body, }
  })
}

///|
/// A transport where `/k` redirects to `/k+1` until `/length`, which
/// answers 200.
fn chain_of(sent : Array[@req.Request], length : Int32) -> @req.MockTransport {
  let table = []
  for k in 0..<length {
    table.push(("https://a.test/\{k}", 302, [("Location", "/\{k + 1}")]))
  }
  routes(sent, table)
}

///|
/// The status of a call's response, or the variant it raised with the URL
/// of the request it names.
async fn redirect_outcome(
  call : async () -> @req.Response raise @req.ReqError,
) -> String {
  try call() catch {
    TooManyRedirects(request~, max~) =>
      "TooManyRedirects \{max} after \{request.url}"
    InvalidRedirect(request~, location~, message~) =>
      "InvalidRedirect \{request.url} -> \{location}: \{message}"
    Network(request~, message~, ..) => "Network \{request.url}: \{message}"
    error => "unexpected \{error}"
  } noraise {
    response => "status \{response.status} at \{response.url}"
  }
}

///|
async test "a redirect chain is followed; history holds the redirects, oldest first" {
  let sent = []
  let client = @req.Client::new(
    transport=routes(sent, [
      ("https://a.test/1", 302, [("Location", "/2?x=1#frag")]),
      ("https://a.test/2?x=1", 301, [("Location", "https://b.test/3")]),
    ]),
  )
  let response = client.get("https://a.test/1")
  assert_eq(response.status, 200)
  assert_eq(response.url, "https://b.test/3")
  assert_eq(response.request.url, "https://b.test/3")
  assert_eq(response.text(), "from https://b.test/3")
  assert_eq(sent.map(request => request.url), [
    "https://a.test/1", "https://a.test/2?x=1", "https://b.test/3",
  ])
  assert_eq(response.history.map(hop => (hop.status, hop.url, hop.text())), [
    (302, "https://a.test/1", "from https://a.test/1"),
    (301, "https://a.test/2?x=1", "from https://a.test/2?x=1"),
  ])
  assert_true(response.history.iter().all(hop => hop.history.is_empty()))
}

///|
async test "follow_redirects is set per client and replaced per call" {
  let sent = []
  let table = [("https://a.test/old", 308, [("Location", "/new")])]
  let off = @req.Client::new(
    follow_redirects=false,
    transport=routes(sent, table),
  )
  let on = @req.Client::new(transport=routes(sent, table))
  let cases : Array[(async () -> @req.Response raise @req.ReqError, String)] = [
    (() => off.get("https://a.test/old"), "status 308 at https://a.test/old"),
    (
      () => off.get("https://a.test/old", follow_redirects=true),
      "status 200 at https://a.test/new",
    ),
    (() => on.get("https://a.test/old"), "status 200 at https://a.test/new"),
    (
      () => on.get("https://a.test/old", follow_redirects=false),
      "status 308 at https://a.test/old",
    ),
    (
      () => on.request("GET", "https://a.test/old", follow_redirects=false),
      "status 308 at https://a.test/old",
    ),
  ]
  for i, case in cases {
    assert_eq(redirect_outcome(case.0), case.1, msg="case \{i}")
  }
}

///|
async test "303 turns POST into GET without the body; 307 keeps both" {
  let sent = []
  let client = @req.Client::new(
    transport=routes(sent, [
      ("https://a.test/form", 303, [("Location", "/done")]),
      ("https://a.test/keep", 307, [("Location", "/kept")]),
    ]),
  )
  let _ = client.post("https://a.test/form", json={ "a": 1 })
  let after_303 = sent[1]
  assert_eq(after_303.http_method, "GET")
  assert_eq(after_303.body, Bytes(b""))
  assert_eq(after_303.headers.get("content-type"), None)
  let _ = client.post("https://a.test/keep", text="hi")
  let after_307 = sent[3]
  assert_eq(after_307.http_method, "POST")
  assert_eq(after_307.url, "https://a.test/kept")
  assert_eq(after_307.body, Bytes(b"hi"))
  assert_eq(
    after_307.headers.get("content-type"),
    Some("text/plain; charset=utf-8"),
  )
}

///|
async test "credentials are dropped when the origin changes, auth's included" {
  let sent = []
  let client = @req.Client::new(
    auth=Bearer("t"),
    headers=[("Cookie", "mine=1"), ("Proxy-Authorization", "Basic eA==")],
    transport=routes(sent, [
      ("https://a.test/1", 302, [("Location", "/2")]),
      ("https://a.test/2", 302, [("Location", "https://b.test/3")]),
      ("https://b.test/3", 302, [("Location", "https://a.test/4")]),
    ]),
  )
  let _ = client.get("https://a.test/1")
  let credentials = (request : @req.Request) => {
    [
      request.headers.get("authorization"),
      request.headers.get("cookie"),
      request.headers.get("proxy-authorization"),
    ]
  }
  let kept = [Some("Bearer t"), Some("mine=1"), Some("Basic eA==")]
  let dropped = [None, None, None]
  assert_eq(sent.map(credentials), [kept, kept, dropped, dropped])
}

///|
async test "refused redirects raise InvalidRedirect and close the response" {
  let sent = []
  let client = @req.Client::new(
    transport=routes(sent, [
      ("https://a.test/down", 302, [("Location", "http://a.test/plain")]),
      ("https://a.test/ftp", 301, [("Location", "ftp://a.test/file")]),
    ]),
  )
  let cases : Array[(String, String)] = [
    (
      "https://a.test/down", "InvalidRedirect https://a.test/down -> http://a.test/plain: https to http downgrade",
    ),
    (
      "https://a.test/ftp", "InvalidRedirect https://a.test/ftp -> ftp://a.test/file: not an http or https URL",
    ),
  ]
  for case in cases {
    assert_eq(redirect_outcome(() => client.get(case.0)), case.1)
  }
  assert_eq(sent.length(), 2, msg="nothing is sent after a refused redirect")
}

///|
async test "more than max_redirects raises TooManyRedirects; 10 by default" {
  let cases : Array[(Int32?, Int32, String)] = [
    (Some(2), 2, "status 200 at https://a.test/2"),
    (Some(2), 3, "TooManyRedirects 2 after https://a.test/2"),
    (Some(0), 1, "TooManyRedirects 0 after https://a.test/0"),
    (None, 10, "status 200 at https://a.test/10"),
    (None, 11, "TooManyRedirects 10 after https://a.test/10"),
  ]
  for case in cases {
    let sent = []
    let client = @req.Client::new(
      max_redirects?=case.0,
      transport=chain_of(sent, case.1),
    )
    let outcome = redirect_outcome(() => client.get("https://a.test/0"))
    assert_eq(outcome, case.2)
    let followed = case.0.unwrap_or(10).min(case.1)
    assert_eq(sent.length(), followed + 1, msg=case.2)
  }
  let sent = []
  let client = @req.Client::new(transport=chain_of(sent, 10))
  assert_eq(client.get("https://a.test/0").history.length(), 10)
}

///|
/// A request body stream of one chunk.
struct Upload {
  mut chunk : Bytes?
}

///|
impl @http.BodyStream for Upload with fn read_some(self) {
  let chunk = self.chunk
  self.chunk = None
  chunk
}

///|
impl @http.BodyStream for Upload with fn close(self) {
  self.chunk = None
}

///|
async test "a stream body is not sent again on 307, and dropped on 303" {
  let sent = []
  let client = @req.Client::new(
    transport=routes(sent, [
      ("https://a.test/307", 307, [("Location", "/next")]),
      ("https://a.test/303", 303, [("Location", "/next")]),
    ]),
  )
  let outcome = redirect_outcome(() => {
    client.put("https://a.test/307", body_stream=Upload::{ chunk: Some(b"x"), })
  })
  assert_eq(
    outcome, "InvalidRedirect https://a.test/307 -> https://a.test/next: the stream request body was already sent",
  )
  let outcome = redirect_outcome(() => {
    client.put("https://a.test/303", body_stream=Upload::{ chunk: Some(b"x"), })
  })
  assert_eq(outcome, "status 200 at https://a.test/next")
  assert_eq(sent.last().unwrap().http_method, "GET")
}

///|
async test "a failure on a later hop is raised as it is" {
  let client = @req.Client::new(
    retry=@req.Retry::none(),
    transport=@req.MockTransport::new(request => {
      guard request.url == "https://a.test/1" else {
        raise @http.HttpError::Connect("refused")
      }
      {
        status: 302,
        headers: @http.Headers::from_array([("Location", "/2")]),
        body: b"",
      }
    }),
  )
  assert_eq(
    redirect_outcome(() => client.get("https://a.test/1")),
    "Network https://a.test/2: refused",
  )
}

///|
async test "the client's steps see the first request and the final response" {
  let sent = []
  let seen = []
  let client = @req.Client::new(
    steps=[
      @req.on_request(request => seen.push(request.url)),
      @req.on_response(response => seen.push(response.url)),
    ],
    transport=routes(sent, [("https://a.test/1", 302, [("Location", "/2")])]),
  )
  let _ = client.get("https://a.test/1")
  assert_eq(seen, ["https://a.test/1", "https://a.test/2"])
  assert_eq(sent.length(), 2)
}

///|
/// A response body that counts how often it was closed.
struct Hop {
  mut body : Bytes?
  mut closed : Int32
}

///|
impl @http.BodyStream for Hop with fn read_some(self) {
  let body = self.body
  self.body = None
  body
}

///|
impl @http.BodyStream for Hop with fn close(self) {
  self.closed += 1
}

///|
/// A transport that streams `table`'s answers like `routes`, keeps each body
/// it hands out, and records how many were still open as each request came.
struct HopTransport {
  table : Array[(String, Int32, Array[(String, String)])]
  bodies : Array[Hop]
  open_at_send : Array[Int32]
}

///|
impl @http.Transport for HopTransport with fn send(_, _) {
  raise @http.HttpError::Protocol("only streamed")
}

///|
impl @http.Transport for HopTransport with fn send_stream(self, request) {
  self.open_at_send.push(
    self.bodies.iter().filter(hop => hop.closed == 0).count(),
  )
  let hop = { body: Some(@utf8.encode("from \{request.url}")), closed: 0, }
  self.bodies.push(hop)
  for route in self.table {
    if route.0 == request.url {
      return (
        { status: route.1, headers: @http.Headers::from_array(route.2), },
        hop,
      )
    }
  }
  ({ status: 200, headers: @http.Headers::new(), }, hop)
}

///|
async test "a streamed call closes each redirect response before the next hop" {
  let transport = HopTransport::{
    table: [
      ("https://a.test/1", 302, [("Location", "/2")]),
      ("https://a.test/2", 307, [("Location", "/3")]),
    ],
    bodies: [],
    open_at_send: [],
  }
  let client = @req.Client::new(transport~)
  let (text, history) = client.stream("GET", "https://a.test/1", response => {
    let history = response.history.map(hop => {
      let body = try hop.content() catch {
        StreamConsumed(..) => "closed"
        error => "unexpected \{error}"
      } noraise {
        _ => "readable"
      }
      (hop.status, hop.url, body)
    })
    (response.read() |> @utf8.decode_lossy, history)
  })
  assert_eq(text, "from https://a.test/3")
  assert_eq(history, [
    (302, "https://a.test/1", "closed"),
    (307, "https://a.test/2", "closed"),
  ])
  assert_eq(transport.open_at_send, [0, 0, 0])
  assert_eq(transport.bodies.map(hop => hop.closed > 0), [true, true, true])
}

///|
async test "a streamed call closes the redirect it refuses" {
  let transport = HopTransport::{
    table: [
      ("https://a.test/1", 302, [("Location", "/2")]),
      ("https://a.test/2", 302, [("Location", "http://a.test/3")]),
    ],
    bodies: [],
    open_at_send: [],
  }
  let client = @req.Client::new(transport~, max_redirects=5)
  let outcome = try {
    client.stream("GET", "https://a.test/1", response => response.status)
    |> ignore
    "returned"
  } catch {
    @req.ReqError::InvalidRedirect(location~, ..) => location
    error => "unexpected \{error}"
  }
  assert_eq(outcome, "http://a.test/3")
  assert_eq(transport.open_at_send, [0, 0])
  assert_eq(transport.bodies.map(hop => hop.closed), [1, 1])
}
