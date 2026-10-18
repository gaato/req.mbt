///|
/// An RFC 6265 cookie store: `@cookie.CookieJar` of gaato/http.
pub type CookieJar = @cookie.CookieJar

///|
/// A stored cookie: `@cookie.Cookie`.
pub type Cookie = @cookie.Cookie

///|
/// A cookie's `SameSite` attribute: `@cookie.SameSite`.
pub type SameSite = @cookie.SameSite

///|
/// Cookies a client's own jar keeps per domain: the RFC 6265 §6.1 minimum.
let default_max_cookies_per_domain : Int32 = 50

///|
/// Cookies a client's own jar keeps in all: the RFC 6265 §6.1 minimum.
let default_max_cookies : Int32 = 3000

///|
/// Where a client keeps cookies instead of a jar of its own.
///
/// ```mbt check
/// test {
///   let clock = @simclock.VirtualClock()
///   let jar = @requesto.CookieJar::new(clock)
///   let first = @requesto.Client::new(clock~, cookies=Jar(jar))
///   let second = @requesto.Client::new(clock~, cookies=Jar(jar))
///   let shared = second.cookies().unwrap()
///   assert_true(physical_equal(shared, jar))
///   let none = @requesto.Client::new(cookies=Off)
///   assert_true(none.cookies() is None)
///   [first, second, none].each(client => client.close())
/// }
/// ```
pub(all) enum Cookies {
  /// In this jar, shared with other clients or filled beforehand. It reads
  /// the time from the clock it was made with.
  Jar(CookieJar)
  /// Nowhere: `Set-Cookie` is ignored and only `Cookie` headers a call or
  /// the client sets are sent.
  Off
}

///|
/// The jar for a client on `clock`: its own unless `cookies` names one or
/// turns them off.
fn cookie_jar(cookies : Cookies?, clock : &@clock.Clock) -> CookieJar? {
  match cookies {
    None =>
      Some(
        @cookie.CookieJar::new(
          clock,
          max_per_domain=default_max_cookies_per_domain,
          max_total=default_max_cookies,
        ),
      )
    Some(Jar(jar)) => Some(jar)
    Some(Off) => None
  }
}

///|
/// The step that sends `jar`'s cookies with each request that carries no
/// `Cookie` header, and stores the `Set-Cookie` headers of its response
/// (`CookieJar::attach` and `CookieJar::store`, as gaato/http's `cookies`
/// middleware does). Inside the redirect step, it sees every hop.
fn cookie_step(jar : CookieJar) -> Step {
  (request, next) => {
    let response = next(jar.attach(request))
    jar.store(response.headers, request.url)
    response
  }
}
