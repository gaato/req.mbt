///|
/// The longest line `each_line` holds unless told otherwise: 16 MiB, the
/// same bound gaato/http/sse puts on one event, so one record of either
/// kind is bounded alike.
let default_max_line_bytes : Int32 = 16_777_216

///|
/// Splits a byte stream into lines ended by `\n`, `\r\n` or `\r`, holding
/// at most `max_bytes` of the line being read.
priv struct LineSplitter {
  max_bytes : Int32
  line : Buffer
  /// A `\r` ended the last line, so a `\n` right after it ends nothing.
  mut skip_lf : Bool
  /// A line grew past `max_bytes`; `feed` stopped there.
  mut overflow : Bool
}

///|
fn LineSplitter::new(max_bytes : Int32) -> LineSplitter {
  { max_bytes, line: Buffer(), skip_lf: false, overflow: false, }
}

///|
/// The lines `bytes` completes, without their terminators and decoded as
/// UTF-8 (malformed bytes become U+FFFD). A line that would pass
/// `max_bytes` sets `overflow` and ends the feed, after the lines before it.
fn LineSplitter::feed(self : LineSplitter, bytes : Bytes) -> Array[String] {
  let lines = []
  for byte in bytes {
    if self.skip_lf {
      self.skip_lf = false
      if byte == b'\n' {
        continue
      }
    }
    if byte == b'\r' || byte == b'\n' {
      lines.push(self.take())
      self.skip_lf = byte == b'\r'
    } else if self.line.length() < self.max_bytes {
      self.line.write_byte(byte)
    } else {
      self.overflow = true
      break
    }
  }
  lines
}

///|
/// The last line, when the stream ended without a terminator after it.
fn LineSplitter::finish(self : LineSplitter) -> String? {
  if self.line.length() > 0 {
    Some(self.take())
  } else {
    None
  }
}

///|
fn LineSplitter::take(self : LineSplitter) -> String {
  let line = @utf8.decode_lossy(self.line.to_bytes())
  self.line.reset()
  line
}

///|
/// Calls `f` with each line of the body, in order, until its end: lines end
/// with `\n`, `\r\n` or `\r`, which `f` does not see, and are decoded as
/// UTF-8 (malformed bytes become U+FFFD). A last line without a terminator
/// counts. Calling `close` in `f` stops there.
///
/// A line longer than `max_line_bytes` (16 MiB by default) closes the body
/// and raises `Protocol`, after the lines before it.
///
/// ```mbt check
/// async test {
///   let client = @requesto.Client::new(
///     transport=@requesto.MockTransport::new(_ => {
///       status: 200,
///       headers: @http.Headers::new(),
///       body: b"{\"n\":1}\n{\"n\":2}\n",
///     }),
///   )
///   let lines = []
///   client.stream("GET", "https://example.com/feed.ndjson", response => {
///     response.each_line(line => lines.push(line))
///   })
///   assert_eq(lines, ["{\"n\":1}", "{\"n\":2}"])
/// }
/// ```
pub async fn Response::each_line(
  self : Response,
  f : async (String) -> Unit,
  max_line_bytes~ : Int32 = default_max_line_bytes,
) -> Unit {
  let splitter = LineSplitter::new(max_line_bytes)
  self.each_slice(slice => {
    for line in splitter.feed(slice) {
      f(line)
      if self.is_closed() {
        return
      }
    }
    if splitter.overflow {
      self.close()
      raise Protocol(
        request=self.request,
        message="a line is longer than max_line_bytes (\{max_line_bytes})",
      )
    }
  })
  if !self.is_closed() && splitter.finish() is Some(line) {
    f(line)
  }
}
