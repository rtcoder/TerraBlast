#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
test_dir="$(mktemp -d /tmp/terrablast-tests.XXXXXX)"
run_case() {
  local name="$1"
  shift
  if ! "$GODOT_BIN" --log-file "$test_dir/$name.log" --path game "$@" >"$test_dir/$name.out" 2>&1; then
    cat "$test_dir/$name.out"
    return 1
  fi
  cat "$test_dir/$name.out"
  if rg -q 'SCRIPT ERROR:|^ERROR:' "$test_dir/$name.out"; then
    return 1
  fi
}
for script in unit/core_tests unit/mvp_tests integration/debug_scene_smoke integration/artillery_flow_tests integration/match_ui_tests integration/mvp_smoke integration/network_smoke; do
  run_case "${script##*/}" --headless --script "tests/$script.gd"
done
run_case server --headless -- --mode server --port 19174 --smoke
if [[ "${RUN_NAKAMA_TESTS:-0}" == 1 ]]; then
  run_case nakama --headless --script tests/integration/nakama_smoke.gd
fi
if [[ "${RUN_RENDER_TESTS:-0}" == 1 ]]; then
  run_case render --script tests/integration/mvp_smoke.gd
fi
rm -r "$test_dir"
