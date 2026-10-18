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
/// them, so a leading `/` on `url` does not discard the base URL's path.
fn join_url(base_url : String?, url : String) -> String {
  guard base_url is Some(base) && scheme_length(url) is None else { return url }
  let base = base.trim_end(chars="/").to_owned()
  let path = url.trim_start(chars="/").to_owned()
  if path.is_empty() {
    base
  } else if path.has_prefix("?") {
    base + path
  } else {
    base + "/" + path
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
/// `url` without its fragment, with `params` added after any query it has.
fn merge_query(url : String, params : Array[(String, String)]) -> String {
  let url = match url.find("#") {
    Some(i) => url[:i].to_owned()
    None => url
  }
  let builder = StringBuilder()
  builder.write_string(url)
  let mut separator = if !url.contains("?") {
    "?"
  } else if url.has_suffix("?") || url.has_suffix("&") {
    ""
  } else {
    "&"
  }
  for pair in params {
    builder.write_string(separator)
    builder.write_string(@http.percent_encode(pair.0))
    builder.write_char('=')
    builder.write_string(@http.percent_encode(pair.1))
    separator = "&"
  }
  builder.to_string()
}

///|
/// Raises unless `url` is an absolute `http` or `https` URL with a host.
fn check_url(url : String) -> Unit raise ReqError {
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
  let rest = url[end + 3:]
  let authority = match rest.find_by(c => c == '/' || c == '?' || c == '#') {
    Some(i) => rest[:i]
    None => rest
  }
  if authority.is_empty() {
    raise InvalidURL(url~, message="no host")
  }
}
