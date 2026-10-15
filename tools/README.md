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
