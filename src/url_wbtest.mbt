///|
test "join_url appends to the base URL unless the URL is absolute" {
  let cases : Array[(String?, String, String)] = [
    (None, "https://a.test/x", "https://a.test/x"),
    (None, "users", "users"),
    (Some("https://a.test/v1"), "users", "https://a.test/v1/users"),
    (Some("https://a.test/v1/"), "/users", "https://a.test/v1/users"),
    (Some("https://a.test/v1//"), "//users/42", "https://a.test/v1/users/42"),
    (Some("https://a.test/v1"), "", "https://a.test/v1"),
    (Some("https://a.test/v1/"), "/", "https://a.test/v1"),
    (Some("https://a.test/v1"), "?page=2", "https://a.test/v1?page=2"),
    (Some("https://a.test/v1"), "http://b.test/y", "http://b.test/y"),
    (Some("https://a.test/v1"), "ftp://b.test/y", "ftp://b.test/y"),
    (Some("https://a.test"), "users:42", "https://a.test/users:42"),
  ]
  for case in cases {
    let (base, url, expected) = case
    assert_eq(
      join_url(base, url),
      expected,
      msg="\{base.unwrap_or("-")} + \{url}",
    )
  }
}

///|
test "scheme_length accepts RFC 3986 schemes before ://" {
  let cases : Array[(String, Int32?)] = [
    ("https://a.test", Some(5)),
    ("HTTP://a.test", Some(4)),
    ("svn+ssh://a.test", Some(7)),
    ("a1.-+://x", Some(5)),
    ("://a.test", None),
    ("1http://a.test", None),
    ("ht tp://a.test", None),
    ("users/http://a.test", None),
    ("users", None),
    ("mailto:a@b.test", None),
  ]
  for case in cases {
    assert_eq(scheme_length(case.0), case.1, msg=case.0)
  }
}

///|
test "merge_params lets the call's names replace the client's" {
  let cases : Array[
    (Array[(String, String)], Array[(String, String)], Array[(String, String)]),
  ] = [
    ([], [], []),
    ([("a", "1")], [], [("a", "1")]),
    ([], [("a", "1")], [("a", "1")]),
    ([("a", "1"), ("b", "2")], [("b", "3")], [("a", "1"), ("b", "3")]),
    (
      [("a", "1"), ("a", "2"), ("c", "0")],
      [("a", "9"), ("a", "8")],
      [("c", "0"), ("a", "9"), ("a", "8")],
    ),
  ]
  for case in cases {
    assert_eq(merge_params(case.0, case.1), case.2)
  }
}

///|
test "merge_query adds parameters after the existing query and drops the fragment" {
  let cases : Array[(String, Array[(String, String)], String)] = [
    ("https://a.test/x", [], "https://a.test/x"),
    ("https://a.test/x", [("q", "1")], "https://a.test/x?q=1"),
    ("https://a.test/x?a=1", [("q", "1")], "https://a.test/x?a=1&q=1"),
    ("https://a.test/x?a=1", [("a", "2")], "https://a.test/x?a=1&a=2"),
    ("https://a.test/x?", [("q", "1")], "https://a.test/x?q=1"),
    ("https://a.test/x?a=1&", [("q", "1")], "https://a.test/x?a=1&q=1"),
    ("https://a.test/x#top", [], "https://a.test/x"),
    ("https://a.test/x?a=1#top", [("q", "1")], "https://a.test/x?a=1&q=1"),
    (
      "https://a.test/x",
      [("a b", "c&d=e"), ("é", "/?#")],
      "https://a.test/x?a%20b=c%26d%3De&%C3%A9=%2F%3F%23",
    ),
    ("https://a.test/x", [("q", "1"), ("r", "")], "https://a.test/x?q=1&r="),
  ]
  for case in cases {
    assert_eq(merge_query(case.0, case.1), case.2, msg=case.0)
  }
}

///|
test "check_url accepts absolute HTTP URLs with a host" {
  let cases : Array[(String, String)] = [
    ("https://a.test", "ok"),
    ("HTTP://a.test:8080/x?y#z", "ok"),
    ("http://a.test?x", "ok"),
    ("http://[::1]/", "ok"),
    ("ftp://a.test/", "unsupported"),
    ("ws://a.test/", "unsupported"),
    ("users/42", "invalid: not an absolute URL"),
    ("", "invalid: not an absolute URL"),
    ("http:/a.test", "invalid: not an absolute URL"),
    ("https://", "invalid: no host"),
    ("https:///x", "invalid: no host"),
    ("https://?q", "invalid: no host"),
    ("https://#f", "invalid: no host"),
    ("https://a.test/a b", "invalid: contains a space or control character"),
    ("https://a.test/\n", "invalid: contains a space or control character"),
    ("https://a.test/\u{7f}", "invalid: contains a space or control character"),
  ]
  for case in cases {
    let (url, expected) = case
    let actual = try check_url(url) catch {
      UnsupportedProtocol(url=u) => {
        assert_eq(u, url)
        "unsupported"
      }
      InvalidURL(url=u, message~) => {
        assert_eq(u, url)
        "invalid: \{message}"
      }
      error => "unexpected \{error}"
    } noraise {
      _ => "ok"
    }
    assert_eq(actual, expected, msg=url)
  }
}

///|
test "merge_headers replaces every value of a name the overrides use" {
  let base = @http.Headers::from_array([
    ("User-Agent", "a"),
    ("Accept", "x"),
    ("Accept", "y"),
    ("X-Keep", "1"),
  ])
  let cases : Array[(Array[(String, String)], Array[(String, String)])] = [
    (
      [],
      [("user-agent", "a"), ("accept", "x"), ("accept", "y"), ("x-keep", "1")],
    ),
    ([("ACCEPT", "z")], [("user-agent", "a"), ("x-keep", "1"), ("accept", "z")]),
    (
      [("X-New", "1"), ("x-new", "2"), ("User-Agent", "b")],
      [
        ("accept", "x"),
        ("accept", "y"),
        ("x-keep", "1"),
        ("x-new", "1"),
        ("x-new", "2"),
        ("user-agent", "b"),
      ],
    ),
  ]
  for case in cases {
    let merged = merge_headers(base, case.0)
    assert_eq(merged.iter().collect(), case.1)
  }
  assert_eq(base.length(), 4, msg="the base is not changed")
}
