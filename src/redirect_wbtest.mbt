///|
test "defaults: 10 redirects in a row, a jar of 50 cookies per domain and 3000 in all" {
  assert_eq(default_max_redirects, 10)
  assert_eq(default_max_cookies_per_domain, 50)
  assert_eq(default_max_cookies, 3000)
  let client = Client::new()
  assert_true(client.follow_redirects)
  assert_eq(client.max_redirects, 10)
  assert_true(client.jar is Some(_))
  client.close()
}

///|
test "redirect_error maps each refusal to a ReqError naming the last request" {
  let request = @http.Request::get("https://a.test/x")
  let cases : Array[(@http.RedirectError, String)] = [
    (
      Transport(Connect("refused")),
      "GET https://a.test/x: network error connecting: refused",
    ),
    (
      TooManyRedirects(max=3, location="https://a.test/y"),
      "GET https://a.test/x: more than 3 redirects",
    ),
    (
      Downgrade(location="http://a.test/x"),
      "GET https://a.test/x: redirect to http://a.test/x not followed: https to http downgrade",
    ),
    (
      BadLocation(location="ftp://a.test/", reason="not an http or https URL"),
      "GET https://a.test/x: redirect to ftp://a.test/ not followed: not an http or https URL",
    ),
    (
      UnreplayableBody(location="https://a.test/y"),
      "GET https://a.test/x: redirect to https://a.test/y not followed: the stream request body was already sent",
    ),
  ]
  for case in cases {
    let error = redirect_error(case.0, request)
    assert_eq(error.to_string(), case.1)
    guard error
      is (Network(request=r, ..)
      | TooManyRedirects(request=r, ..)
      | InvalidRedirect(request=r, ..)) else {
      fail("unexpected \{error}")
    }
    assert_true(physical_equal(r, request), msg=case.1)
  }
}

///|
test "cookie_jar: the client's own by default, the one given, or none" {
  let clock = @adapter.AsyncClock::new()
  let given = @cookie.CookieJar::new(clock)
  assert_true(
    cookie_jar(None, clock) is Some(jar) && !physical_equal(jar, given),
  )
  assert_true(
    cookie_jar(Some(Jar(given)), clock) is Some(jar) &&
    physical_equal(jar, given),
  )
  assert_true(cookie_jar(Some(Off), clock) is None)
}
