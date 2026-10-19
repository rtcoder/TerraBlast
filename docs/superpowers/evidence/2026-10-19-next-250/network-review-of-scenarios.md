# Independent review: final scenarios runner/report/resume

Status: actionable findings fixed and independently rechecked; see `network-review-resolution.md`. The text below records the original review.

Read-only review of `tools/scenarios.py`, `tools/scenario_report.py`, test suites and final CLI documentation against scenario plan. No product edits during review. Three confirmed findings passed to root.

## P1 — Fast successful exit bypasses the log size limit

`tools/scenarios.py:98`–105 `_execute` checks the8MiB limit only while process.poll() is None. If the executable writes9MB and exits between two polls, the loop takes its successful else branch and returns passed. The captured file remains9MB and errors beyond the bounded8MiB read can be hidden. Existing large-output test sleeps after writing, so it misses this case.

Reproduced with `_execute([sys.executable,'-c',"import sys;sys.stdout.write('x'*9000000)"],tmp,5,threading.Event())`: status passed, exit0, actual_bytes9000000, elapsed0.0289s. Add a final file-size check after process cleanup, as existing `devtools.run_case` already does; test a large-output process that exits immediately.

## P2 — A recovered case is reported as a regression

`tools/scenario_report.py:99`–106 compare_reports compares state/shot/damage even when the baseline timed out without a summary. A candidate passed case correctly produces status regression=false, but absent→actual state and None→2 shots are marked regression=true, so overall ok=false. This makes baseline failure recovery return exit1.

Reproduced with matching case/config digest, baseline status timeout without summary and candidate status passed with a valid summary: changes include status(regression=false), state(regression=true), shots(regression=true). Compare deterministic outcome changes only when both sides have comparable successful outcomes; retain candidate failures as regressions.

## P2 — Oversized finite JSON integers bypass controlled validation

`tools/scenario_report.py:44` and68 call math.isfinite on arbitrary Python integers. A JSON integer10**400 is syntactically valid and within the report byte cap, but float conversion inside math.isfinite raises OverflowError, which neither validation nor CLI main catches. The result is a traceback/exit1 instead of the promised controlled invalid-input exit2. Statistics values have the same issue.

Reproduced `validate_report({... duration_seconds:10**400 ...})`: OverflowError int too large to convert to float. Reject oversized integers explicitly or use a finite-number validator that cannot overflow; add duration and metric cases through CLI.

## Safety/resume/report checks that held

Commands are reconstructed solely from validated manifest axes; report command fields cannot add executable arguments. Case IDs are generated from canonical config digests. Resume checks producer/config, bounded artifact paths rooted under cases/ID/attempt, absence of symlink ancestors, sizes/SHA256 and canonical summary-file equality. A foreign manifest is rejected and failed/tampered cases use fresh attempt directories. Root metadata/lock symlinks are rejected, concurrency bounded1–4 and cancellation uses existing process-group cleanup. HTML is escaped and CSV prefixes formula-leading cells. No confirmed path escape or command execution issue found in the reviewed paths.
