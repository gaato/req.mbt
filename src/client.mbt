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
  priv max_body_bytes : Int32?
  priv steps : Array[Step]
  priv follow_redirects : Bool
  priv max_redirects : Int32
  priv jar : CookieJar?
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
/// - `timeout`: milliseconds one exchange may take, 30 s by default: up to
///   the whole response, or for a streamed one up to its head and then each
///   read of its body.
/// - `max_body_bytes`: the largest body buffered, 64 MiB by default, counted
///   after decoding; `None` lifts it. The default transport applies it to
///   each call; `Response::read` applies it to a streamed body.
/// - `steps`: links of the chain around the transport, the first outermost;
///   they see each request before `auth` is applied.
/// - `follow_redirects`: follows 301, 302, 303, 307 and 308 responses, at
///   most `max_redirects` (10) in a row, as gaato/http's `follow_redirects`
///   does: 303, and 301 or 302 after `POST`, turn into `GET` without the
///   body; `Authorization`, `Cookie` and `Proxy-Authorization` are dropped
///   when the origin changes; `https` to `http` is refused. On by default;
///   each call can turn it off or on. On JS, `fetch` follows redirects
///   before the client sees them.
/// - `cookies`: by default the client keeps cookies in a jar of its own on
///   its clock (`Client::cookies`), at most 50 per domain and 3000 in all,
///   applied on every redirect hop. `Jar(jar)` uses `jar` instead, `Off`
///   keeps none.
/// - `transport`: replaces the default `AsyncTransport` of gaato/http-async.
/// - `clock`: measures `timeout` and `elapsed`.
///
/// These configure the default transport and are ignored with `transport`:
///
/// - `connect_timeout`, `write_timeout`, `read_timeout`, `pool_timeout`:
///   milliseconds for making a connection, sending the request, waiting for
///   each read of the response, and waiting for a free connection. Unset,
///   only `timeout` applies.
/// - `max_connections`, `max_connections_per_origin`: open connections in
///   all and to one origin; a call beyond them waits for one to be free.
///   Unset, gaato/http-async's defaults apply.
/// - `max_idle_per_origin`: connections kept open between calls, per origin.
/// - `proxy`: an `http://` or `https://` proxy URL, credentials optional,
///   for every call. Without it, `trust_env` (on by default) reads
///   `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` and `NO_PROXY`.
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
  follow_redirects~ : Bool = true,
  max_redirects~ : Int32 = default_max_redirects,
  cookies? : Cookies,
  transport? : &@http.Transport,
  clock? : &@clock.Clock,
  connect_timeout? : Int32,
  write_timeout? : Int32,
  read_timeout? : Int32,
  pool_timeout? : Int32,
  max_connections? : Int32,
  max_connections_per_origin? : Int32,
  max_idle_per_origin? : Int32,
  proxy? : String,
  trust_env~ : Bool = true,
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
        connect_timeout_ms?=connect_timeout,
        write_timeout_ms?=write_timeout,
        read_timeout_ms?=read_timeout,
        pool_timeout_ms?=pool_timeout,
        max_connections?,
        max_connections_per_origin?,
        max_idle_per_origin?,
        max_body_bytes?,
        proxy?,
        trust_env~,
      )
      (transport as &@http.Transport, Some(transport))
    }
  }
  let clock = clock.unwrap_or_else(() => @adapter.AsyncClock::new())
  {
    base_url,
    headers: merge_headers(defaults, headers),
    params: [..params],
    timeout,
    max_body_bytes,
    steps,
    follow_redirects,
    max_redirects,
    jar: cookie_jar(cookies, clock),
    transport,
    clock,
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
/// The client's cookie jar, or `None` with `cookies=Off`.
///
/// ```mbt check
/// test {
///   let client = @req.Client::new()
///   assert_eq(client.cookies().map(jar => jar.length()), Some(0))
///   client.close()
/// }
/// ```
pub fn Client::cookies(self : Client) -> CookieJar? {
  self.jar
}

///|
/// The client's steps, then the redirect step unless `follow_redirects` is
/// off, then the cookie step: the chain of one call.
fn Client::chain(self : Client, follow_redirects : Bool?) -> Array[Step] {
  let steps = [..self.steps]
  if follow_redirects.unwrap_or(self.follow_redirects) {
    steps.push(redirect_step(self.max_redirects))
  }
  if self.jar is Some(jar) {
    steps.push(cookie_step(jar))
  }
  steps
}

///|
/// Sends a request and returns its response, whatever its status.
///
/// - `params` are added to the URL's query, after the client's; a name given
///   here replaces the client's parameters of that name.
/// - `headers` replace the client's headers of the same names.
/// - At most one body: `content` (bytes, no `Content-Type`), `text`
///   (`text/plain; charset=utf-8`), `data` (a URL-encoded form), `files`
///   (`multipart/form-data`), `json` (compact `application/json`) or
///   `body_stream` (sent as it is read, with `Content-Length` when
///   `body_length` gives it and chunked otherwise). A `Content-Type` in the
///   headers wins over the implied one. A body that streams, including
///   files made with `Part::file_stream`, is sent at most once: retries and
///   redirects that would send it again stop instead.
/// - `timeout` replaces the client's for this call.
/// - `follow_redirects` replaces the client's for this call. The response
///   carries the redirects followed in `history` and the final URL in `url`.
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
  body_stream? : &@http.BodyStream,
  body_length? : Int64,
  timeout? : Int32,
  follow_redirects? : Bool,
) -> Response raise ReqError {
  let request = self.build(
    http_method,
    url,
    params,
    headers,
    select_body(
      content?,
      text?,
      data?,
      files?,
      json?,
      body_stream?,
      body_length?,
    ),
  )
  let timeout = timeout.unwrap_or(self.timeout)
  run_steps(
    self.chain(follow_redirects),
    request => self.exchange(request, timeout, stream=false),
    request,
  )
}

///|
/// Sends a request like `request` and calls `f` with the response while its
/// body is still on the connection, then closes it, whether `f` read it or
/// not. Steps see the response before `f`; every response the call opened,
/// including ones a step dropped or raised over, is closed when it ends.
/// The redirect responses in `history` are closed unread before the next
/// request goes out: they keep their status, headers and URL, not their
/// bodies.
///
/// ```mbt check
/// async test {
///   let client = @req.Client::new(
///     transport=@req.MockTransport::new(_ => {
///       status: 200,
///       headers: @http.Headers::new(),
///       body: b"line one",
///     }),
///   )
///   let size = client.stream("GET", "https://example.com/export", response => {
///     let mut size = 0
///     response.each_chunk(chunk => size += chunk.length())
///     size
///   })
///   assert_eq(size, 8)
/// }
/// ```
pub async fn[T] Client::stream(
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
  body_stream? : &@http.BodyStream,
  body_length? : Int64,
  timeout? : Int32,
  follow_redirects? : Bool,
  f : async (Response) -> T,
) -> T {
  let request = self.build(
    http_method,
    url,
    params,
    headers,
    select_body(
      content?,
      text?,
      data?,
      files?,
      json?,
      body_stream?,
      body_length?,
    ),
  )
  let timeout = timeout.unwrap_or(self.timeout)
  // Every response opened during the call is closed when it ends, so a
  // step that raises after `next`, or drops a response it replaced, cannot
  // leave a connection behind.
  let opened : Array[Response] = []
  defer opened.each(response => response.close())
  let response = run_steps(
    self.chain(follow_redirects),
    request => {
      let response = self.exchange(request, timeout, stream=true)
      opened.push(response)
      response
    },
    request,
  )
  f(response)
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
/// client's clock. A streamed exchange ends at the response head and leaves
/// the body on the connection.
async fn Client::exchange(
  self : Client,
  request : Request,
  timeout : Int32,
  stream~ : Bool,
) -> Response raise ReqError {
  let started = self.clock.now_unix_ms()
  let received = @adapter.with_timeout_opt(self.clock, timeout, () => {
    if stream {
      let (head, body) = self.transport.send_stream(request)
      (head.status, head.headers, Open(body, started=false))
    } else {
      let response = self.transport.send(request)
      (
        response.status,
        response.headers,
        Buffered(response.body, delivered=false),
      )
    }
  }) catch {
    error => raise map_transport_error(error, request)
  }
  guard received is Some((status, headers, state)) else {
    raise Timeout(request~, phase=Unknown, timeout~)
  }
  {
    status,
    headers,
    url: request.url,
    request,
    history: [],
    elapsed: (self.clock.now_unix_ms() - started).to_int(),
    body: { state, max_bytes: self.max_body_bytes, clock: self.clock, timeout, },
  }
}
