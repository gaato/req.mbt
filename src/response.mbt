///|
/// A request as the transport receives it: `@http.Request`.
pub type Request = @http.Request

///|
/// A received response. Every status is an ordinary response; call
/// `raise_for_status` to turn the ones outside 200 through 299 into an error.
pub struct Response {
  /// The status code.
  status : Int32
  /// The response headers.
  headers : @http.Headers
  /// The whole body.
  content : Bytes
  /// The URL the response came from.
  url : String
  /// The request that produced the response, as the transport received it.
  request : Request
  /// Milliseconds from handing the request to the transport to having the
  /// whole response, measured on the client's clock.
  elapsed : Int32
}

///|
/// The body decoded as UTF-8; malformed bytes become U+FFFD.
pub fn Response::text(self : Response) -> String {
  @utf8.decode_lossy(self.content)
}

///|
/// The body parsed as JSON.
pub fn Response::json(self : Response) -> Json raise ReqError {
  let text = @utf8.decode(self.content) catch {
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
