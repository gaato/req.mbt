///|
/// A multipart part: `Part::text(name, value)`,
/// `Part::file(name, filename, content_type, bytes)` or
/// `Part::json(name, value)`.
pub type Part = @multipart.Part

///|
/// The one body a call sends.
priv enum Body {
  Empty
  Content(Bytes)
  Text(String)
  Form(Array[(String, String)])
  Multipart(Array[Part])
  JsonValue(Json)
}

///|
/// The body the call's arguments name; more than one is an error.
fn select_body(
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
) -> Body raise ReqError {
  let bodies = [
    content.map(x => Content(x)),
    text.map(x => Text(x)),
    data.map(x => Form(x)),
    files.map(x => Multipart(x)),
    json.map(x => JsonValue(x)),
  ].filter_map(body => body)
  match bodies {
    [] => Empty
    [body] => body
    _ =>
      raise InvalidRequest(
        message="give at most one of content, text, data, files and json",
      )
  }
}

///|
/// The body's bytes and the `Content-Type` it implies, if any. `random`
/// draws multipart boundaries.
fn Body::encode(
  self : Body,
  random? : () -> Double,
) -> (String?, Bytes) raise ReqError {
  match self {
    Empty => (None, b"")
    Content(bytes) => (None, bytes)
    Text(text) => (Some("text/plain; charset=utf-8"), @utf8.encode(text))
    Form(pairs) => {
      let encoded = pairs
        .map(pair => {
          @http.percent_encode(pair.0) + "=" + @http.percent_encode(pair.1)
        })
        .join("&")
      (Some("application/x-www-form-urlencoded"), @utf8.encode(encoded))
    }
    Multipart(parts) => {
      let (content_type, segments) = @multipart.encode_segments_fresh(
        parts,
        random?,
      ) catch {
        InvalidHeaderValue(_) =>
          raise InvalidRequest(
            message="multipart: a part's content type contains CR or LF",
          )
        BoundaryCollision =>
          raise InvalidRequest(
            message="multipart: every boundary drawn occurs in a part",
          )
        InvalidBoundary(boundary) =>
          raise InvalidRequest(
            message="multipart: invalid boundary \{boundary}",
          )
      }
      (Some(content_type), @multipart.join_segments(segments))
    }
    JsonValue(value) =>
      (Some("application/json"), @utf8.encode(value.stringify()))
  }
}
