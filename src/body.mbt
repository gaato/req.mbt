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
  Stream(&@http.BodyStream, Int64?)
}

///|
/// The body the call's arguments name; more than one is an error.
fn select_body(
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
  body_stream? : &@http.BodyStream,
  body_length? : Int64,
) -> Body raise RequestoError {
  if body_length is Some(_) && body_stream is None {
    raise InvalidRequest(message="body_length is given without body_stream")
  }
  let bodies = [
    content.map(x => Content(x)),
    text.map(x => Text(x)),
    data.map(x => Form(x)),
    files.map(x => Multipart(x)),
    json.map(x => JsonValue(x)),
    body_stream.map(x => Stream(x, body_length)),
  ].filter_map(body => body)
  match bodies {
    [] => Empty
    [body] => body
    _ =>
      raise InvalidRequest(
        message="give at most one of content, text, data, files, json and body_stream",
      )
  }
}

///|
/// The body to send and the `Content-Type` it implies, if any. `random`
/// draws multipart boundaries. Files given as streams, and `body_stream`,
/// are sent as they are read.
fn Body::encode(
  self : Body,
  random? : () -> Double,
) -> (String?, @http.Body) raise RequestoError {
  match self {
    Empty => (None, Bytes(b""))
    Content(bytes) => (None, Bytes(bytes))
    Text(text) => (Some("text/plain; charset=utf-8"), Bytes(@utf8.encode(text)))
    Form(pairs) => {
      let encoded = pairs
        .map(pair => {
          @http.percent_encode(pair.0) + "=" + @http.percent_encode(pair.1)
        })
        .join("&")
      (Some("application/x-www-form-urlencoded"), Bytes(@utf8.encode(encoded)))
    }
    Multipart(parts) => {
      let (content_type, body) = encode_multipart(parts, random?) catch {
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
        StreamPart(name) =>
          raise InvalidRequest(message="multipart: cannot stream part \{name}")
      }
      (Some(content_type), body)
    }
    JsonValue(value) =>
      (Some("application/json"), Bytes(@utf8.encode(value.stringify())))
    Stream(stream, length) =>
      (None, Stream(@http.StreamBody::new(stream, length?)))
  }
}

///|
/// A multipart body: in memory, with a boundary checked against every part,
/// when all parts are; otherwise a stream, scanned for the boundary as it is
/// sent.
fn encode_multipart(
  parts : Array[Part],
  random? : () -> Double,
) -> (String, @http.Body) raise @multipart.MultipartError {
  if parts.iter().all(part => part.body is Bytes(_)) {
    let (content_type, segments) = @multipart.encode_segments_fresh(
      parts,
      random?,
    )
    (content_type, Bytes(@multipart.join_segments(segments)))
  } else {
    let random = random.unwrap_or(@runtime.default_random)
    @multipart.encode_body(parts, @multipart.make_boundary(random))
  }
}
