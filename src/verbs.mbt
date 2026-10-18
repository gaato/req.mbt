///|
/// Sends a `GET` request: `request("GET", url, ...)`.
pub async fn Client::get(
  self : Client,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  timeout? : Int32,
  follow_redirects? : Bool,
) -> Response raise ReqError {
  self.request("GET", url, params~, headers~, timeout?, follow_redirects?)
}

///|
/// Sends a `HEAD` request: `request("HEAD", url, ...)`.
pub async fn Client::head(
  self : Client,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  timeout? : Int32,
  follow_redirects? : Bool,
) -> Response raise ReqError {
  self.request("HEAD", url, params~, headers~, timeout?, follow_redirects?)
}

///|
/// Sends a `OPTIONS` request: `request("OPTIONS", url, ...)`.
pub async fn Client::options(
  self : Client,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  timeout? : Int32,
  follow_redirects? : Bool,
) -> Response raise ReqError {
  self.request("OPTIONS", url, params~, headers~, timeout?, follow_redirects?)
}

///|
/// Sends a `DELETE` request: `request("DELETE", url, ...)`.
pub async fn Client::delete(
  self : Client,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  timeout? : Int32,
  follow_redirects? : Bool,
) -> Response raise ReqError {
  self.request("DELETE", url, params~, headers~, timeout?, follow_redirects?)
}

///|
/// Sends a `POST` request: `request("POST", url, ...)`.
pub async fn Client::post(
  self : Client,
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
  self.request(
    "POST",
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
    follow_redirects?,
  )
}

///|
/// Sends a `PUT` request: `request("PUT", url, ...)`.
pub async fn Client::put(
  self : Client,
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
  self.request(
    "PUT",
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
    follow_redirects?,
  )
}

///|
/// Sends a `PATCH` request: `request("PATCH", url, ...)`.
pub async fn Client::patch(
  self : Client,
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
  self.request(
    "PATCH",
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
    follow_redirects?,
  )
}
