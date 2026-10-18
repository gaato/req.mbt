///|
async test "a cookie set on a redirect hop is sent on the next hop and kept" {
  let sent = []
  let client = @requesto.Client::new(
    transport=routes(sent, [
      (
        "https://a.test/login",
        302,
        [("Set-Cookie", "sid=1; Path=/"), ("Location", "/home")],
      ),
      ("https://a.test/home", 302, [("Location", "https://b.test/")]),
    ]),
  )
  let _ = client.post("https://a.test/login", data=[("user", "u")])
  let _ = client.get("https://a.test/again")
  assert_eq(sent.map(request => request.headers.get("cookie")), [
    None,
    Some("sid=1"),
    None,
    Some("sid=1"),
  ])
  let jar = client.cookies().unwrap()
  assert_eq(jar.iter().map(cookie => (cookie.name, cookie.domain)).collect(), [
    ("sid", "a.test"),
  ])
}

///|
async test "a Cookie header the call sets wins over the jar" {
  let sent = []
  let client = @requesto.Client::new(
    transport=routes(sent, [
      ("https://a.test/set", 200, [("Set-Cookie", "sid=1")]),
    ]),
  )
  let _ = client.get("https://a.test/set")
  let _ = client.get("https://a.test/", headers=[("Cookie", "mine=2")])
  assert_eq(sent[1].headers.get_all("cookie"), ["mine=2"])
}

///|
async test "cookies=Off keeps none; Jar(jar) shares one between clients" {
  let sent = []
  let table = [("https://a.test/set", 200, [("Set-Cookie", "sid=1")])]
  let off = @requesto.Client::new(cookies=Off, transport=routes(sent, table))
  assert_true(off.cookies() is None)
  let _ = off.get("https://a.test/set")
  let _ = off.get("https://a.test/")
  assert_eq(sent[1].headers.get("cookie"), None)
  let first = @requesto.Client::new(transport=routes(sent, table))
  let jar = first.cookies().unwrap()
  let second = @requesto.Client::new(
    cookies=Jar(jar),
    transport=routes(sent, table),
  )
  let _ = first.get("https://a.test/set")
  let _ = second.get("https://a.test/")
  assert_eq(sent.last().unwrap().headers.get("cookie"), Some("sid=1"))
  assert_true(second.cookies().unwrap() |> physical_equal(jar))
}

///|
async test "the client's jar reads the client's clock" {
  let sent = []
  let clock = @simclock.VirtualClock()
  let client = @requesto.Client::new(
    clock~,
    transport=routes(sent, [
      ("https://a.test/set", 200, [("Set-Cookie", "sid=1; Max-Age=60")]),
    ]),
  )
  let _ = client.get("https://a.test/set")
  clock.advance(59_999)
  let _ = client.get("https://a.test/")
  clock.advance(1)
  let _ = client.get("https://a.test/")
  assert_eq(sent.map(request => request.headers.get("cookie")), [
    None,
    Some("sid=1"),
    None,
  ])
}

///|
async test "the client's jar keeps 50 cookies per domain and 3000 in all" {
  let sent = []
  let many = Array::makei(51, i => ("Set-Cookie", "c\{i}=1"))
  let client = @requesto.Client::new(
    transport=routes(sent, [("https://a.test/", 200, many)]),
  )
  let _ = client.get("https://a.test/")
  let jar = client.cookies().unwrap()
  assert_eq(jar.length(), 50)
  jar.clear()
  let fifty = @http.Headers::from_array(
    Array::makei(50, i => ("Set-Cookie", "c\{i}=1")),
  )
  for domain in 0..<60 {
    jar.store(fifty, "https://d\{domain}.test/")
  }
  assert_eq(jar.length(), 3000)
  jar.store(fifty, "https://d60.test/")
  assert_eq(jar.length(), 3000)
}
