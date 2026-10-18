///|
/// Why a call failed. Transport failures carry the request being sent;
/// `Status` carries the response that `raise_for_status` refused.
pub(all) suberror ReqError {
  /// A time limit of `timeout` milliseconds ran out during `phase`: one of
  /// the transport's per-phase limits, or `Unknown` for the call's
  /// `timeout`, which spans the phases.
  Timeout(request~ : Request, phase~ : Phase, timeout~ : Int32)
  /// The connection could not be made (`Dial`) or failed after it was made,
  /// in `phase`.
  Network(request~ : Request, phase~ : Phase, message~ : String)
  /// The peer broke HTTP, or the response passed a limit such as
  /// `max_body_bytes`.
  Protocol(request~ : Request, message~ : String)
  /// The proxy refused to open a tunnel with `status`: 407 when it wants
  /// credentials, 403 when it refuses the destination, 502 or 504 when it
  /// could not reach it. Nothing reached the origin.
  Proxy(request~ : Request, status~ : Int32, message~ : String)
  /// More than `max` redirects in a row; `request` is the last one sent,
  /// whose response was the redirect past `max`.
  TooManyRedirects(request~ : Request, max~ : Int32)
  /// A redirect that is not followed: a `Location` that is not a usable
  /// URL, an `https` to `http` downgrade, or a stream body that cannot be
  /// sent again.
  InvalidRedirect(request~ : Request, location~ : String, message~ : String)
  /// The body of a streamed response was asked for before `read` read it.
  ResponseNotRead(request~ : Request)
  /// The body of a streamed response was read without `read`, or closed,
  /// so it is gone.
  StreamConsumed(request~ : Request)
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
    Timeout(request=r, phase~, timeout~) =>
      @debug.Repr::ctor("Timeout", [
        (Some("request"), request(r)),
        (Some("phase"), @debug.Repr::Repr(phase)),
        (Some("timeout"), @debug.Repr::Repr(timeout)),
      ])
    Network(request=r, phase~, message~) =>
      @debug.Repr::ctor("Network", [
        (Some("request"), request(r)),
        (Some("phase"), @debug.Repr::Repr(phase)),
        (Some("message"), string(message)),
      ])
    Protocol(request=r, message~) =>
      @debug.Repr::ctor("Protocol", [
        (Some("request"), request(r)),
        (Some("message"), string(message)),
      ])
    Proxy(request=r, status~, message~) =>
      @debug.Repr::ctor("Proxy", [
        (Some("request"), request(r)),
        (Some("status"), @debug.Repr::Repr(status)),
        (Some("message"), string(message)),
      ])
    TooManyRedirects(request=r, max~) =>
      @debug.Repr::ctor("TooManyRedirects", [
        (Some("request"), request(r)),
        (Some("max"), @debug.Repr::Repr(max)),
      ])
    InvalidRedirect(request=r, location~, message~) =>
      @debug.Repr::ctor("InvalidRedirect", [
        (Some("request"), request(r)),
        (Some("location"), string(location)),
        (Some("message"), string(message)),
      ])
    ResponseNotRead(request=r) =>
      @debug.Repr::ctor("ResponseNotRead", [(Some("request"), request(r))])
    StreamConsumed(request=r) =>
      @debug.Repr::ctor("StreamConsumed", [(Some("request"), request(r))])
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
    Timeout(request~, phase~, timeout~) =>
      "\{target(request)}: timed out after \{timeout} ms\{phase_suffix(phase)}"
    Network(request~, phase~, message~) =>
      "\{target(request)}: network error\{phase_suffix(phase)}: \{message}"
    Protocol(request~, message~) =>
      "\{target(request)}: protocol error: \{message}"
    Proxy(request~, status~, message~) =>
      "\{target(request)}: the proxy refused the tunnel with \{status}: \{message}"
    TooManyRedirects(request~, max~) =>
      "\{target(request)}: more than \{max} redirects"
    InvalidRedirect(request~, location~, message~) =>
      "\{target(request)}: redirect to \{location} not followed: \{message}"
    ResponseNotRead(request~) =>
      "\{target(request)}: the streamed body has not been read"
    StreamConsumed(request~) =>
      "\{target(request)}: the streamed body was consumed or closed"
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
/// Whether a time limit ran out.
pub fn ReqError::is_timeout(self : ReqError) -> Bool {
  self is Timeout(..)
}

///|
/// Whether sending failed below HTTP: `Timeout`, `Network`, `Protocol`,
/// `Proxy` or `UnsupportedProtocol`.
pub fn ReqError::is_transport_error(self : ReqError) -> Bool {
  match self {
    Timeout(..)
    | Network(..)
    | Protocol(..)
    | Proxy(..)
    | UnsupportedProtocol(..) => true
    TooManyRedirects(..)
    | InvalidRedirect(..)
    | ResponseNotRead(..)
    | StreamConsumed(..)
    | InvalidURL(..)
    | InvalidRequest(..)
    | Decoding(..)
    | Status(..) => false
  }
}

///|
/// Whether the request certainly never reached the server, so sending it
/// again cannot repeat its effect: the transport failed while waiting for a
/// connection or making one, or the proxy refused the tunnel. A request
/// refused before the transport, such as `InvalidURL`, is not counted: it
/// would fail the same way again.
pub fn ReqError::is_unsent(self : ReqError) -> Bool {
  match self {
    Timeout(phase~, ..) | Network(phase~, ..) => phase is (Pool | Dial)
    Proxy(..) => true
    _ => false
  }
}

///|
/// Maps a failure of the transport for `request`. The transport raises
/// only `@http.HttpError`; anything else is reported as `Protocol`.
fn map_transport_error(error : Error, request : Request) -> ReqError {
  match error {
    @http.HttpError::Connect(message) => Network(request~, phase=Dial, message~)
    @http.HttpError::Timeout(phase~, ms~) =>
      Timeout(request~, phase~, timeout=ms)
    @http.HttpError::Network(phase~, message~) =>
      Network(request~, phase~, message~)
    @http.HttpError::Protocol(message) => Protocol(request~, message~)
    @http.HttpError::Proxy(status~, message~) =>
      Proxy(request~, status~, message~)
    error => Protocol(request~, message=error.to_string())
  }
}

///|
/// How a message names the phase it failed in; nothing for `Unknown`.
fn phase_suffix(phase : Phase) -> String {
  match phase {
    Pool => " waiting for a connection"
    Dial => " connecting"
    Write => " sending the request"
    Head => " waiting for the response"
    Body => " reading the body"
    Unknown => ""
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
