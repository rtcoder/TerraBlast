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

Map audit uses the production TOML parser, structural validator, builder and spawn-ground validator. `--list-maps` audits every `.toml` in `res://maps`, returning name, dimensions, spawn count and errors. For fixtures or another directory, pass `--maps-dir /absolute/directory`. `--mode audit-maps` is an equivalent explicit mode. Invalid maps, missing/empty directories and invalid CLI arguments exit 2.

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

Unknown difficulty, missing values, duplicate flags, `--bots`/`--record` outside simulation, or an unwritable output path return exit code 2. Parent directories must already exist. The launcher forwards each argument independently, including paths with spaces, and works from any current directory. The suite automatically discovers unit `*tests.gd` and integration `*next_tests.gd` once, and includes `test_bot_cli.py` with the usual logs and report.

Graphical solo, checkpoint (`user://last_session.json`) and action replay (`user://last_replay.json`) controls are described in the [main README](../README.md#solo-saves-and-replay). They are local-only; they cannot save or replace an authoritative online match.
