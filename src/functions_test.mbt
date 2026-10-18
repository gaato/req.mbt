///|
async test "top-level functions send through a throw-away client" {
  // An unsupported scheme fails before any I/O, so these run offline while
  // still creating, using and closing the default client.
  let url = "ftp://a.test/"
  let calls : Array[
    async () -> @requesto.Response raise @requesto.RequestoError,
  ] = [
    () => @requesto.request("GET", url),
    () => @requesto.get(url),
    () => @requesto.head(url),
    () => @requesto.options(url),
    () => @requesto.delete(url),
    () => @requesto.post(url, json=Json::null()),
    () => @requesto.put(url, data=[]),
    () => @requesto.patch(url, text=""),
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
  let streamed = try {
    let _ : Int32 = @requesto.stream("GET", url, response => response.status)
    "sent"
  } catch {
    @requesto.RequestoError::UnsupportedProtocol(url=u) => u
    error => "unexpected \{error}"
  }
  assert_eq(streamed, url)
}

///|
async test "MockTransport streams the handler's response as one chunk" {
  let transport = @requesto.MockTransport::new(request => {
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
