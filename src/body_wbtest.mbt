///|
fn selection(
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
) -> String {
  let body = select_body(content?, text?, data?, files?, json?) catch {
    InvalidRequest(message~) => return "error: \{message}"
    error => return "unexpected \{error}"
  }
  match body {
    Empty => "empty"
    Content(_) => "content"
    Text(_) => "text"
    Form(_) => "form"
    Multipart(_) => "multipart"
    JsonValue(_) => "json"
  }
}

///|
test "select_body takes at most one body" {
  let conflict = "error: give at most one of content, text, data, files and json"
  let cases : Array[(String, String)] = [
    (selection(), "empty"),
    (selection(content=b"x"), "content"),
    (selection(text="x"), "text"),
    (selection(data=[]), "form"),
    (selection(files=[]), "multipart"),
    (selection(json=Json::null()), "json"),
    (selection(content=b"x", text="x"), conflict),
    (selection(data=[], files=[]), conflict),
    (selection(text="x", json=Json::null()), conflict),
    (
      selection(content=b"", text="", data=[], files=[], json=Json::null()),
      conflict,
    ),
  ]
  for i, case in cases {
    assert_eq(case.0, case.1, msg="case \{i}")
  }
}

///|
test "each body kind implies its Content-Type" {
  let cases : Array[(Body, String?, Bytes)] = [
    (Empty, None, b""),
    (Content(b"\x00\xff"), None, b"\x00\xff"),
    (Text("héllo"), Some("text/plain; charset=utf-8"), b"h\xc3\xa9llo"),
    (Form([]), Some("application/x-www-form-urlencoded"), b""),
    (
      Form([("a b", "c&d"), ("e", "é")]),
      Some("application/x-www-form-urlencoded"),
      b"a%20b=c%26d&e=%C3%A9",
    ),
    (
      JsonValue({ "a": [1, true, Json::null()], "b": "é" }),
      Some("application/json"),
      b"{\"a\":[1,true,null],\"b\":\"\xc3\xa9\"}",
    ),
  ]
  for i, case in cases {
    let (body, content_type, bytes) = case
    assert_eq(body.encode(), (content_type, bytes), msg="case \{i}")
  }
}

///|
test "multipart bodies use a fresh boundary and report encoding failures" {
  let parts = [
    Part::text("a", "1"),
    Part::file("f", "f.txt", "text/plain", b"x"),
  ]
  let (content_type, body) = Multipart(parts).encode(random=() => 0.5)
  guard content_type is Some(content_type) else { fail("no Content-Type") }
  let boundary = content_type["multipart/form-data; boundary=".length():].to_owned()
  assert_eq(
    (Some(content_type), body),
    {
      let (t, b) = @multipart.encode(parts, boundary)
      (Some(t), b)
    },
  )
  let invalid = try
    Multipart([Part::file("f", "f.txt", "text/plain\r\n", b"x")]).encode()
  catch {
    InvalidRequest(message~) => message
    error => "unexpected \{error}"
  } noraise {
    _ => "encoded"
  }
  assert_eq(invalid, "multipart: a part's content type contains CR or LF")
  let colliding = [Part::text("a", "\r\n--" + boundary)]
  let collision = try Multipart(colliding).encode(random=() => 0.5) catch {
    InvalidRequest(message~) => message
    error => "unexpected \{error}"
  } noraise {
    _ => "encoded"
  }
  assert_eq(collision, "multipart: every boundary drawn occurs in a part")
}
