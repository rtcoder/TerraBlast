#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

"$GODOT_BIN" --headless --path game --script tests/unit/core_tests.gd
"$GODOT_BIN" --headless --path game --script tests/integration/debug_scene_smoke.gd
