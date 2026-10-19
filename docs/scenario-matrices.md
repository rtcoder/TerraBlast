# Scenario matrices

Run from any working directory with Python 3.10+ and Godot 4.6.2 (`GODOT_BIN` overrides discovery):

```sh
python3 tools/launch.py scenarios validate --manifest tools/scenarios/smoke.json
python3 tools/launch.py scenarios plan --manifest tools/scenarios/arenas.json
python3 tools/launch.py scenarios run --manifest tools/scenarios/smoke.json --output-root build/scenario-smoke --jobs 2 --verify-recordings
python3 tools/launch.py scenarios run --manifest tools/scenarios/smoke.json --output-root build/scenario-smoke --resume --verify-recordings
python3 tools/launch.py scenarios summary build/scenario-smoke/report.json
python3 tools/launch.py scenarios export build/scenario-smoke/report.json --format html --output build/scenario-smoke/report.html
python3 tools/launch.py scenarios compare build/baseline/report.json build/candidate/report.json --time-relative .2 --time-absolute .1
```

Manifest version 1 requires `maps`, `players`, `presets`, `seeds`, `shots`, `bots`; optional `repeats` defaults to 1. Axes are sorted/deduplicated. Limits: 128 cases, players 2/4/6/8/10, shots 1–256, seed 0–2147483647, repeats 1–10. Presets are classic/quick/training; bots seeded/easy/normal. Registered map IDs are checked again using engine audit before execution. Plan runs without Godot, returns argv and upper shot cost. `--include`/`--exclude` select ID globs; quote wildcards. Empty selection is an error.

`smoke.json` repeats one short case twice, `arenas.json` covers nine arenas, `bots.json` compares two planners. `--jobs` is bounded to 1–4; per-case `--timeout` defaults to 60 seconds and total `--deadline` to 3600. Both must be finite and positive, at most 3600. SIGINT/SIGTERM cancels workers and kills their process groups. Timed-out and skipped cases remain in the ordered report. Reports are atomically replaced after each result. Each attempt retains separate logs; a root lock prevents simultaneous runs into the same directory. Remove a stale `.running` lock only after confirming its process has ended.

Output directories must be empty or carry this tool's marker. Source directories and symlink components are rejected; use canonical `/private/tmp` on macOS. `build/` is an allowed repository output root. `--record-all` saves archives, `--verify-recordings` also executes replay verification. Resume and retry-failed reuse only passed cases with matching configuration, required artifacts, sizes/SHA256, and summary contents. Commands are always reconstructed from the manifest. A foreign manifest is rejected. Changing a report cannot supply executable arguments.

Reports include engine, platform, Git revision, timestamp, configuration digests, result states and artifact provenance. `summary --status passed --map two_islands` filters without modifying the source. Aggregates group by map/preset/player count, sum player statistics and terrain deltas, and retain terrain hashes as identities. Timing uses nearest-rank p95. Repeated configurations compare canonical state and terrain, ignoring elapsed time.

Comparison joins IDs and reports added/removed/matched cases and state, damage, accepted-shot and timing changes. Missing cases fail in strict mode; `--permissive` only relaxes missing cases. New failed cases always fail. Timing fails when **both** absolute and relative tolerances are exceeded, avoiding division by zero. Environment and manifest differences are explicit metadata. Exit codes: 0 success, 1 run/regression failure, 2 invalid input/preflight. Redirect compare stdout to save its versioned JSON.

Exports: JSON, CSV with spreadsheet formula protection, escaped Markdown, offline HTML with status filter. Inputs are bounded to 1 MiB manifests / 8 MiB reports. Export cannot overwrite its report or source tree. Reports and artifacts are local diagnostic data, not signed provenance or authentication credentials.
