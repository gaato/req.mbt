///|
/// A transport that answers every request by calling a function, for tests:
/// the function can check the request, record it, wait on a clock, return
/// any response or raise any transport failure.
///
/// ```mbt check
/// async test {
///   let client = @req.Client::new(
///     transport=@req.MockTransport::new(request => {
///       status: 200,
///       headers: @http.Headers::new(),
///       body: b"hi \{request.url}",
///     }),
///   )
///   let response = client.get("https://example.com/")
///   assert_eq(response.text(), "hi https://example.com/")
/// }
/// ```
pub struct MockTransport {
  priv handler : async (Request) -> @http.Response raise @http.HttpError
}

///|
/// Creates a transport that answers with `handler`.
pub fn MockTransport::new(
  handler : async (Request) -> @http.Response raise @http.HttpError,
) -> MockTransport {
  { handler, }
}

///|
pub extend MockTransport with @http.Transport::{send, send_stream}

///|
/// Answers with the handler's response.
pub impl @http.Transport for MockTransport with fn send(self, request) {
  (self.handler)(request)
}

///|
/// Answers with the handler's response, its body as a single chunk.
pub impl @http.Transport for MockTransport with fn send_stream(self, request) {
  let response = (self.handler)(request)
  (
    { status: response.status, headers: response.headers, },
    OneChunk::{ body: Some(response.body), },
  )
}

///|
/// A body stream that yields one chunk, then the end.
priv struct OneChunk {
  mut body : Bytes?
}

///|
impl @http.BodyStream for OneChunk with fn read_some(self) {
  let body = self.body
  self.body = None
  body
}

///|
impl @http.BodyStream for OneChunk with fn close(self) {
  self.body = None
}
