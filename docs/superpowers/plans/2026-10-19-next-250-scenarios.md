# Scenario Matrix Implementation Plan

> Execute inline with TDD and independent final review; user preapproved.

**Goal:** Reproducible bounded batches of existing simulations with resumable artifacts and comparisons.
**Architecture:** Python stdlib manifest/runner/report modules wrap existing Godot CLI; no gameplay change.
**Tech Stack:** Python>=3.10, subprocess processgroups, concurrent.futures, existing devtools.
**Spec:** ../specs/2026-10-19-next-250-design.md

## Constraints and review focus

Max128cases, repeats1..10, jobs1..4, shots1..256, players2..10, seeds0..2147483647. Inputmanifest1MiB/report8MiB. Unknown keys/types, nonfinite metrics, directory symlinks, foreign resume reports and missing artifacts rejected. Commands always reconstructed from validated config. Report schema1. No simultaneous workers may share output directories; cancellation kills every process group. Retry cannot trust commands/paths stored in report. HTML/CSV/Markdown escape data.

## Files and exact interfaces

`tools/scenarios.py`: `validate_manifest(value)->dict`, `expand_matrix(value)->list[dict]`, `select_cases(cases,includes,excludes)`, `run_matrix(manifest,root,binary,jobs=1,timeout=60,deadline=3600,record=False,verify=False,resume=False,retry_failed=False)->dict`. Entry configuration map,players,preset,seed,shots,bots; configdigest canonical SHA256. caseID digestprefix + repeatindex; record unique attempts under outputroot/cases/ID/attempt-N. root outside source or ROOT/build; no symlink components. Each case JSON summary and optional replay manifest checksums. Parent-owned report writes completed outcomes in planorder. Scheduler maxjobs and deadline; signal cancels worker groups. Godotvalidmaps read once duringrun audit. plan/validate noengine.

`tools/scenario_report.py`: `validate_report(value)->dict`, `summarize(report,filters={})`, `compare_reports(first,second,time_relative=.2,time_absolute=.1,strict=True)`, `to_csv`, `to_markdown`, `to_html`. Floatfinite validation, nearest-rankp95, metrics fromsummary.state.statistics. State digest uses canonical JSON excludingwalltime. Nondeterminism groups configdigest acrossrepeatcases. Compare missing/failure/state/shot/damage/timing independently, stableoutput.

`tools/scenarios.py` CLI subcommands plan/validate/run/summary/compare/validate-report/export, strictargparse. --manifest, --output-root, --jobs, --timeout, --deadline, --record-all, --verify-recordings, --resume, --retry-failed, --include/--exclude; comparison --time-relative/--time-absolute/--permissive. Export --format json/csv/markdown/html to explicit path. `tools/launch.py scenarios` delegates argv. Add `tools/scenarios/*.json` smoke/arena/bot manifests.

## Test/implementation steps

- [ ] `tools/test_scenarios.py`: schema, stableIDs/permutations, repeat/costcaps, plan argv/cwd, unknownargs. Observefail then implement parser/plan.
- [ ] Fakeengine fixtures: summaryvalidity, maxparallelism, failures/timeouts, attempts, verifiedresume/tamper, totaldeadline/cancellation. Implement executor and checksums with testable registry.
- [ ] Reportfixtures: aggregates, percentileedges, outcomes/unresolved, inventorynotnumericstats, repeatdiff, comparethresholds andadded/missing; escapedexports. Implement scenario_report.
- [ ] RealGodot2case smoke +replayverify in temp; deterministiccomparison ofsamecase. Addrunnerregistry once.
- [ ] CLI foreigncwd, safeoutputs/aliaspaths, reportboundedloads, defaultmanifests; documentation commands validated.
- [ ] Independentreview and per50ID evidence, fullsuite. No actualplatformexport implied.

Exact50 acceptance rows in mastermanifest groupscenarios. Root keeps ledger in acceptance report and checkboxes rather than per-task commits while shared integration is incomplete.
