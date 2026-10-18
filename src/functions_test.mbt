///|
async test "top-level functions send through a throw-away client" {
  // An unsupported scheme fails before any I/O, so these run offline while
  // still creating, using and closing the default client.
  let url = "ftp://a.test/"
  let calls : Array[async () -> @req.Response raise @req.ReqError] = [
    () => @req.request("GET", url),
    () => @req.get(url),
    () => @req.head(url),
    () => @req.options(url),
    () => @req.delete(url),
    () => @req.post(url, json=Json::null()),
    () => @req.put(url, data=[]),
    () => @req.patch(url, text=""),
  ]
  for i, call in calls {
    let outcome = try call() catch {
      UnsupportedProtocol(url=u) => u
      error => "unexpected \{error}"
    } noraise {
      _ => "sent"
    }
    assert_eq(outcome, url, msg="call \{i}")
  }
}

///|
async test "MockTransport streams the handler's response as one chunk" {
  let transport = @req.MockTransport::new(request => {
    status: 201,
    headers: @http.Headers::new(),
    body: @utf8.encode(request.url),
  })
  let (head, stream) = transport.send_stream(@http.Request::get("/x"))
  assert_eq(head.status, 201)
  assert_eq(stream.read_some(), Some(b"/x"))
  assert_eq(stream.read_some(), None)
  let (_, stream) = transport.send_stream(@http.Request::get("/y"))
  stream.close()
  assert_eq(stream.read_some(), None)
}
