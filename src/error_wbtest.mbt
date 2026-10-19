///|
fn sample_request() -> Request {
  @http.Request::get("https://a.test/x").header(
    "Authorization", "Bearer secret",
  )
}

///|
fn sample_response(status : Int32) -> Response {
  Response::new(status, sample_request(), content=b"body")
}

///|
suberror Odd

///|
test "transport failures map to the error variants" {
  let request = sample_request()
  let cases : Array[(Error, String)] = [
    (@http.HttpError::Connect("refused"), "network Dial refused"),
    (@http.HttpError::Timeout(phase=Head, ms=500), "timeout Head 500"),
    (
      @http.HttpError::Network(phase=Body, message="reset"),
      "network Body reset",
    ),
    (@http.HttpError::Protocol("bad head"), "protocol bad head"),
    (@http.HttpError::Proxy(status=407, message="auth"), "proxy 407 auth"),
    (Odd, "protocol gaato/requesto.Odd.Odd"),
  ]
  for case in cases {
    let mapped = match map_transport_error(case.0, request) {
      Network(request=r, phase~, message~) if physical_equal(r, request) =>
        "network \{@debug.to_string(phase)} \{message}"
      Timeout(request=r, phase~, timeout~) if physical_equal(r, request) =>
        "timeout \{@debug.to_string(phase)} \{timeout}"
      Protocol(request=r, message~) if physical_equal(r, request) =>
        "protocol \{message}"
      Proxy(request=r, status~, message~) if physical_equal(r, request) =>
        "proxy \{status} \{message}"
      other => "unexpected \{other}"
    }
    assert_eq(mapped, case.1)
  }
}

///|
test "errors print one line without headers and fall into groups" {
  let request = sample_request()
  // (error, message, is_timeout, is_transport_error, is_unsent)
  let cases : Array[(RequestoError, String, Bool, Bool, Bool)] = [
    (
      Timeout(request~, phase=Unknown, timeout=30000),
      "GET https://a.test/x: timed out after 30000 ms",
      true,
      true,
      false,
    ),
    (
      TotalTimeout(request~, timeout=150000),
      "GET https://a.test/x: the call did not finish within 150000 ms",
      true,
      false,
      false,
    ),
    (
      Timeout(request~, phase=Pool, timeout=100),
      "GET https://a.test/x: timed out after 100 ms waiting for a connection",
      true,
      true,
      true,
    ),
    (
      Timeout(request~, phase=Dial, timeout=100),
      "GET https://a.test/x: timed out after 100 ms connecting",
      true,
      true,
      true,
    ),
    (
      Timeout(request~, phase=Head, timeout=100),
      "GET https://a.test/x: timed out after 100 ms waiting for the response",
      true,
      true,
      false,
    ),
    (
      Network(request~, phase=Dial, message="refused"),
      "GET https://a.test/x: network error connecting: refused",
      false,
      true,
      true,
    ),
    (
      Network(request~, phase=Write, message="reset"),
      "GET https://a.test/x: network error sending the request: reset",
      false,
      true,
      false,
    ),
    (
      Network(request~, phase=Body, message="reset"),
      "GET https://a.test/x: network error reading the body: reset",
      false,
      true,
      false,
    ),
    (
      Network(request~, phase=Unknown, message="failed"),
      "GET https://a.test/x: network error: failed",
      false,
      true,
      false,
    ),
    (
      Protocol(request~, message="bad"),
      "GET https://a.test/x: protocol error: bad",
      false,
      true,
      false,
    ),
    (
      Proxy(request~, status=407, message="Proxy Authentication Required"),
      "GET https://a.test/x: the proxy refused the tunnel with 407: Proxy Authentication Required",
      false,
      true,
      true,
    ),
    (
      UnsupportedProtocol(url="ftp://a.test"),
      "unsupported protocol in URL: ftp://a.test",
      false,
      true,
      false,
    ),
    (
      TooManyRedirects(request~, max=10),
      "GET https://a.test/x: more than 10 redirects",
      false,
      false,
      false,
    ),
    (
      InvalidRedirect(
        request~,
        location="http://a.test/",
        message="https to http",
      ),
      "GET https://a.test/x: redirect to http://a.test/ not followed: https to http",
      false,
      false,
      false,
    ),
    (
      ResponseNotRead(request~),
      "GET https://a.test/x: the streamed body has not been read",
      false,
      false,
      false,
    ),
    (
      StreamConsumed(request~),
      "GET https://a.test/x: the streamed body was consumed or closed",
      false,
      false,
      false,
    ),
    (
      InvalidURL(url="x", message="not an absolute URL"),
      "invalid URL x: not an absolute URL",
      false,
      false,
      false,
    ),
    (InvalidRequest(message="m"), "invalid request: m", false, false, false),
    (
      Decoding(message="m"),
      "cannot decode the response body: m",
      false,
      false,
      false,
    ),
    (
      Status(request~, response=sample_response(404)),
      "client error 404 for GET https://a.test/x",
      false,
      false,
      false,
    ),
  ]
  for case in cases {
    let (error, message, timeout, transport, unsent) = case
    assert_eq(error.to_string(), message)
    assert_eq(error.is_timeout(), timeout, msg=message)
    assert_eq(error.is_transport_error(), transport, msg=message)
    assert_eq(error.is_unsent(), unsent, msg=message)
    assert_false(@debug.to_string(error).contains("secret"), msg=message)
  }
}

///|
test "error debug output names the request and the response status" {
  let request = sample_request()
  let cases : Array[(RequestoError, String)] = [
    (Timeout(request~, phase=Head, timeout=5), "Timeout"),
    (TotalTimeout(request~, timeout=5), "TotalTimeout"),
    (Network(request~, phase=Dial, message="m"), "Network"),
    (Protocol(request~, message="m"), "Protocol"),
    (Proxy(request~, status=403, message="m"), "Proxy"),
    (TooManyRedirects(request~, max=1), "TooManyRedirects"),
    (InvalidRedirect(request~, location="l", message="m"), "InvalidRedirect"),
    (ResponseNotRead(request~), "ResponseNotRead"),
    (StreamConsumed(request~), "StreamConsumed"),
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
