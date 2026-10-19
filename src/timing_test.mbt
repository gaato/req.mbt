///|
/// A transport whose responses wait for `release`.
fn held(release : @aqueue.Queue[Int32]) -> @requesto.MockTransport {
  @requesto.MockTransport::new(_ => {
    let status = release.get() catch { _ => 0 }
    { status, headers: @http.Headers::new(), body: b"", }
  })
}

///|
/// Runs `call` in the background and returns where its outcome lands:
/// `None` while it runs, then the status or the error's variant.
fn outcome_of(
  group : @async.TaskGroup[Unit],
  call : async () -> @requesto.Response raise @requesto.RequestoError,
) -> Ref[String?] {
  let outcome = Ref(None)
  group.spawn_bg(() => {
    outcome.val = Some(
      try call() catch {
        Timeout(timeout~, ..) => "Timeout \{timeout}"
        TotalTimeout(timeout~, ..) => "TotalTimeout \{timeout}"
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
  let client = @requesto.Client::new(
    transport=held(release),
    clock~,
    retry=@requesto.Retry::none(),
  )
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
  let client = @requesto.Client::new(
    transport=held(release),
    clock~,
    timeout=100,
    retry=@requesto.Retry::none(),
  )
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
  let client = @requesto.Client::new(
    clock~,
    steps=[@requesto.on_request(_ => clock.sleep(1000))],
    transport=@requesto.MockTransport::new(_ => {
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

///|
async test "a call takes at most max_retries + 2 exchanges in all by default, steps and retries included" {
  let clock = @simclock.VirtualClock()
  let release : @aqueue.Queue[Int32] = Queue(kind=Unbounded)
  let client = @requesto.Client::new(
    transport=held(release),
    clock~,
    random=() => 0.5,
    steps=[@requesto.on_request(_ => clock.sleep(100_000))],
  )
  @async.with_task_group(group => {
    let outcome = outcome_of(group, () => client.get("https://a.test/"))
    clock.advance(149_999)
    assert_eq(
      outcome.val,
      None,
      msg="a step, one exchange, a wait, part of another",
    )
    clock.advance(1)
    assert_eq(outcome.val, Some("TotalTimeout 150000"), msg="5 times 30 s")
    assert_eq(clock.pending(), [], msg="no timer is left behind")
  })
}

///|
async test "the derived total follows a raised timeout, and total_timeout=None lifts it" {
  let clock = @simclock.VirtualClock()
  let release : @aqueue.Queue[Int32] = Queue(kind=Unbounded)
  let client = @requesto.Client::new(
    transport=held(release),
    clock~,
    retry=@requesto.Retry::none(),
  )
  @async.with_task_group(group => {
    let long = outcome_of(group, () => {
      client.get("https://a.test/", timeout=600_000)
    })
    clock.advance(599_999)
    assert_eq(long.val, None, msg="not cut at 2.5 minutes")
    clock.advance(1)
    assert_eq(long.val, Some("Timeout 600000"), msg="the send's own timeout")
  })
  let unbounded = @requesto.Client::new(
    transport=held(release),
    clock~,
    retry=@requesto.Retry::none(),
    total_timeout=None,
    steps=[@requesto.on_request(_ => clock.sleep(10_000_000))],
  )
  @async.with_task_group(group => {
    let outcome = outcome_of(group, () => unbounded.get("https://a.test/"))
    clock.advance(10_000_000)
    assert_eq(outcome.val, None)
    release.put(200)
    clock.settle()
    assert_eq(outcome.val, Some("status 200"))
  })
}

///|
async test "total_timeout is set per client and replaced per call" {
  let clock = @simclock.VirtualClock()
  let release : @aqueue.Queue[Int32] = Queue(kind=Unbounded)
  let client = @requesto.Client::new(
    transport=held(release),
    clock~,
    timeout=5000,
    total_timeout=Some(1000),
  )
  @async.with_task_group(group => {
    let by_client = outcome_of(group, () => client.get("https://a.test/"))
    let by_call = outcome_of(group, () => {
      client.get("https://a.test/", total_timeout=Some(2000))
    })
    clock.advance(1000)
    assert_eq(by_client.val, Some("TotalTimeout 1000"))
    assert_eq(by_call.val, None)
    clock.advance(1000)
    assert_eq(by_call.val, Some("TotalTimeout 2000"))
    assert_eq(clock.pending(), [])
  })
}
