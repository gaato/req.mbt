///|
/// The lines a splitter bounded at `max` returns for `chunks`, then its last
/// line, or where it overflowed.
fn split_lines(chunks : Array[Bytes], max~ : Int32 = 64) -> Array[String] {
  let splitter = LineSplitter::new(max)
  let lines = []
  for chunk in chunks {
    lines.append(splitter.feed(chunk))
    if splitter.overflow {
      lines.push("<overflow>")
      return lines
    }
  }
  if splitter.finish() is Some(line) {
    lines.push("<last> " + line)
  }
  lines
}

///|
test "LineSplitter ends lines at LF, CRLF and CR, across chunks" {
  let cases : Array[(Array[Bytes], Array[String])] = [
    ([], []),
    ([b""], []),
    ([b"a\nb\n"], ["a", "b"]),
    ([b"a\r\nb\r\n"], ["a", "b"]),
    ([b"a\rb\r"], ["a", "b"]),
    ([b"a\r", b"\nb\n"], ["a", "b"]),
    ([b"a\r", b"b\n"], ["a", "b"]),
    ([b"a", b"b", b"\n"], ["ab"]),
    ([b"\n\n"], ["", ""]),
    ([b"\r\n\r\n"], ["", ""]),
    ([b"\n\r"], ["", ""]),
    ([b"a\nb"], ["a", "<last> b"]),
    ([b"a\r"], ["a"]),
    ([b"caf\xc3", b"\xa9\n"], ["café"]),
    ([b"\xff\n"], ["\u{fffd}"]),
  ]
  for case in cases {
    assert_eq(split_lines(case.0), case.1, msg=@debug.to_string(case.1))
  }
}

///|
test "LineSplitter holds max_bytes of a line and refuses one more" {
  let cases : Array[(Array[Bytes], Array[String])] = [
    ([b"abc\n"], ["abc"]),
    ([b"abc"], ["<last> abc"]),
    ([b"ab", b"c\r\n"], ["abc"]),
    ([b"abcd\n"], ["<overflow>"]),
    ([b"x\nabcd\ny\n"], ["x", "<overflow>"]),
    ([b"abc", b"d"], ["<overflow>"]),
    ([b"abc\nabc\n"], ["abc", "abc"]),
  ]
  for case in cases {
    assert_eq(split_lines(case.0, max=3), case.1, msg=@debug.to_string(case.1))
  }
  assert_eq(default_max_line_bytes, 16 * 1024 * 1024)
}
