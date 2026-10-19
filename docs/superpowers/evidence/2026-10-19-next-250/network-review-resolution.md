# Independent review resolution

Read current fixes and reran the original narrow reproductions. No root or competition product code edited by reviewer.

## Scenarios — all3findings resolved

- `_execute` now performs a final process.log size check after child cleanup. A fast9MB successful process is reported log_limit rather than passed.
- `compare_reports` limits deterministic outcome and timing comparisons to two passed cases. Timeout→passed is an improvement and no longer acquires false state/shot regressions; candidate failures remain regressions.
- `finite_number` catches oversized-int float conversion and rejects booleans/non-numbers. Duration and statistics validation use it, as do comparison thresholds. CLI tests with10**400 return controlled exit2 and JSON reasons invalid duration / invalid statistic damage, with no traceback.

Verification: `PYTHONPATH=tools python3 -m unittest test_scenarios.FailureContracts.test_review_fast_output_recovery_and_huge_numbers -v` passed (1test). Additional CLI duration/statistics reproductions passed; durable results `network-review-scenario-cli-resolution.json`.

## Competition — both actionable findings resolved

- `resume` with no saved active match now calls `return_to_live(false)` before dropping the old fixture token, restores retained live context and does not overwrite the loaded draft. Panel visibility/menu pause is restored coherently after replacement. Original probe now reports draft_resume_ok=true, orphan_runner_kept=false, fixture_runner_null=true, active_empty=true, live_context_kept=false.
- `Event.restore` rejects last_draw at or after the current active attempt, and rejects a stored draw preceding/equal to the latest recorded final result. Original future-draw probe now returns false.

The same-size cross-arena probe still returns true, deliberately: final accepted contract verifies canonical rules/weapons/dimensions/roster and snapshot integrity, and does not promise terrain provenance for mutable live snapshots. Root clarified this limitation; it is not an open blocker.

Verification: reran `/private/tmp/tb19_competition_review_probe.gd` on Godot4.6.2 and inspected each output. Targeted competition core and full-scene integration regression runs both passed: `competition19: PASS failures=0` and `competition19_next: PASS failures=0` (`/private/tmp/tb19-competition-final-unit.log`, `/private/tmp/tb19-competition-final-integration.log`).

No unresolved findings remain from this review scope.

Network test isolation follow-up also resolved: fresh temporary ConnectionProfiles injected before connection; dedicated rerun passed (network-scene-isolation.json). No normal profile destination is used by this test.
