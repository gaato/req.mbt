///|
/// RFC 7616 §3.9.1's challenge, with `nonce` and `stale`.
fn challenge(nonce~ : String, stale~ : Bool = false) -> String {
  let stale = if stale { ", stale=true" } else { "" }
  "Digest realm=\"http-auth@example.org\", qop=\"auth, auth-int\", algorithm=SHA-256, nonce=\"\{nonce}\", opaque=\"FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS\"\{stale}"
}

///|
let rfc_nonce = "7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v"

///|
/// The answer to `challenge` for Mufasa's GET of /dir/index.html with a
/// cnonce drawn from 0.5, computed independently.
fn answer(nonce~ : String, nc~ : String, response~ : String) -> String {
  "Digest username=\"Mufasa\", realm=\"http-auth@example.org\", uri=\"/dir/index.html\", algorithm=SHA-256, nonce=\"\{nonce}\", nc=\{nc}, cnonce=\"80000000800000008000000080000000\", qop=auth, response=\"\{response}\", opaque=\"FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS\""
}

///|
/// A server that wants Digest: it records each request's `Authorization`
/// and answers with `respond`, given the request's number from 0.
fn server(
  seen : Array[String?],
  respond : (Int32, String?) -> (Int32, String?),
) -> @req.MockTransport {
  @req.MockTransport::new(request => {
    let authorization = request.headers.get("authorization")
    seen.push(authorization)
    if request.body is Stream(body) {
      ignore(body.take())
    }
    let (status, challenge) = respond(seen.length() - 1, authorization)
    let headers = match challenge {
      Some(value) => [("WWW-Authenticate", value)]
      None => []
    }
    { status, headers: @http.Headers::from_array(headers), body: b"", }
  })
}

///|
fn mufasa(transport : @req.MockTransport) -> @req.Client {
  @req.Client::new(
    transport~,
    auth=Digest(username="Mufasa", password="Circle of Life"),
    random=() => 0.5,
    retry=@req.Retry::none(),
  )
}

///|
async test "Digest answers a 401 once, then reuses the nonce with a counted nc" {
  let seen = []
  let client = mufasa(
    server(seen, (_, authorization) => {
      match authorization {
        None => (401, Some(challenge(nonce=rfc_nonce)))
        Some(_) => (200, None)
      }
    }),
  )
  let url = "https://a.test/dir/index.html"
  assert_eq(client.get(url).status, 200)
  assert_eq(client.get(url).status, 200)
  assert_eq(seen, [
    None,
    Some(
      answer(
        nonce=rfc_nonce,
        nc="00000001",
        response="1533fd14d2a9448ea55bd4eca0a54f5ef9387326d926a7350fe6a3c2357f454f",
      ),
    ),
    Some(
      answer(
        nonce=rfc_nonce,
        nc="00000002",
        response="5abf1c094d98e2d057f90ee9b918ebea75db7f4b0898d0ef3133a4696527fd54",
      ),
    ),
  ])
}

///|
async test "a stale nonce is answered with the new one" {
  let seen = []
  let client = mufasa(
    server(seen, (n, _) => {
      match n {
        0 => (401, Some(challenge(nonce=rfc_nonce)))
        2 => (401, Some(challenge(nonce="fresh", stale=true)))
        _ => (200, None)
      }
    }),
  )
  let url = "https://a.test/dir/index.html"
  assert_eq(client.get(url).status, 200)
  assert_eq(client.get(url).status, 200)
  assert_eq(seen.length(), 4)
  assert_true(seen[2].unwrap().contains("nc=00000002"), msg="the old nonce")
  assert_eq(
    seen[3],
    Some(
      answer(
        nonce="fresh",
        nc="00000001",
        response="2218116c60a122226d2aabe04e8d6333e27c87cb7ffd7e8a9f648a6dac421495",
      ),
    ),
  )
}

///|
async test "a refused answer returns the 401, and a stale one is answered once more" {
  let seen = []
  let client = mufasa(
    server(seen, (_, _) => (401, Some(challenge(nonce=rfc_nonce)))),
  )
  assert_eq(client.get("https://a.test/").status, 401)
  assert_eq(seen.length(), 2, msg="sent, then answered once")
  let seen = []
  let client = mufasa(
    server(seen, (n, _) => (401, Some(challenge(nonce="n\{n}", stale=n > 0)))),
  )
  assert_eq(client.get("https://a.test/").status, 401)
  assert_eq(seen.length(), 3, msg="answered, then once more for stale")
}

///|
/// A body stream with nothing in it.
struct Nothing {}

///|
impl @http.BodyStream for Nothing with fn read_some(_) {
  None
}

///|
impl @http.BodyStream for Nothing with fn close(_) {
  ()
}

///|
async test "Digest leaves alone a call with its own Authorization, other schemes and a sent stream" {
  let cases : Array[(String, Array[(String, String)], Bool, Int32, Int32)] = [
    (challenge(nonce="n"), [("Authorization", "Token t")], false, 401, 1),
    ("Basic realm=\"r\"", [], false, 401, 1),
    (challenge(nonce="n"), [], true, 401, 1),
    ("Digest realm=\"r\", nonce=\"n\", qop=auth-int", [], false, 200, 2),
    ("Digest realm=\"r\", nonce=\"n\", qop=auth-int", [], true, 401, 1),
  ]
  for case in cases {
    let seen = []
    let client = mufasa(
      server(seen, (_, authorization) => {
        match authorization {
          None | Some("Token t") => (401, Some(case.0))
          Some(_) => (200, None)
        }
      }),
    )
    let response = if case.2 {
      client.put("https://a.test/", headers=case.1, body_stream=Nothing::{ })
    } else {
      client.put("https://a.test/", headers=case.1, text="body")
    }
    assert_eq(response.status, case.3, msg=case.0)
    assert_eq(seen.length(), case.4, msg=case.0)
  }
}

///|
async test "Digest nonces are kept per origin" {
  let seen = []
  let client = mufasa(
    server(seen, (_, authorization) => {
      match authorization {
        None => (401, Some(challenge(nonce=rfc_nonce)))
        Some(_) => (200, None)
      }
    }),
  )
  let _ = client.get("https://a.test/")
  let _ = client.get("https://b.test/")
  let _ = client.get("https://a.test/")
  assert_eq(seen.map(value => value.map(v => v.contains("nc=00000001"))), [
    None,
    Some(true),
    None,
    Some(true),
    Some(false),
  ])
}

///|
async test "a retry passes through Digest again with the next nc" {
  let clock = @simclock.VirtualClock()
  let seen = []
  let client = @req.Client::new(
    transport=server(seen, (n, authorization) => {
      match (n, authorization) {
        (_, None) => (401, Some(challenge(nonce=rfc_nonce)))
        (1, _) => (503, None)
        _ => (200, None)
      }
    }),
    clock~,
    auth=Digest(username="Mufasa", password="Circle of Life"),
    random=() => 0.0,
  )
  @async.with_task_group(group => {
    let status = Ref(0)
    group.spawn_bg(() => status.val = client.get("https://a.test/").status)
    clock.advance(0)
    assert_eq(status.val, 200)
  })
  assert_eq(seen.length(), 3)
  assert_true(seen[1].unwrap().contains("nc=00000001"))
  assert_true(seen[2].unwrap().contains("nc=00000002"))
}
