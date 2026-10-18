///|
/// Credentials sent in the `Authorization` header. A call that sets that
/// header itself keeps its own.
pub(all) enum Auth {
  /// HTTP Basic: `username:password`, UTF-8 and base64-encoded.
  Basic(username~ : String, password~ : String)
  /// `Bearer <token>`.
  Bearer(String)
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
  }
}

///|
/// The `Authorization` header value.
fn Auth::header_value(self : Auth) -> String {
  match self {
    Basic(username~, password~) =>
      "Basic " + @base64.encode(@utf8.encode(username + ":" + password))
    Bearer(token) => "Bearer " + token
  }
}

///|
/// The step that sets `Authorization` on requests that do not have it.
fn auth_step(auth : Auth) -> Step {
  (request, next) => {
    if !request.headers.contains("authorization") {
      request.headers.set("authorization", auth.header_value())
    }
    next(request)
  }
}
