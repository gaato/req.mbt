///|
/// A copy of `base` in which every name `overrides` uses holds only the
/// values `overrides` gives it.
fn merge_headers(
  base : @http.Headers,
  overrides : Array[(String, String)],
) -> @http.Headers {
  let merged = @http.Headers::new()
  for pair in base.iter() {
    merged.append(pair.0, pair.1)
  }
  for pair in overrides {
    merged.remove(pair.0)
  }
  for pair in overrides {
    merged.append(pair.0, pair.1)
  }
  merged
}
