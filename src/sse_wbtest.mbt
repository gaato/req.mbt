///|
test "is_event_stream reads the media type, whatever its case and parameters" {
  let cases : Array[(String?, Bool)] = [
    (Some("text/event-stream"), true),
    (Some("Text/Event-Stream"), true),
    (Some("text/event-stream; charset=utf-8"), true),
    (Some(" text/event-stream ;charset=utf-8"), true),
    (Some("text/event-stream-x"), false),
    (Some("application/json"), false),
    (Some("text/plain; text/event-stream"), false),
    (Some(""), false),
    (None, false),
  ]
  for case in cases {
    assert_eq(is_event_stream(case.0), case.1, msg=case.0.unwrap_or("-"))
  }
}

///|
test "with_default_header adds a header the call does not name" {
  let cases : Array[(Array[(String, String)], Array[(String, String)])] = [
    ([], [("Accept", "text/event-stream")]),
    ([("X-Key", "1")], [("X-Key", "1"), ("Accept", "text/event-stream")]),
    ([("accept", "*/*")], [("accept", "*/*")]),
    ([("ACCEPT", "a"), ("Accept", "b")], [("ACCEPT", "a"), ("Accept", "b")]),
  ]
  for case in cases {
    assert_eq(
      with_default_header(case.0, "Accept", "text/event-stream"),
      case.1,
    )
  }
}
