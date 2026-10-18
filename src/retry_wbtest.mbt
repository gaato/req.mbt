///|
test "Retry defaults: 3 retries, transient statuses, idempotent methods, 60 s cap" {
  let retry = Retry::new()
  assert_eq(retry.max_retries, 3)
  assert_eq(retry.statuses, [408, 429, 500, 502, 503, 504])
  assert_eq(retry.methods, ["GET", "HEAD", "OPTIONS", "PUT", "DELETE", "TRACE"])
  assert_eq(retry.max_retry_after, 60_000)
  assert_eq(retry.base_delay, 1000)
  assert_eq(retry.max_delay, 30_000)
  assert_eq(Retry::none().max_retries, 0)
  let clamped = Retry::new(
    max_retries=-1,
    max_retry_after=-1,
    base_delay=-1,
    max_delay=-1,
    methods=["get"],
  )
  assert_eq(clamped.max_retries, 0)
  assert_eq(clamped.max_retry_after, 0)
  assert_eq(clamped.base_delay, 0)
  assert_eq(clamped.max_delay, 0)
  assert_eq(clamped.methods, ["GET"])
}

///|
test "retryable: idempotent methods on transient statuses and failures, any method when unsent" {
  let retry = Retry::new()
  let ok = (http_method : String, status : Int32) => {
    let request = @http.Request::new(http_method, "https://a.test/")
    let outcome : Result[Response, ReqError] = Ok(
      Response::new(status, request),
    )
    (request, outcome)
  }
  let err = (http_method : String, error : (Request) -> ReqError) => {
    let request = @http.Request::new(http_method, "https://a.test/")
    let outcome : Result[Response, ReqError] = Err(error(request))
    (request, outcome)
  }
  let cases : Array[(String, (Request, Result[Response, ReqError]), Bool)] = [
    ("GET 503", ok("GET", 503), true),
    ("get 503", ok("get", 503), true),
    ("HEAD 408", ok("HEAD", 408), true),
    ("OPTIONS 429", ok("OPTIONS", 429), true),
    ("PUT 500", ok("PUT", 500), true),
    ("DELETE 502", ok("DELETE", 502), true),
    ("TRACE 504", ok("TRACE", 504), true),
    ("GET 501", ok("GET", 501), false),
    ("GET 404", ok("GET", 404), false),
    ("GET 200", ok("GET", 200), false),
    ("POST 503", ok("POST", 503), false),
    ("PATCH 429", ok("PATCH", 429), false),
    (
      "GET timeout",
      err("GET", r => Timeout(request=r, phase=Head, timeout=1)),
      true,
    ),
    (
      "GET call timeout",
      err("GET", r => Timeout(request=r, phase=Unknown, timeout=1)),
      true,
    ),
    (
      "GET reset",
      err("GET", r => Network(request=r, phase=Body, message="")),
      true,
    ),
    (
      "POST timeout",
      err("POST", r => Timeout(request=r, phase=Head, timeout=1)),
      false,
    ),
    (
      "POST reset",
      err("POST", r => Network(request=r, phase=Write, message="")),
      false,
    ),
    (
      "POST refused",
      err("POST", r => Network(request=r, phase=Dial, message="")),
      true,
    ),
    (
      "POST pool timeout",
      err("POST", r => Timeout(request=r, phase=Pool, timeout=1)),
      true,
    ),
    (
      "POST proxy 502",
      err("POST", r => Proxy(request=r, status=502, message="")),
      true,
    ),
    (
      "GET proxy 407",
      err("GET", r => Proxy(request=r, status=407, message="")),
      false,
    ),
    ("GET protocol", err("GET", r => Protocol(request=r, message="")), false),
    ("GET invalid", err("GET", _ => InvalidRequest(message="")), false),
  ]
  for case in cases {
    let (request, outcome) = case.1
    assert_eq(retry.retryable(request, outcome), case.2, msg=case.0)
  }
  let custom = Retry::new(statuses=[501], methods=["post"])
  let (request, outcome) = ok("POST", 501)
  assert_true(custom.retryable(request, outcome))
  let (request, outcome) = ok("GET", 503)
  assert_false(custom.retryable(request, outcome))
}

///|
/// A body stream that is never read.
priv struct Idle {}

///|
impl @http.BodyStream for Idle with fn read_some(_) {
  None
}

///|
impl @http.BodyStream for Idle with fn close(_) {
  ()
}

///|
test "delay_ms: the count, the body, Retry-After and its cap, else the backoff" {
  let retry = Retry::new()
  let now = 784_111_777_000L // Sun, 06 Nov 1994 08:49:37 GMT
  let get = @http.Request::get("https://a.test/")
  let response = (headers : Array[(String, String)]) => {
    let outcome : Result[Response, ReqError] = Ok(
      Response::new(503, get, headers=@http.Headers::from_array(headers)),
    )
    outcome
  }
  let cases : Array[(String, Result[Response, ReqError], Int32, Int32?)] = [
    ("backoff, first retry", response([]), 0, Some(500)),
    ("backoff, third retry", response([]), 2, Some(2000)),
    ("no fourth retry", response([]), 3, None),
    ("seconds", response([("Retry-After", "5")]), 0, Some(5000)),
    ("zero", response([("Retry-After", "0")]), 2, Some(0)),
    ("at the cap", response([("Retry-After", "60")]), 0, Some(60_000)),
    ("over the cap", response([("Retry-After", "61")]), 0, None),
    (
      "HTTP date",
      response([("Retry-After", "Sun, 06 Nov 1994 08:49:40 GMT")]),
      0,
      Some(3000),
    ),
    (
      "past HTTP date",
      response([("Retry-After", "Sun, 06 Nov 1994 08:49:00 GMT")]),
      0,
      Some(0),
    ),
    (
      "far HTTP date",
      response([("Retry-After", "Mon, 07 Nov 1994 08:49:37 GMT")]),
      0,
      None,
    ),
    ("unreadable", response([("Retry-After", "soon")]), 1, Some(1000)),
    (
      "retry-after-ms is not standard",
      response([("Retry-After-Ms", "10")]),
      0,
      Some(500),
    ),
    ("not retryable", Ok(Response::new(404, get)), 0, None),
    (
      "failure",
      Err(Network(request=get, phase=Dial, message="")),
      1,
      Some(1000),
    ),
  ]
  for case in cases {
    assert_eq(retry.delay_ms(get, case.1, case.2, now, 0.5), case.3, msg=case.0)
  }
  let stream = @http.StreamBody::new(Idle::{ })
  let put = @http.Request::put("https://a.test/")
  let put = { ..put, body: Stream(stream), }
  let failed : Result[Response, ReqError] = Err(
    Network(request=put, phase=Dial, message=""),
  )
  assert_eq(retry.delay_ms(put, failed, 0, now, 0.5), Some(500), msg="untaken")
  let _ = stream.take()
  assert_eq(retry.delay_ms(put, failed, 0, now, 0.5), None, msg="taken")
  assert_eq(Retry::none().delay_ms(get, response([]), 0, now, 0.5), None)
}

///|
test "full_jitter draws below base * 2 ^ retries, capped" {
  let cases : Array[(Int32, Int32, Int32, Double, Int32)] = [
    (1000, 30_000, 0, 0.5, 500),
    (1000, 30_000, 1, 0.5, 1000),
    (1000, 30_000, 2, 0.9999, 3999),
    (1000, 30_000, 4, 0.0, 0),
    (1000, 30_000, 5, 0.5, 15_000),
    (1000, 30_000, 1_000_000, 0.5, 15_000),
    (1000, 30_000, 5, 1.0, 29_999),
    (1000, 30_000, 5, -1.0, 0),
    (1000, 30_000, 5, 0.0 / 0.0, 0),
    (1000, 30_000, -3, 0.5, 500),
    (50_000, 30_000, 0, 0.5, 15_000),
    (0, 30_000, 3, 0.5, 0),
  ]
  for case in cases {
    assert_eq(
      full_jitter(case.0, case.1, case.2, case.3),
      case.4,
      msg=@debug.to_string(case),
    )
  }
}
