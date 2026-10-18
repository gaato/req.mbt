///|
/// Why a call failed. Transport failures carry the request being sent;
/// `Status` carries the response that `raise_for_status` refused.
pub(all) suberror ReqError {
  /// The exchange did not finish within `timeout` milliseconds.
  Timeout(request~ : Request, timeout~ : Int32)
  /// The connection could not be made or was lost.
  Network(request~ : Request, message~ : String)
  /// The peer broke HTTP, or the response passed a limit such as
  /// `max_body_bytes`.
  Protocol(request~ : Request, message~ : String)
  /// The URL's scheme is not `http` or `https`.
  UnsupportedProtocol(url~ : String)
  /// The URL is not an absolute HTTP URL.
  InvalidURL(url~ : String, message~ : String)
  /// The call's arguments conflict or cannot be encoded.
  InvalidRequest(message~ : String)
  /// A response body is not the JSON, or the type, it was read as.
  Decoding(message~ : String)
  /// The response status is not in 200 through 299.
  Status(request~ : Request, response~ : Response)
}

///|
/// Debug output names the request by method and URL and the response by
/// status, so headers such as `Authorization` never appear in it.
pub extend ReqError with @debug.Debug::{to_repr}

///|
pub impl @debug.Debug for ReqError with fn to_repr(self) {
  let request = (request : Request) => {
    @debug.Repr::literal(request.http_method + " " + request.url)
  }
  let string = (value : String) => @debug.Repr::Repr(value)
  match self {
    Timeout(request=r, timeout~) =>
      @debug.Repr::ctor("Timeout", [
        (Some("request"), request(r)),
        (Some("timeout"), @debug.Repr::Repr(timeout)),
      ])
    Network(request=r, message~) =>
      @debug.Repr::ctor("Network", [
        (Some("request"), request(r)),
        (Some("message"), string(message)),
      ])
    Protocol(request=r, message~) =>
      @debug.Repr::ctor("Protocol", [
        (Some("request"), request(r)),
        (Some("message"), string(message)),
      ])
    UnsupportedProtocol(url~) =>
      @debug.Repr::ctor("UnsupportedProtocol", [(Some("url"), string(url))])
    InvalidURL(url~, message~) =>
      @debug.Repr::ctor("InvalidURL", [
        (Some("url"), string(url)),
        (Some("message"), string(message)),
      ])
    InvalidRequest(message~) =>
      @debug.Repr::ctor("InvalidRequest", [(Some("message"), string(message))])
    Decoding(message~) =>
      @debug.Repr::ctor("Decoding", [(Some("message"), string(message))])
    Status(request=r, response~) =>
      @debug.Repr::ctor("Status", [
        (Some("request"), request(r)),
        (Some("status"), @debug.Repr::Repr(response.status)),
      ])
  }
}

///|
/// The error's one-line message.
pub extend ReqError with Show::{to_string, output}

///|
/// A one-line message naming the request by method and URL, without headers
/// or bodies.
pub impl Show for ReqError with fn output(self, logger) {
  let target = (request : Request) => request.http_method + " " + request.url
  let message = match self {
    Timeout(request~, timeout~) =>
      "\{target(request)}: timed out after \{timeout} ms"
    Network(request~, message~) =>
      "\{target(request)}: network error: \{message}"
    Protocol(request~, message~) =>
      "\{target(request)}: protocol error: \{message}"
    UnsupportedProtocol(url~) => "unsupported protocol in URL: \{url}"
    InvalidURL(url~, message~) => "invalid URL \{url}: \{message}"
    InvalidRequest(message~) => "invalid request: \{message}"
    Decoding(message~) => "cannot decode the response body: \{message}"
    Status(request~, response~) =>
      "\{status_class(response.status)} \{response.status} for \{target(request)}"
  }
  logger.write_string(message)
}

///|
/// Whether the exchange ran out of time.
pub fn ReqError::is_timeout(self : ReqError) -> Bool {
  self is Timeout(..)
}

///|
/// Whether sending failed below HTTP: `Timeout`, `Network`, `Protocol` or
/// `UnsupportedProtocol`.
pub fn ReqError::is_transport_error(self : ReqError) -> Bool {
  match self {
    Timeout(..) | Network(..) | Protocol(..) | UnsupportedProtocol(..) => true
    InvalidURL(..) | InvalidRequest(..) | Decoding(..) | Status(..) => false
  }
}

///|
/// Maps a failure of the transport's `send` for `request`. `send` raises
/// only `@http.HttpError`; anything else is reported as `Protocol`.
fn map_transport_error(error : Error, request : Request) -> ReqError {
  match error {
    @http.HttpError::Connect(message) => Network(request~, message~)
    @http.HttpError::Timeout(timeout) => Timeout(request~, timeout~)
    @http.HttpError::Protocol(message) => Protocol(request~, message~)
    error => Protocol(request~, message=error.to_string())
  }
}

///|
/// How the message of a `Status` error names its status.
fn status_class(status : Int32) -> String {
  match status / 100 {
    1 => "informational response"
    3 => "redirect response"
    4 => "client error"
    5 => "server error"
    _ => "unexpected status"
  }
}
