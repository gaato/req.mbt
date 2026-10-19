// Helpers that src/retry_wbtest.mbt checks: the decisions themselves come
// from gaato/http/retry, which `Retry::delay_ms` asks; these expose parts of
// them on their own.

///|
/// Whether `outcome` is worth sending `request` again, leaving aside the
/// count, the body and the wait.
fn Retry::retryable(
  self : Retry,
  request : Request,
  outcome : Result[Response, RequestoError],
) -> Bool {
  guard retry_outcome(outcome) is Some(outcome) else { return false }
  let rule = {
    ..self.rule(),
    max_retries: 1,
    retry_after: { source: Ignore, cap: NoCap, zero_means_backoff: false, },
  }
  rule.decide(outcome, request, attempt=0, random=0.0, replayable=true)
  is Wait(_)
}

///|
/// A wait drawn uniformly between 0 and `base * 2 ^ retries`, capped at
/// `max` (AWS's "full jitter"). `random` is clamped into `[0, 1)`.
fn full_jitter(
  base : Int32,
  max : Int32,
  retries : Int32,
  random : Double,
) -> Int32 {
  let backoff : @retry.Backoff = { base_ms: base, max_ms: max, jitter: Full, }
  backoff.delay_ms(retries, random)
}
