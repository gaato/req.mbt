///|
/// An RFC 3986 URI reference: `@http.Url`, for taking apart, resolving or
/// comparing the URLs of responses.
///
/// ```mbt check
/// test {
///   let page = @req.Url::parse("https://api.example.com/v1/items?page=1")
///   let next = page.resolve(@req.Url::parse("items?page=2"))
///   assert_eq(next.to_string(), "https://api.example.com/v1/items?page=2")
///   assert_eq(next.query_params(), [("page", "2")])
///   assert_true(page.same_origin(next))
/// }
/// ```
pub type Url = @http.Url

///|
/// The length of `url`'s scheme when it starts with one followed by `://`:
/// a letter, then letters, digits, `+`, `-` or `.`.
fn scheme_length(url : String) -> Int32? {
  guard url.find("://") is Some(end) && end > 0 else { return None }
  for i in 0..<end {
    let c = url[i]
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (i > 0 && ((c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.'))
    if !ok {
      return None
    }
  }
  Some(end)
}

///|
/// Appends `url` to `base_url`, unless `url` is absolute. One `/` joins
/// them, so a leading `/` on `url` does not discard the base URL's path. The
/// path goes before the base URL's query, whose parameters come first in the
/// result. Fragments are dropped: they are never sent.
fn join_url(base_url : String?, url : String) -> String {
  guard base_url is Some(base) && scheme_length(url) is None else { return url }
  let (base, base_query) = split_query(without_fragment(base))
  let (path, query) = split_query(without_fragment(url))
  let base = base.trim_end(chars="/").to_owned()
  let path = path.trim_start(chars="/").to_owned()
  let joined = if path.is_empty() { base } else { base + "/" + path }
  let query = match (base_query, query) {
    (None, None) => ""
    (Some(q), None) | (None, Some(q)) => "?" + q
    (Some(a), Some(b)) =>
      if a.is_empty() {
        "?" + b
      } else if b.is_empty() {
        "?" + a
      } else {
        "?" + a + "&" + b
      }
  }
  joined + query
}

///|
fn without_fragment(url : String) -> String {
  match url.find("#") {
    Some(i) => url[:i].to_owned()
    None => url
  }
}

///|
/// `url` before its first `?`, and what follows it, if there is a `?`.
fn split_query(url : String) -> (String, String?) {
  match url.find("?") {
    Some(i) => (url[:i].to_owned(), Some(url[i + 1:].to_owned()))
    None => (url, None)
  }
}

///|
/// The client's parameters that the call does not name, then the call's.
fn merge_params(
  client : Array[(String, String)],
  call : Array[(String, String)],
) -> Array[(String, String)] {
  let named = call.map(pair => pair.0)
  [..client.filter(pair => !named.contains(pair.0)), ..call]
}

///|
/// `url` parsed, if it is an absolute `http` or `https` URL with a host.
/// Parsing normalises it as `@http.Url::parse` does: lower-case scheme and
/// host, canonical IPv6, no default port, no dot segments, and what has to
/// be percent-encoded encoded (existing escapes kept). A space or control
/// character is refused rather than encoded or dropped.
fn parse_url(url : String) -> Url raise ReqError {
  for c in url {
    if c <= ' ' || c == '\u{7f}' {
      raise InvalidURL(url~, message="contains a space or control character")
    }
  }
  guard scheme_length(url) is Some(end) else {
    raise InvalidURL(url~, message="not an absolute URL")
  }
  let scheme = url[:end].to_lower()
  if scheme != "http" && scheme != "https" {
    raise UnsupportedProtocol(url~)
  }
  let parsed = @http.Url::parse(url) catch {
    @http.UrlError::Invalid(message) => raise InvalidURL(url~, message~)
  }
  if parsed.host is (None | Some("")) {
    raise InvalidURL(url~, message="no host")
  }
  parsed
}
