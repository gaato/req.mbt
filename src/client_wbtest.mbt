///|
test "defaults: 30 s per exchange, 64 MiB per buffered body, a versioned User-Agent" {
  assert_eq(default_timeout, 30_000)
  assert_eq(default_max_body_bytes, 64 * 1024 * 1024)
  assert_eq(user_agent, "gaato-req/0.1.0")
  let client = Client::new()
  assert_eq(client.timeout, 30_000)
  assert_true(client.owned is Some(_))
  assert_eq(client.headers.get("user-agent"), Some(user_agent))
  client.close()
}

///|
test "check_method accepts HTTP tokens" {
  let cases : Array[(String, Bool)] = [
    ("GET", true),
    ("get", true),
    ("M-SEARCH", true),
    ("X!#$%&'*+.^_`|~9", true),
    ("", false),
    ("GE T", false),
    ("GET\r\n", false),
    ("GÉT", false),
    ("(GET)", false),
  ]
  for case in cases {
    let accepted = try check_method(case.0) catch {
      InvalidRequest(message~) => {
        assert_eq(message, "invalid method: \{case.0}")
        false
      }
      error => fail("unexpected \{error}")
    } noraise {
      _ => true
    }
    assert_eq(accepted, case.1, msg=case.0)
  }
}

///|
test "build: an explicit Content-Type wins over the body's" {
  let transport = MockTransport::new(_ => {
    raise @http.HttpError::Protocol("not sent")
  })
  let client = Client::new(transport~, headers=[("X-Client", "1")])
  let cases : Array[(Array[(String, String)], String?)] = [
    ([], Some("application/json")),
    (
      [("content-type", "application/vnd.api+json")],
      Some("application/vnd.api+json"),
    ),
  ]
  for case in cases {
    let request = client.build(
      "post",
      "https://a.test/x",
      [],
      case.0,
      JsonValue(Json::null()),
    )
    assert_eq(request.http_method, "POST")
    assert_eq(request.headers.get("content-type"), case.1)
    assert_eq(request.headers.get_all("content-type").length(), 1)
    assert_eq(request.body, Bytes(b"null"))
  }
  let client = Client::new(transport~, headers=[("Content-Type", "text/csv")])
  let request = client.build("POST", "https://a.test/x", [], [], Text("a,b"))
  assert_eq(request.headers.get("content-type"), Some("text/csv"))
}

///|
test "Auth header values" {
  let cases : Array[(Auth, String)] = [
    (
      Basic(username="Aladdin", password="open sesame"),
      "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==",
    ),
    (Basic(username="é", password=""), "Basic w6k6"),
    (Bearer("t0k"), "Bearer t0k"),
  ]
  for case in cases {
    assert_eq(case.0.header_value(), case.1)
  }
}

///|
test "Auth debug output redacts secrets" {
  assert_eq(
    @debug.to_string(Basic(username="u", password="p")),
    "Basic(username=\"u\", password=<redacted>)",
  )
  assert_eq(@debug.to_string(Bearer("t")), "Bearer(<redacted>)")
}
