#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

"$GODOT_BIN" --headless --log-file /tmp/terrablast-tests.log --path game --script tests/unit/core_tests.gd
"$GODOT_BIN" --headless --log-file /tmp/terrablast-tests.log --path game --script tests/integration/debug_scene_smoke.gd

"$GODOT_BIN" --headless --log-file /tmp/terrablast-artillery-tests.log --path game --script tests/integration/artillery_flow_tests.gd

"$GODOT_BIN" --headless --log-file /tmp/terrablast-mvp-tests.log --path game --script tests/unit/mvp_tests.gd
