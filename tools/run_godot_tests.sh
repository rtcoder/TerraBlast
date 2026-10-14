#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

"$GODOT_BIN" --headless --log-file /tmp/terrablast-tests.log --path game --script tests/unit/core_tests.gd
"$GODOT_BIN" --headless --log-file /tmp/terrablast-tests.log --path game --script tests/integration/debug_scene_smoke.gd

"$GODOT_BIN" --headless --log-file /tmp/terrablast-artillery-tests.log --path game --script tests/integration/artillery_flow_tests.gd

"$GODOT_BIN" --headless --log-file /tmp/terrablast-mvp-tests.log --path game --script tests/unit/mvp_tests.gd

"$GODOT_BIN" --headless --log-file /tmp/terrablast-ui-tests.log --path game --script tests/integration/match_ui_tests.gd

"$GODOT_BIN" --headless --log-file /tmp/terrablast-network-tests.log --path game --script tests/integration/network_smoke.gd
"$GODOT_BIN" --headless --log-file /tmp/terrablast-server-tests.log --path game -- --mode server --port 19174 --smoke
