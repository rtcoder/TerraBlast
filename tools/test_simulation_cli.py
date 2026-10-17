"""Exercise public CLI including deterministic scenarios on all three arenas."""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
from devtools import godot_binary
GODOT = godot_binary()

def run(*args):
    return subprocess.run([GODOT, '--headless', '--path', str(ROOT / 'game'), '--log-file', '/tmp/terrablast-cli.log', '--', *args], capture_output=True, text=True, timeout=30)

for arena in ('twin_forts', 'two_islands', 'canyon_bridge'):
    results = []
    for _ in range(2):
        result = run('--mode', 'simulate', '--map', arena, '--shots', '6', '--seed', '123')
        assert result.returncode == 0, result.stdout + result.stderr
        assert 'SCRIPT ERROR' not in result.stdout + result.stderr
        results.append(json.loads(next(line for line in result.stdout.splitlines() if line.startswith('{'))))
    assert results[0] == results[1], f'{arena}: nondeterministic scenario'
    assert results[0]['shots'] > 0 and results[0]['deltas'] > 0
for args in (('--mode', 'typo'), ('--port', '99999'), ('--map', 'missing'), ('--players', '0')):
    result = run(*args)
    assert result.returncode == 2, result.stdout + result.stderr
print('CLI: deterministic scenarios on all three arenas and invalid-argument exits passed')
