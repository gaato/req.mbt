///|
/// The statuses retried unless told otherwise: 408, 429, 500, 502, 503 and
/// 504, as Elixir Req's `:safe_transient` and ky do.
let default_retry_statuses : Array[Int32] = [408, 429, 500, 502, 503, 504]

///|
/// The methods retried unless told otherwise: those RFC 9110 §9.2.2 calls
/// idempotent, as urllib3's `Retry.DEFAULT_ALLOWED_METHODS` and ky do.
let default_retry_methods : Array[String] = [
  "GET", "HEAD", "OPTIONS", "PUT", "DELETE", "TRACE",
]

///|
/// When a call is sent again, and how long it waits first.
///
/// A call is sent again, up to `max_retries` times, when its method is one
/// of `methods` and the response's status is one of `statuses` or sending
/// failed with `Timeout` or `Network`; and whatever its method when nothing
/// reached the server (`RequestoError::is_unsent`; a proxy refusal only with one
/// of `statuses`). A body that streams is never sent twice. The wait is a
/// `Retry-After` the response gives, in seconds or as an HTTP date on the
/// client's clock, unless it asks for more than `max_retry_after`, in which
/// case the response is returned as it is; otherwise it is drawn between 0
/// and `base_delay * 2 ^ retry`, capped at `max_delay` ("full jitter").
///
/// ```mbt check
/// test {
///   let client = @requesto.Client::new(retry=@requesto.Retry::new(max_retries=5))
///   client.close()
///   let client = @requesto.Client::new(retry=@requesto.Retry::none())
///   client.close()
/// }
/// ```
pub struct Retry {
  priv max_retries : Int32
  priv statuses : Array[Int32]
  priv methods : Array[String]
  priv max_retry_after : Int32
  priv base_delay : Int32
  priv max_delay : Int32
}

///|
/// A retry policy; the defaults are those of `Client::new`.
///
/// - `max_retries`: sends after the first, 3 by default.
/// - `statuses`: response statuses worth another try, by default 408, 429,
///   500, 502, 503 and 504.
/// - `methods`: methods sent again after such a status or a `Timeout` or
///   `Network` failure, by default GET, HEAD, OPTIONS, PUT, DELETE and TRACE.
/// - `max_retry_after`: the longest `Retry-After` honoured, in milliseconds,
///   60 s by default; a server asking for more gets no retry.
/// - `base_delay`, `max_delay`: milliseconds of the backoff, 1 s and 30 s by
///   default.
pub fn Retry::new(
  max_retries~ : Int32 = 3,
  statuses~ : Array[Int32] = default_retry_statuses,
  methods~ : Array[String] = default_retry_methods,
  max_retry_after~ : Int32 = 60_000,
  base_delay~ : Int32 = 1000,
  max_delay~ : Int32 = 30_000,
) -> Retry {
  {
    max_retries: max_retries.max(0),
    statuses: [..statuses],
    methods: methods.map(String::to_upper),
    max_retry_after: max_retry_after.max(0),
    base_delay: base_delay.max(0),
    max_delay: max_delay.max(0),
  }
}

///|
/// A policy that never sends a call again.
pub fn Retry::none() -> Retry {
  Retry::new(max_retries=0)
}

///|
/// The wait in milliseconds before sending `request` again, after `outcome`
/// was the result of retry number `retries` (0 for the first send), or
/// `None` to keep the outcome. `now_ms` reads an HTTP-date `Retry-After`;
/// `random`, in `[0, 1)`, draws the backoff.
fn Retry::delay_ms(
  self : Retry,
  request : Request,
  outcome : Result[Response, RequestoError],
  retries : Int32,
  now_ms : Int64,
  random : Double,
) -> Int32? {
  guard retries < self.max_retries && request.body.is_replayable() else {
    return None
  }
  guard self.retryable(request, outcome) else { return None }
  let server = match outcome {
    Ok(response) =>
      response.headers
      .get("retry-after")
      .bind(value => @http.parse_retry_after(value, now_unix_ms=now_ms))
    Err(_) => None
  }
  match server {
    Some(ms) if ms > self.max_retry_after => None
    Some(ms) => Some(ms)
    None => Some(full_jitter(self.base_delay, self.max_delay, retries, random))
  }
}

///|
/// Whether `outcome` is worth sending `request` again, leaving aside the
/// count and the body.
fn Retry::retryable(
  self : Retry,
  request : Request,
  outcome : Result[Response, RequestoError],
) -> Bool {
  let idempotent = self.methods.contains(request.http_method.to_upper())
  match outcome {
    Ok(response) => idempotent && self.statuses.contains(response.status)
    // A proxy that refuses with 403 or 407 refuses again; 502 and 504 may
    // pass.
    Err(Proxy(status~, ..)) => self.statuses.contains(status)
    Err(error) if error.is_unsent() => true
    Err(Timeout(..) | Network(..)) => idempotent
    Err(_) => false
  }
}

///|
/// A wait drawn uniformly between 0 and `base * 2 ^ retries`, capped at
/// `max` (AWS's "full jitter"). `random` is clamped into `[0, 1)`.
fn full_jitter(
  base : Int32,
  max : Int32,
  retries : Int32,
  random : Double,
) -> Int32 {
  let cap = max.to_double()
  let mut ceiling = base.to_double().min(cap)
  for _ in 0..<retries {
    guard ceiling < cap else { break }
    ceiling = (ceiling * 2.0).min(cap)
  }
  let random = if random >= 0.0 { random.min(0.9999999999999999) } else { 0.0 }
  (ceiling * random).to_int()
}

///|
/// The step that sends a request again as `retry` says, waiting on `clock`,
/// but never past `deadline`: a wait that would end at or after it is not
/// waited for. Each send gets its own copy of the headers, so later steps
/// start from the same request every time; a response that is not kept is
/// closed. The response returned counts the retries in `retries`.
fn retry_step(
  retry : Retry,
  clock : &@clock.Clock,
  random : () -> Double,
  deadline : Int64?,
) -> Step {
  (request, next) => {
    for retries = 0 {
      let sent = { ..request, headers: copy_headers(request.headers), }
      let outcome : Result[Response, RequestoError] = try next(sent) catch {
        error => Err(error)
      } noraise {
        response => Ok(response)
      }
      let now = clock.now_unix_ms()
      let delay = retry
        .delay_ms(request, outcome, retries, now, random())
        .filter(delay => {
          deadline is None || now + delay.to_int64() < deadline.unwrap()
        })
      guard delay is Some(delay) else {
        match outcome {
          Ok(response) if retries == 0 => return response
          Ok(response) => return { ..response, retries, }
          Err(error) => raise error
        }
      }
      if outcome is Ok(response) {
        response.close()
      }
      clock.sleep(delay)
      continue retries + 1
    }
  }
}
