///|
/// Credentials sent in the `Authorization` header. A call that sets that
/// header itself keeps its own.
#non_exhaustive
pub(all) enum Auth {
  /// HTTP Basic: `username:password`, UTF-8 and base64-encoded.
  Basic(username~ : String, password~ : String)
  /// `Bearer <token>`.
  Bearer(String)
  /// HTTP Digest (RFC 7616, and RFC 2617's challenges without qop): a 401
  /// with a `Digest` challenge from the request's origin is answered once
  /// (twice if the first answer's nonce was stale) by sending the request
  /// again, when its body can be; the nonce is reused, with a counted `nc`,
  /// for that origin's later calls. MD5, SHA-256 and their `-sess` forms,
  /// qop `auth`, and `auth-int` for a body in memory.
  Digest(username~ : String, password~ : String)
}

///|
/// Debug output redacts the password and the token.
pub extend Auth with @debug.Debug::{to_repr}

///|
pub impl @debug.Debug for Auth with fn to_repr(self) {
  let redacted = @debug.Repr::literal("<redacted>")
  match self {
    Basic(username~, ..) =>
      @debug.Repr::ctor("Basic", [
        (Some("username"), @debug.Repr::Repr(username)),
        (Some("password"), redacted),
      ])
    Bearer(_) => @debug.Repr::ctor("Bearer", [(None, redacted)])
    Digest(username~, ..) =>
      @debug.Repr::ctor("Digest", [
        (Some("username"), @debug.Repr::Repr(username)),
        (Some("password"), redacted),
      ])
  }
}

///|
/// The step that authorizes requests that do not set `Authorization`
/// themselves. `random` draws Digest's client nonces.
fn auth_step(auth : Auth, random : () -> Double) -> Step {
  match auth {
    Basic(username~, password~) => header_step(basic_value(username, password))
    Bearer(token) => header_step("Bearer " + token)
    Digest(username~, password~) => digest_step(username, password, random)
  }
}

///|
/// The step that sets `Authorization: <value>` on requests without it.
fn header_step(value : String) -> Step {
  (request, next) => {
    guard !request.headers.contains("authorization") else {
      return next(request)
    }
    let headers = copy_headers(request.headers)
    headers.set("authorization", value)
    next({ ..request, headers, })
  }
}

///|
/// The `Authorization` value of HTTP Basic: `username:password`, UTF-8 and
/// base64-encoded.
fn basic_value(username : String, password : String) -> String {
  "Basic " + @base64.encode(@utf8.encode(username + ":" + password))
}

///|
/// `step` for requests to the origin of `url`; requests to any other origin,
/// such as a redirect elsewhere, pass by it.
fn same_origin_only(url : String, step : Step) -> Step {
  let origin = @http.Url::parse(url) catch { _ => return step }
  (request, next) => {
    if same_origin_as(origin, request.url) {
      step(request, next)
    } else {
      next(request)
    }
  }
}
