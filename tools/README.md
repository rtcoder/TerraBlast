# Portable development commands

Python 3 standard library only. Every entry point resolves the repository from its own location; it can be invoked from another working directory. Godot resolution: explicit `GODOT_BIN`, then `godot` / `godot4` on PATH, then the macOS application path. An invalid explicit override fails instead of silently selecting another engine. Arguments are passed as arrays, without shell evaluation.

```sh
python3 tools/launch.py local-dev --map two_islands --preset quick
python3 tools/launch.py client --host 127.0.0.1 --port 19170
python3 tools/launch.py server --port 19170 --preset training
python3 tools/launch.py simulate --shots 6 --seed 123 --output /tmp/summary.json
python3 tools/launch.py simulate --help
python3 tools/launch.py simulate --version
python3 tools/launch.py simulate --list-maps
python3 tools/launch.py replay --replay /tmp/recording.json
python3 tools/launch.py doctor --nakama
python3 tools/launch.py test --timeout 90 --log-dir /tmp/terrablast-results
python3 tools/run_network_process_test.py --port 19389 --timeout 30
```

Map audit uses the production TOML parser, structural validator, builder and spawn-ground validator. `--list-maps` audits every `.toml` in `res://maps`, returning id, name, dimensions, theme, sorted team IDs, capacity (up to 10), spawn count and errors. For fixtures or another directory, pass `--maps-dir /absolute/directory`. `--mode audit-maps` is an equivalent explicit mode. Invalid maps, missing/empty directories and invalid CLI arguments exit 2.

Simulation summary files use a temporary sibling and atomic rename. Replay mode verifies the bounded versioned archive and final state hash before reporting success. Utility modes run no gameplay scene or network listener.

The test runner retains stdout and Godot logs, with a versioned JSON report even on failure. Each record contains name, status, duration and log path. Timeout terminates the process tree (POSIX process group; Windows taskkill tree). Excessive output also terminates the process. Network tests choose an available local UDP port by default; pass `--port` to pin one. Their log directory is printed and retained after failure. `RUN_NAKAMA_TESTS=1` and `RUN_RENDER_TESTS=1` opt into backend and windowed checks; CI runs offline headless tests separately.

`game/export_presets.cfg` contains macOS, Windows, Linux desktop and dedicated Linux server configurations, including TOML resources. Dedicated builds default to server mode. These presets have been parsed and checked locally; producing platform binaries still requires Godot 4.6.2 export templates and running actual exports. No exported binaries or cross-platform runtime verification are claimed. Build destinations are under `build/`.

## Bot simulation and recordings

```sh
python3 tools/launch.py simulate --map twin_forts --bots easy --shots 6 --record '/tmp/bot replay.json' --output '/tmp/bot summary.json'
python3 tools/launch.py simulate --map two_islands --bots normal --shots 6
python3 tools/launch.py replay --replay '/tmp/bot replay.json'
python3 tools/test_bot_cli.py
```

`--bots easy|normal` uses the same deterministic, bounded shot planner as local solo play, for both teams. Normal considers more candidate shots; bots do not move. Without this flag, simulation retains its seeded shooter (`--seed 123`). JSON summaries retain `state` and `terrain_hash`, and add `bot_difficulty` (empty for the seeded shooter) and `bot_decisions` (accepted bot shots, zero without bots).

`--record PATH` captures all accepted shots from the simulation's initial state and writes a versioned ReplayArchive. Use a different path for `--output`: identical normalized paths are rejected. Replay mode runs in a separate process and returns `ok: true, reason: verified` only after checking the final state hash. Archives are bounded; a recording that exceeds the recorder's limit fails export rather than silently saving a truncated replay.

Unknown difficulty, missing values, duplicate flags, `--bots`/`--record` outside simulation, or an unwritable output path return exit code 2. Parent directories must already exist. The launcher forwards each argument independently, including paths with spaces, and works from any current directory. The suite automatically discovers unit `*tests.gd` and integration `*next_tests.gd` once, and includes `test_bot_cli.py` and `test_lobby_cli.py` with the usual logs and report.

Graphical solo, checkpoint (`user://last_session.json`) and action replay (`user://last_replay.json`) controls are described in the [main README](../README.md#solo-saves-and-replay). They are local-only; they cannot save or replace an authoritative online match.

## Dedicated match lobby

```sh
python3 tools/launch.py server --map canyon_bridge --players 4 --lobby --port 19170
python3 tools/launch.py server --map canyon_bridge --players 10 --lobby --port 19171
python3 tools/launch.py server --map canyon_bridge --players 10 --lobby --smoke
python3 tools/test_lobby_cli.py
```

All modes accept the nine registered arenas listed below. The server defaults to 2 players; `--players 2..10` sets its required capacity. Startup prints the map, preset, actual player count, capacity and `lobby`/`auto` mode. Insufficient spawns fail before binding a port. `--lobby` is a server-only boolean flag with no value; duplicate flags and invalid contexts exit 2.

F2 selects the host and port. F7 shows the match roster, edits your name before start and toggles Ready. Lobby mode waits for the full connected and ready roster. Any disconnect pauses gameplay until full capacity reconnects; F4 retries a reserved slot. After match end the full roster must vote for rematch, then select Ready again. Without `--lobby`, a full roster starts automatically. The default 2-player auto mode remains compatible.

These are manually allocated Godot match servers. Nakama authentication, lobbies and matchmaking remain separate metagame services; no automatic server provisioning is implemented.

## Selecting and resuming tests

```sh
python3 tools/run_tests.py --list --include '*250*'
python3 tools/run_tests.py --include '*tests' --exclude '*network*' --fail-fast --log-dir /private/tmp/tb-tests --junit /private/tmp/tb-tests/junit.xml
python3 tools/run_tests.py --rerun-failed /private/tmp/tb-tests/report.json --log-dir /private/tmp/tb-retry --jsonl
python3 tools/doctor.py --templates --output /private/tmp/tb-doctor.json
```

`--include` and `--exclude` accept repeated case-sensitive globs. An empty selection is an error. Retry reports supply trusted test names only, never executable commands. Timeouts must be finite and within `(0,3600]` seconds. Each invocation retains a separate attempt directory; JSON is atomically updated after each case, and interruption retains partial results. JSONL emits one result per case. Optional Nakama/render checks are identified explicitly in the report.

## Local release artifacts

```sh
python3 tools/launch.py release plan --platform linux --platform server
python3 tools/release.py build --platform server --timeout 300
python3 tools/release.py verify build/server
python3 tools/release.py package build/server build/TerraBlast-server.zip
# The context must be the repository root, not server/:
docker build -f server/Dockerfile -t terrablast-server .
docker run --rm -p 19170:19170/udp terrablast-server --port 19170
```

Build requires a Godot 4.6.2-or-newer patch in the 4.6 release line and matching installed export templates. Missing templates fail preflight; nothing is downloaded automatically. `plan` needs no engine. `build` invokes the selected export presets with bounded execution and per-platform logs; a non-empty binary is required before a manifest is written. Manifests cover all outputs, including sidecar PCK files, with sizes and SHA256 hashes. `verify` rejects missing, changed, unlisted or linked files. `package` creates a deterministic ZIP and updates `SHA256SUMS`. Existing artifacts require explicit `--replace`; build replacement is limited to a previously verified manifest. Use canonical paths without symlink components (on macOS, `/private/tmp` rather than `/tmp`).

The container runs as UID10001 with writable user-data under `/home/terrablast`; only prepared server outputs enter its build context. Runtime arguments follow the existing entrypoint. Platform exports and Docker execution require the corresponding external tools/templates; offline tests use fake exporters to verify failure handling and package integrity.

## Replay analysis and library inspection

```sh
python3 tools/launch.py audit-maps
python3 tools/launch.py local-dev --map ballistics_range --dry-run
python3 tools/launch.py analyze-replay --replay /private/tmp/replay.json --output /private/tmp/analysis.json
python3 tools/launch.py analyze-replay --replay /private/tmp/replay.json --analysis-format shots --output /private/tmp/shots.csv
python3 tools/launch.py compare-replays --replay /private/tmp/first.json --replay-other /private/tmp/second.json
python3 tools/launch.py library --query 'practice' --sort title
python3 tools/launch.py library --library-health
```

Analysis verifies the archive and reconstructs a private runner. It reports players, weapons, shot bookmarks, turn transitions, terrain changes and eliminations; simulation time comes from recorded ticks. `--analysis-format players|shots` exports CSV, including formula-safe quoted text. Comparison reports initial/final hashes and outcome differences. An output cannot replace either input archive. Library inspection supports `--entry ID`, query/sort and storage diagnostics without opening a gameplay scene.

The registry now contains nine arenas: `twin_forts`, `two_islands`, `canyon_bridge`, `ballistics_range`, `terraced_quarry`, `split_pass`, `bunker_court`, `ring_island`, `three_lane_foundry`. Audit output includes supported player counts.

## Bounded server operation

Server-only flags: `--reservation-seconds 1..300`, `--hello-seconds 1..30`, `--packet-rate 60..1000`, `--byte-rate 8192..1048576`, `--snapshot-chunks 1..64`, `--snapshot-bytes 65536..8388608`, `--receive-bytes 8192..4194304`. `--shutdown-after SECONDS` (0.1..3600) requests graceful shutdown. `--server-report /absolute/path.json` atomically records diagnostics at shutdown; its existing parent must be outside the project and contain no symlink components. Reports omit credentials and tokens.
