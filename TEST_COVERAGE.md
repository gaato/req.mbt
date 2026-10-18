# Test coverage ledger

Line coverage of `gaato/req`, measured on native with `moon test
--enable-coverage` and reported in Coveralls-JSON mode. The rule is a closed
ledger:

> **Every uncovered line is either covered by a test or listed below with a
> reason.** `scripts/coverage_report.sh` enforces this: a file with uncovered
> lines must have a row here whose budget is at least the actual count, and
> the script fails otherwise. Rows for fully covered files are flagged as
> stale and rows with slack are noted, so budgets only ever shrink.

## Running it

```fish
scripts/coverage_report.sh                    # measure, print tables, check the ledger
scripts/coverage_report.sh --from-json _build/coverage_report.json   # recheck only
```

CI runs it after the gates on every push and pull request. Exit status: 0 =
ledger OK, 1 = an unexplained or over-budget file, 2 = the run itself failed
(a failing test, a build error). The tests use `MockTransport` and
`VirtualClock` only: no sockets, no real sleeps.

### What is measured

- Sources: every non-test `.mbt` under `src/`.
- Counts are Coveralls lines: lines with at least one instrumented point,
  covered when any point on them ran.

### Pitfalls the script pins

- Counters from earlier runs and trace maps of moved or deleted packages
  silently corrupt the merge, so every run deletes `_build/**/moonbit_coverage_*`
  and `_build/native/debug/test` first, and passes the trace maps and counter
  files to the reporter explicitly.
- `-f summary` omits fully covered files, which skews totals; the script uses
  the Coveralls JSON.
- moon's bundled tcc cannot link on some hosts (openSUSE); the script sets
  `MOON_CC=cc` unless it is already set.

Snapshot at the last full measurement (2026-10-18): **99.5 %** (390/392
lines).

## Policy

Must be covered by tests:

- the pure decisions: URL joining, query and header merging, URL and method
  checks, body selection and encoding, status classes, error mapping and
  messages, line splitting and the event-stream checks;
- every `raise` arm reachable through the public API;
- the client, the verbs, the top-level functions, the step chain, the
  timeout and the streamed readers (chunks, lines, events), through
  `MockTransport` and `VirtualClock`.

Accepted as uncovered (needs a row):

- defensive arms that are unreachable by construction;
- testable lines not yet tested, marked `not yet tested`.

Budgets are exact uncovered counts at the last measurement.

## Accepted uncovered

| File | Budget | Reason |
| --- | --- | --- |
| src/body.mbt | 2 | Two arms of the multipart error mapping that cannot be reached: `InvalidBoundary`, since `encode_segments_fresh` and `encode_multipart` draw boundaries with `make_boundary`, which only makes valid ones; and `StreamPart`, since `encode_multipart` calls `encode_segments_fresh` only when every part is bytes. |
