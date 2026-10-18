///|
fn selection(
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
  body_stream? : &@http.BodyStream,
  body_length? : Int64,
) -> String {
  let body = select_body(
    content?,
    text?,
    data?,
    files?,
    json?,
    body_stream?,
    body_length?,
  ) catch {
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
    Stream(_, length) => "stream " + @debug.to_string(length)
  }
}

///|
test "select_body takes at most one body" {
  let conflict = "error: give at most one of content, text, data, files, json and body_stream"
  let stream = @http.StreamBody::new(Chunks::new([])).take()
  let cases : Array[(String, String)] = [
    (selection(body_stream=stream), "stream None"),
    (selection(body_stream=stream, body_length=3L), "stream Some(3)"),
    (selection(body_stream=stream, content=b""), conflict),
    (
      selection(body_length=3L),
      "error: body_length is given without body_stream",
    ),
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
    assert_eq(body.encode(), (content_type, Bytes(bytes)), msg="case \{i}")
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
      (Some(t), @http.Body::Bytes(b))
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

///|
/// A body stream that yields the given chunks, then the end.
priv struct Chunks {
  chunks : Array[Bytes]
  mut next : Int32
}

///|
fn Chunks::new(chunks : Array[Bytes]) -> Chunks {
  { chunks, next: 0, }
}

///|
impl @http.BodyStream for Chunks with fn read_some(self) {
  guard self.next < self.chunks.length() else { return None }
  self.next += 1
  Some(self.chunks[self.next - 1])
}

///|
impl @http.BodyStream for Chunks with fn close(self) {
  self.next = self.chunks.length()
}

///|
test "a stream body is passed on with its length and no Content-Type" {
  let source = Chunks::new([b"ab", b"c"])
  let (content_type, body) = Stream(source, Some(3L)).encode()
  assert_eq(content_type, None)
  assert_eq(body.length(), Some(3L))
  assert_true(body.is_replayable())
  guard body is Stream(stream) else { fail("not a stream") }
  ignore(stream.take())
  assert_false(body.is_replayable())
  let (_, unknown) = Stream(Chunks::new([]), None).encode()
  assert_eq(unknown.length(), None)
}

///|
test "multipart with a stream part is a stream body, without one it is bytes" {
  let file = Part::file_stream(
    "f",
    "f.bin",
    "application/octet-stream",
    Chunks::new([b"xyz"]),
    length=3L,
  )
  let (content_type, streamed) = Multipart([Part::text("a", "1"), file]).encode(random=() => {
      0.5
    },
  )
  guard content_type is Some(content_type) else { fail("no Content-Type") }
  assert_true(content_type.has_prefix("multipart/form-data; boundary="))
  assert_true(streamed is Stream(_))
  assert_true(streamed.length() is Some(_))
  let (_, in_memory) = Multipart([Part::text("a", "1")]).encode()
  assert_true(in_memory is Bytes(_))
}
