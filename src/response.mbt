///|
/// A request as the transport receives it: `@http.Request`.
pub type Request = @http.Request

///|
/// The phase of an exchange a transport failure happened in: `@http.Phase`.
pub type Phase = @http.Phase

///|
/// A received response. Every status is an ordinary response; call
/// `raise_for_status` to turn the ones outside 200 through 299 into an error.
///
/// A response from `Client::stream` holds its body unread: `read` buffers
/// it, `read_some` and `each_chunk` take it chunk by chunk, `each_line` and
/// `each_event` line by line and event by event, and `close` drops the
/// rest. Any other call's response arrives read.
pub struct Response {
  /// The status code.
  status : Int32
  /// The response headers.
  headers : @http.Headers
  /// The URL the response came from.
  url : String
  /// The request that produced the response, as the transport received it.
  request : Request
  /// The redirect responses followed on the way here, oldest first.
  history : Array[Response]
  /// Milliseconds from handing the request to the transport to having the
  /// whole response, or its head for a streamed response, measured on the
  /// client's clock.
  elapsed : Int32
  priv body : ResponseBody
}

///|
/// Where a response's body is.
priv enum BodyState {
  /// In memory; `delivered` once `read_some` has handed it out.
  Buffered(Bytes, delivered~ : Bool)
  /// Still on the connection; `started` once a chunk has been taken.
  Open(&@http.BodyStream, started~ : Bool)
  /// Read to its end chunk by chunk.
  Ended
  /// Closed before its end.
  Closed
}

///|
/// A response body and the limits for reading it.
priv struct ResponseBody {
  mut state : BodyState
  /// Set by `close`, whatever the state, to stop the `each_*` loops.
  mut closed : Bool
  /// The most bytes `read` buffers.
  max_bytes : Int32?
  /// Bounds each read from the connection.
  clock : &@clock.Clock
  /// Milliseconds each read from the connection may take.
  timeout : Int32
}

///|
/// A response for a step or a test to return, its body already read.
///
/// ```mbt check
/// test {
///   let request = @http.Request::get("https://example.com/")
///   let response = @req.Response::new(200, request, content=b"cached")
///   assert_eq(response.text(), "cached")
///   assert_eq(response.url, "https://example.com/")
/// }
/// ```
pub fn Response::new(
  status : Int32,
  request : Request,
  headers? : @http.Headers,
  content~ : Bytes = b"",
  url? : String,
  history~ : Array[Response] = [],
  elapsed~ : Int32 = 0,
) -> Response {
  {
    status,
    headers: headers.unwrap_or_else(() => @http.Headers::new()),
    url: url.unwrap_or(request.url),
    request,
    history,
    elapsed,
    body: buffered_body(content),
  }
}

///|
/// A body already in memory.
fn buffered_body(content : Bytes) -> ResponseBody {
  {
    state: Buffered(content, delivered=false),
    closed: false,
    max_bytes: None,
    clock: @adapter.AsyncClock::new(),
    timeout: 0,
  }
}

///|
/// The whole body. A streamed response's body has to be read first.
pub fn Response::content(self : Response) -> Bytes raise ReqError {
  match self.body.state {
    Buffered(content, ..) => content
    Open(_, started=false) => raise ResponseNotRead(request=self.request)
    Open(_, started=true) | Ended | Closed =>
      raise StreamConsumed(request=self.request)
  }
}

///|
/// The body decoded as UTF-8; malformed bytes become U+FFFD.
pub fn Response::text(self : Response) -> String raise ReqError {
  @utf8.decode_lossy(self.content())
}

///|
/// The body parsed as JSON.
pub fn Response::json(self : Response) -> Json raise ReqError {
  let content = self.content()
  let text = @utf8.decode(content) catch {
    _ => raise Decoding(message="the body is not valid UTF-8")
  }
  @json.parse(text) catch {
    error => raise Decoding(message=error.to_string())
  }
}

///|
/// The body parsed as JSON and converted to `T`, which the call site names
/// by its expected type: `let user : User = response.json_as()`.
pub fn[T : @json.FromJson] Response::json_as(
  self : Response,
) -> T raise ReqError {
  let json = self.json()
  @json.from_json(json) catch {
    error => raise Decoding(message=error.to_string())
  }
}

///|
/// Reads the rest of a streamed body into memory, up to the client's
/// `max_body_bytes`, and returns it; `content`, `text` and `json` work
/// afterwards. A body already read is returned as it is. A body larger than
/// the bound is closed and raises `Protocol`.
pub async fn Response::read(self : Response) -> Bytes raise ReqError {
  match self.body.state {
    Buffered(content, ..) => content
    Open(stream, started=false) => {
      let buffer = Buffer()
      while self.next_chunk(stream) is Some(chunk) {
        if self.body.max_bytes is Some(max) &&
          buffer.length() + chunk.length() > max {
          self.close()
          raise Protocol(
            request=self.request,
            message="the body is larger than max_body_bytes (\{max})",
          )
        }
        buffer.write_bytes(chunk)
      }
      let content = buffer.to_bytes()
      self.body.state = Buffered(content, delivered=false)
      content
    }
    Open(_, started=true) | Ended | Closed =>
      raise StreamConsumed(request=self.request)
  }
}

///|
/// The next chunk of the body, or `None` at its end. A body in memory comes
/// as one chunk. Each read from the connection is bounded by the call's
/// `timeout`. After `close`, raises `StreamConsumed`.
pub async fn Response::read_some(self : Response) -> Bytes? raise ReqError {
  match self.body.state {
    Buffered(content, delivered~) => {
      guard !delivered && content.length() > 0 else { return None }
      self.body.state = Buffered(content, delivered=true)
      Some(content)
    }
    Open(stream, ..) => {
      self.body.state = Open(stream, started=true)
      self.next_chunk(stream)
    }
    Ended => None
    Closed => raise StreamConsumed(request=self.request)
  }
}

///|
/// Calls `f` with each chunk of the body, in order, until its end. Calling
/// `close` in `f` stops there.
pub async fn Response::each_chunk(
  self : Response,
  f : async (Bytes) -> Unit,
) -> Unit {
  while self.read_some() is Some(chunk) {
    f(chunk)
    if self.is_closed() {
      return
    }
  }
}

///|
/// The most bytes of one read handed to a parser at once, so the events or
/// lines it returns together are bounded by a slice, not by a read: a body
/// in memory arrives as one read of any size.
let slice_bytes : Int32 = 65_536

///|
/// Calls `f` with the body in slices of at most `slice_bytes`, in order,
/// until its end or until `f` closes the response.
async fn Response::each_slice(
  self : Response,
  f : async (Bytes) -> Unit,
) -> Unit {
  while self.read_some() is Some(chunk) {
    for start = 0; start < chunk.length(); start = start + slice_bytes {
      let slice = if start == 0 && chunk.length() <= slice_bytes {
        chunk
      } else {
        chunk[start:(start + slice_bytes).min(chunk.length())].to_owned()
      }
      f(slice)
      if self.is_closed() {
        return
      }
    }
  }
}

///|
/// Whether `close` was called, which ends the `each_*` loops.
fn Response::is_closed(self : Response) -> Bool {
  self.body.closed
}

///|
/// Drops the rest of a streamed body and releases its connection, and ends
/// any `each_*` loop it is called from. A body in memory, or one read to
/// its end, stays readable.
pub fn Response::close(self : Response) -> Unit {
  self.body.closed = true
  if self.body.state is Open(stream, ..) {
    self.body.state = Closed
    stream.close()
  }
}

///|
/// One read from the connection within the timeout; the end of the body
/// closes the stream.
async fn Response::next_chunk(
  self : Response,
  stream : &@http.BodyStream,
) -> Bytes? raise ReqError {
  let body = self.body
  let chunk = @adapter.with_timeout_opt(body.clock, body.timeout, () => {
    stream.read_some()
  }) catch {
    error => {
      self.close()
      raise map_transport_error(error, self.request)
    }
  }
  match chunk {
    None => {
      self.close()
      raise Timeout(request=self.request, phase=Body, timeout=body.timeout)
    }
    Some(None) => {
      body.state = Ended
      stream.close()
      None
    }
    Some(Some(chunk)) => Some(chunk)
  }
}

///|
/// Whether the status is in 100 through 199.
pub fn Response::is_informational(self : Response) -> Bool {
  self.status >= 100 && self.status <= 199
}

///|
/// Whether the status is in 200 through 299.
pub fn Response::is_success(self : Response) -> Bool {
  self.status >= 200 && self.status <= 299
}

///|
/// Whether the status is in 300 through 399.
pub fn Response::is_redirect(self : Response) -> Bool {
  self.status >= 300 && self.status <= 399
}

///|
/// Whether the status is in 400 through 499.
pub fn Response::is_client_error(self : Response) -> Bool {
  self.status >= 400 && self.status <= 499
}

///|
/// Whether the status is in 500 through 599.
pub fn Response::is_server_error(self : Response) -> Bool {
  self.status >= 500 && self.status <= 599
}

///|
/// Whether the status is in 400 through 599.
pub fn Response::is_error(self : Response) -> Bool {
  self.status >= 400 && self.status <= 599
}

///|
/// The response itself when its status is in 200 through 299, otherwise a
/// `Status` error carrying it, informational and redirect statuses included.
pub fn Response::raise_for_status(self : Response) -> Response raise ReqError {
  guard self.is_success() else {
    raise Status(request=self.request, response=self)
  }
  self
}
