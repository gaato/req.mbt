// Redirects follow gaato/http's `follow_redirects`, the policy of the WHATWG
// Fetch Standard and httpx: this file only carries req's responses and
// errors through it.

///|
/// Redirects a client follows in a row unless told otherwise: Req's limit,
/// the lowest of the clients compared (requests allows 30, axios 21, httpx
/// and Fetch 20).
let default_max_redirects : Int32 = 10

///|
/// The step that follows redirects with gaato/http's `follow_redirects`, at
/// most `max_redirects` in a row, sending every hop through the rest of the
/// chain. The final response carries the redirect responses in `history`,
/// oldest first, each closed: a streamed one keeps its status, headers and
/// URL but not its body. A response the step does not return is closed.
fn redirect_step(max_redirects : Int32) -> Step {
  (request, next) => {
    let history : Array[Response] = []
    // The latest request sent and its response, which the lower layer sees
    // only as a head.
    let mut sent = request
    let mut received : Response? = None
    // A failure of the rest of the chain, carried through the lower layer's
    // `HttpError` unchanged.
    let mut failure : ReqError? = None
    let _ = @http.follow_redirects(
      request,
      request => {
        sent = request
        let response = next(request) catch {
          error => {
            failure = Some(error)
            raise @http.HttpError::Protocol(error.to_string())
          }
        }
        received = Some(response)
        { status: response.status, headers: response.headers, body: b"", }
      },
      max_redirects~,
      on_redirect=_ => {
        if received is Some(response) {
          response.close()
          history.push(response)
        }
      },
    ) catch {
      error => {
        if failure is Some(failure) {
          raise failure
        }
        if received is Some(response) {
          response.close()
        }
        raise redirect_error(error, sent)
      }
    }
    // `follow_redirects` returned, so the last request got a response.
    { ..received.unwrap(), history, }
  }
}

///|
/// The `ReqError` for a redirect refused while following from `request`,
/// the last request sent.
fn redirect_error(error : @http.RedirectError, request : Request) -> ReqError {
  match error {
    Transport(error) => map_transport_error(error, request)
    TooManyRedirects(max~, ..) => TooManyRedirects(request~, max~)
    Downgrade(location~) =>
      InvalidRedirect(request~, location~, message="https to http downgrade")
    BadLocation(location~, reason~) =>
      InvalidRedirect(request~, location~, message=reason)
    UnreplayableBody(location~) =>
      InvalidRedirect(
        request~,
        location~,
        message="the stream request body was already sent",
      )
  }
}
