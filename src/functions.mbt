///|
/// Sends a request with a throw-away client, closed afterwards. The
/// arguments are those of `Client::request`.
///
/// ```mbt check
/// async test {
///   let response = try @requesto.request("GET", "ftp://example.com/") catch {
///     UnsupportedProtocol(..) => None
///     error => raise error
///   } noraise {
///     response => Some(response)
///   }
///   assert_true(response is None)
/// }
/// ```
pub async fn request(
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
  total_timeout? : Int32?,
  follow_redirects? : Bool,
  retry? : Retry,
) -> Response raise RequestoError {
  let client = Client::new()
  defer client.close()
  client.request(
    http_method,
    url,
    params~,
    headers~,
    content?,
    text?,
    data?,
    files?,
    json?,
    body_stream?,
    body_length?,
    timeout?,
    total_timeout?,
    follow_redirects?,
    retry?,
  )
}

///|
/// Streams a response with a throw-away client, closed afterwards. The
/// arguments are those of `Client::stream`.
pub async fn[T] stream(
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
  total_timeout? : Int32?,
  follow_redirects? : Bool,
  retry? : Retry,
  f : async (Response) -> T,
) -> T {
  let client = Client::new()
  defer client.close()
  client.stream(
    http_method,
    url,
    params~,
    headers~,
    content?,
    text?,
    data?,
    files?,
    json?,
    body_stream?,
    body_length?,
    timeout?,
    total_timeout?,
    follow_redirects?,
    retry?,
    f,
  )
}

///|
/// Sends a `GET` request with a throw-away client, closed afterwards.
pub async fn get(
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  timeout? : Int32,
  total_timeout? : Int32?,
  follow_redirects? : Bool,
  retry? : Retry,
) -> Response raise RequestoError {
  let client = Client::new()
  defer client.close()
  client.get(
    url,
    params~,
    headers~,
    timeout?,
    total_timeout?,
    follow_redirects?,
    retry?,
  )
}

///|
/// Sends a `HEAD` request with a throw-away client, closed afterwards.
pub async fn head(
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  timeout? : Int32,
  total_timeout? : Int32?,
  follow_redirects? : Bool,
  retry? : Retry,
) -> Response raise RequestoError {
  let client = Client::new()
  defer client.close()
  client.head(
    url,
    params~,
    headers~,
    timeout?,
    total_timeout?,
    follow_redirects?,
    retry?,
  )
}

///|
/// Sends a `OPTIONS` request with a throw-away client, closed afterwards.
pub async fn options(
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  timeout? : Int32,
  total_timeout? : Int32?,
  follow_redirects? : Bool,
  retry? : Retry,
) -> Response raise RequestoError {
  let client = Client::new()
  defer client.close()
  client.options(
    url,
    params~,
    headers~,
    timeout?,
    total_timeout?,
    follow_redirects?,
    retry?,
  )
}

///|
/// Sends a `DELETE` request with a throw-away client, closed afterwards.
pub async fn delete(
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  timeout? : Int32,
  total_timeout? : Int32?,
  follow_redirects? : Bool,
  retry? : Retry,
) -> Response raise RequestoError {
  let client = Client::new()
  defer client.close()
  client.delete(
    url,
    params~,
    headers~,
    timeout?,
    total_timeout?,
    follow_redirects?,
    retry?,
  )
}

///|
/// Sends a `POST` request with a throw-away client, closed afterwards.
pub async fn post(
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
  total_timeout? : Int32?,
  follow_redirects? : Bool,
  retry? : Retry,
) -> Response raise RequestoError {
  let client = Client::new()
  defer client.close()
  client.post(
    url,
    params~,
    headers~,
    content?,
    text?,
    data?,
    files?,
    json?,
    body_stream?,
    body_length?,
    timeout?,
    total_timeout?,
    follow_redirects?,
    retry?,
  )
}

///|
/// Sends a `PUT` request with a throw-away client, closed afterwards.
pub async fn put(
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
  total_timeout? : Int32?,
  follow_redirects? : Bool,
  retry? : Retry,
) -> Response raise RequestoError {
  let client = Client::new()
  defer client.close()
  client.put(
    url,
    params~,
    headers~,
    content?,
    text?,
    data?,
    files?,
    json?,
    body_stream?,
    body_length?,
    timeout?,
    total_timeout?,
    follow_redirects?,
    retry?,
  )
}

///|
/// Sends a `PATCH` request with a throw-away client, closed afterwards.
pub async fn patch(
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
  total_timeout? : Int32?,
  follow_redirects? : Bool,
  retry? : Retry,
) -> Response raise RequestoError {
  let client = Client::new()
  defer client.close()
  client.patch(
    url,
    params~,
    headers~,
    content?,
    text?,
    data?,
    files?,
    json?,
    body_stream?,
    body_length?,
    timeout?,
    total_timeout?,
    follow_redirects?,
    retry?,
  )
}
