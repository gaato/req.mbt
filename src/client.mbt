///|
/// The `User-Agent` a client sends unless told otherwise.
let user_agent : String = "gaato-req/0.1.0"

///|
/// How long one exchange may take, in milliseconds, unless told otherwise.
let default_timeout : Int32 = 30_000

///|
/// The largest buffered body the default transport accepts, unless told
/// otherwise: 64 MiB, counted after decompression.
let default_max_body_bytes : Int32 = 67_108_864

///|
/// The default transport's own deadline. The client applies `timeout` on its
/// clock, so the transport's only has to stay out of the way of any timeout
/// a call asks for.
let transport_ceiling_ms : Int32 = 2_147_483_647

///|
/// Defaults shared by the calls made through it, and the transport and clock
/// they use. Call `close` when done, to drop the default transport's idle
/// connections.
pub struct Client {
  priv base_url : String?
  priv headers : @http.Headers
  priv params : Array[(String, String)]
  priv timeout : Int32
  priv steps : Array[Step]
  priv transport : &@http.Transport
  priv clock : &@clock.Clock
  priv owned : @adapter.AsyncTransport?
}

///|
/// Creates a client.
///
/// - `base_url`: prefixed to relative URLs; a call's URL is appended to it
///   with one `/`, so `"/users"` and `"users"` both land under its path.
/// - `headers`: sent with every call, after `User-Agent: gaato-req/<version>`,
///   which a `User-Agent` here replaces.
/// - `params`: query parameters added to every call.
/// - `auth`: sets `Authorization` on calls that do not set it themselves.
/// - `timeout`: milliseconds one exchange may take, 30 s by default.
/// - `max_body_bytes`: the largest buffered body the default transport
///   accepts, 64 MiB by default; `None` lifts it. Ignored with `transport`.
/// - `steps`: links of the chain around the transport, the first outermost;
///   they see each request before `auth` is applied.
/// - `transport`: replaces the default `AsyncTransport` of gaato/http-async.
/// - `clock`: measures `timeout` and `elapsed`.
///
/// ```mbt check
/// test {
///   let client = @req.Client::new(
///     base_url="https://api.example.com/v1",
///     headers=[("Accept", "application/json")],
///     auth=Bearer("token"),
///   )
///   client.close()
/// }
/// ```
pub fn Client::new(
  base_url? : String,
  headers~ : Array[(String, String)] = [],
  params~ : Array[(String, String)] = [],
  auth? : Auth,
  timeout~ : Int32 = default_timeout,
  max_body_bytes~ : Int32? = Some(default_max_body_bytes),
  steps~ : Array[Step] = [],
  transport? : &@http.Transport,
  clock? : &@clock.Clock,
) -> Client {
  let defaults = @http.Headers::from_array([("user-agent", user_agent)])
  let steps = match auth {
    Some(auth) => [..steps, auth_step(auth)]
    None => [..steps]
  }
  let (transport, owned) = match transport {
    Some(transport) => (transport, None)
    None => {
      let transport = @adapter.AsyncTransport::new(
        timeout_ms=transport_ceiling_ms,
        max_body_bytes?,
      )
      (transport as &@http.Transport, Some(transport))
    }
  }
  {
    base_url,
    headers: merge_headers(defaults, headers),
    params: [..params],
    timeout,
    steps,
    transport,
    clock: clock.unwrap_or_else(() => @adapter.AsyncClock::new()),
    owned,
  }
}

///|
/// Drops the default transport's idle connections. A transport passed to
/// `Client::new` is left to its owner.
pub fn Client::close(self : Client) -> Unit {
  if self.owned is Some(transport) {
    transport.close()
  }
}

///|
/// Sends a request and returns its response, whatever its status.
///
/// - `params` are added to the URL's query, after the client's; a name given
///   here replaces the client's parameters of that name.
/// - `headers` replace the client's headers of the same names.
/// - At most one body: `content` (bytes, no `Content-Type`), `text`
///   (`text/plain; charset=utf-8`), `data` (a URL-encoded form), `files`
///   (`multipart/form-data`) or `json` (compact `application/json`). A
///   `Content-Type` in the headers wins over the implied one.
/// - `timeout` replaces the client's for this call.
pub async fn Client::request(
  self : Client,
  http_method : String,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
  timeout? : Int32,
) -> Response raise ReqError {
  let request = self.build(
    http_method,
    url,
    params,
    headers,
    select_body(content?, text?, data?, files?, json?),
  )
  let timeout = timeout.unwrap_or(self.timeout)
  run_steps(self.steps, request => self.exchange(request, timeout), request)
}

///|
/// The request a call describes, before the steps.
fn Client::build(
  self : Client,
  http_method : String,
  url : String,
  params : Array[(String, String)],
  headers : Array[(String, String)],
  body : Body,
  random? : () -> Double,
) -> Request raise ReqError {
  check_method(http_method)
  let url = join_url(self.base_url, url)
  check_url(url)
  let url = merge_query(url, merge_params(self.params, params))
  let headers = merge_headers(self.headers, headers)
  let (content_type, body) = body.encode(random?)
  if content_type is Some(value) && !headers.contains("content-type") {
    headers.set("content-type", value)
  }
  { http_method: http_method.to_upper(), url, headers, body, }
}

///|
/// Raises unless `http_method` is an HTTP token.
fn check_method(http_method : String) -> Unit raise ReqError {
  let token = !http_method.is_empty() &&
    http_method
    .iter()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      "!#$%&'*+-.^_`|~".contains_char(c)
    })
  if !token {
    raise InvalidRequest(message="invalid method: \{http_method}")
  }
}

///|
/// The last link: one exchange with the transport, within `timeout` on the
/// client's clock.
async fn Client::exchange(
  self : Client,
  request : Request,
  timeout : Int32,
) -> Response raise ReqError {
  let started = self.clock.now_unix_ms()
  let response = @adapter.with_timeout_opt(self.clock, timeout, () => {
    self.transport.send(request)
  }) catch {
    error => raise map_transport_error(error, request)
  }
  guard response is Some(response) else { raise Timeout(request~, timeout~) }
  {
    status: response.status,
    headers: response.headers,
    content: response.body,
    url: request.url,
    request,
    elapsed: (self.clock.now_unix_ms() - started).to_int(),
  }
}
