///|
/// A transport whose responses wait for `release`.
fn held(release : @aqueue.Queue[Int32]) -> @req.MockTransport {
  @req.MockTransport::new(_ => {
    let status = release.get() catch { _ => 0 }
    { status, headers: @http.Headers::new(), body: b"", }
  })
}

///|
/// Runs `call` in the background and returns where its outcome lands:
/// `None` while it runs, then the status or the error's variant.
fn outcome_of(
  group : @async.TaskGroup[Unit],
  call : async () -> @req.Response raise @req.ReqError,
) -> Ref[String?] {
  let outcome = Ref(None)
  group.spawn_bg(() => {
    outcome.val = Some(
      try call() catch {
        Timeout(timeout~, ..) => "Timeout \{timeout}"
        error => "unexpected \{error}"
      } noraise {
        response => "status \{response.status}"
      },
    )
  })
  outcome
}

///|
async test "an exchange times out after 30 s on the client's clock by default" {
  let clock = @simclock.VirtualClock()
  let release : @aqueue.Queue[Int32] = Queue(kind=Unbounded)
  let client = @req.Client::new(transport=held(release), clock~)
  @async.with_task_group(group => {
    let outcome = outcome_of(group, () => client.get("https://a.test/"))
    clock.advance(29_999)
    assert_eq(outcome.val, None, msg="still waiting at 29,999 ms")
    clock.advance(1)
    assert_eq(outcome.val, Some("Timeout 30000"))
    assert_eq(clock.pending(), [], msg="no timer is left behind")
  })
}

///|
async test "timeout is set per client and replaced per call" {
  let clock = @simclock.VirtualClock()
  let release : @aqueue.Queue[Int32] = Queue(kind=Unbounded)
  let client = @req.Client::new(transport=held(release), clock~, timeout=100)
  @async.with_task_group(group => {
    let by_client = outcome_of(group, () => client.get("https://a.test/"))
    let by_call = outcome_of(group, () => {
      client.get("https://a.test/", timeout=250)
    })
    clock.advance(100)
    assert_eq(by_client.val, Some("Timeout 100"))
    assert_eq(by_call.val, None)
    release.put(200)
    clock.settle()
    assert_eq(by_call.val, Some("status 200"), msg="answered before 250 ms")
  })
}

///|
async test "elapsed is the transport's time on the client's clock" {
  let clock = @simclock.VirtualClock()
  let client = @req.Client::new(
    clock~,
    steps=[@req.on_request(_ => clock.sleep(1000))],
    transport=@req.MockTransport::new(_ => {
      clock.sleep(250)
      { status: 200, headers: @http.Headers::new(), body: b"", }
    }),
  )
  @async.with_task_group(group => {
    let elapsed = Ref(-1)
    group.spawn_bg(() => elapsed.val = client.get("https://a.test/").elapsed)
    clock.advance(1250)
    assert_eq(elapsed.val, 250, msg="time spent in steps is not counted")
  })
}
