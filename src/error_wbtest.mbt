///|
fn sample_request() -> Request {
  @http.Request::get("https://a.test/x").header(
    "Authorization", "Bearer secret",
  )
}

///|
fn sample_response(status : Int32) -> Response {
  {
    status,
    headers: @http.Headers::new(),
    content: b"body",
    url: "https://a.test/x",
    request: sample_request(),
    elapsed: 0,
  }
}

///|
suberror Odd

///|
test "transport failures map to the error variants" {
  let request = sample_request()
  let cases : Array[(Error, String)] = [
    (@http.HttpError::Connect("refused"), "network refused"),
    (@http.HttpError::Timeout(500), "timeout 500"),
    (@http.HttpError::Protocol("bad head"), "protocol bad head"),
    (Odd, "protocol gaato/req.Odd.Odd"),
  ]
  for case in cases {
    let mapped = match map_transport_error(case.0, request) {
      Network(request=r, message~) if physical_equal(r, request) =>
        "network \{message}"
      Timeout(request=r, timeout~) if physical_equal(r, request) =>
        "timeout \{timeout}"
      Protocol(request=r, message~) if physical_equal(r, request) =>
        "protocol \{message}"
      other => "unexpected \{other}"
    }
    assert_eq(mapped, case.1)
  }
}

///|
test "errors print one line without headers and fall into groups" {
  let request = sample_request()
  let cases : Array[(ReqError, String, Bool, Bool)] = [
    (
      Timeout(request~, timeout=30000),
      "GET https://a.test/x: timed out after 30000 ms",
      true,
      true,
    ),
    (
      Network(request~, message="refused"),
      "GET https://a.test/x: network error: refused",
      false,
      true,
    ),
    (
      Protocol(request~, message="bad"),
      "GET https://a.test/x: protocol error: bad",
      false,
      true,
    ),
    (
      UnsupportedProtocol(url="ftp://a.test"),
      "unsupported protocol in URL: ftp://a.test",
      false,
      true,
    ),
    (
      InvalidURL(url="x", message="not an absolute URL"),
      "invalid URL x: not an absolute URL",
      false,
      false,
    ),
    (InvalidRequest(message="m"), "invalid request: m", false, false),
    (Decoding(message="m"), "cannot decode the response body: m", false, false),
    (
      Status(request~, response=sample_response(404)),
      "client error 404 for GET https://a.test/x",
      false,
      false,
    ),
  ]
  for case in cases {
    let (error, message, timeout, transport) = case
    assert_eq(error.to_string(), message)
    assert_eq(error.is_timeout(), timeout, msg=message)
    assert_eq(error.is_transport_error(), transport, msg=message)
    assert_false(@debug.to_string(error).contains("secret"), msg=message)
  }
}

///|
test "error debug output names the request and the response status" {
  let request = sample_request()
  let cases : Array[(ReqError, String)] = [
    (Timeout(request~, timeout=5), "Timeout"),
    (Network(request~, message="m"), "Network"),
    (Protocol(request~, message="m"), "Protocol"),
    (UnsupportedProtocol(url="ftp://a.test"), "UnsupportedProtocol"),
    (InvalidURL(url="x", message="m"), "InvalidURL"),
    (InvalidRequest(message="m"), "InvalidRequest"),
    (Decoding(message="m"), "Decoding"),
    (Status(request~, response=sample_response(503)), "Status"),
  ]
  for case in cases {
    let repr = @debug.to_string(case.0)
    assert_true(repr.has_prefix(case.1 + "("), msg=repr)
    assert_false(repr.contains("secret"), msg=repr)
  }
  assert_eq(
    @debug.to_string(Status(request~, response=sample_response(503))),
    "Status(request=GET https://a.test/x, status=503)",
  )
}

///|
test "status messages name the status class" {
  let cases : Array[(Int32, String)] = [
    (101, "informational response"),
    (204, "unexpected status"),
    (304, "redirect response"),
    (418, "client error"),
    (503, "server error"),
    (600, "unexpected status"),
  ]
  for case in cases {
    assert_eq(status_class(case.0), case.1)
  }
}
