#!/usr/bin/env python3
"""Bounded headless suite with durable per-test logs and JSON report."""
import argparse
import signal
import json
import os
from pathlib import Path
import sys
import tempfile
from devtools import ROOT, godot_binary, run_case

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=float, default=90)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--log-dir', type=Path)
    args = parser.parse_args()
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    directory = args.log_dir or Path(tempfile.mkdtemp(prefix='terrablast-tests-'))
    directory.mkdir(parents=True, exist_ok=True)
    report = args.report or directory / 'report.json'
    results = []
    try:
        binary = godot_binary()
        scripts = sorted((ROOT / 'game/tests/unit').glob('*tests.gd'))
        names = ['debug_scene_smoke', 'artillery_flow_tests', 'match_ui_tests', 'mvp_smoke', 'review_regressions', 'network_smoke', 'client50_tests', 'network50_tests']
        names += [p.stem for p in sorted((ROOT / 'game/tests/integration').glob('*next_tests.gd'))]
        if os.environ.get('RUN_NAKAMA_TESTS') == '1':
            names += ['nakama_smoke', 'nakama50_tests']
        scripts += [ROOT / 'game/tests/integration' / (name + '.gd') for name in dict.fromkeys(names)]
        commands = [(p.stem, [binary, '--headless', '--path', str(ROOT / 'game'), '--log-file', str(directory / (p.stem + '.log')), '--script', str(p)]) for p in scripts]
        commands.append(('server', [binary, '--headless', '--log-file', str(directory / 'server.log'), '--path', str(ROOT / 'game'), '--', '--mode', 'server', '--port', '19174', '--smoke']))
        if os.environ.get('RUN_RENDER_TESTS') == '1':
            commands.append(('render', [binary, '--log-file', str(directory / 'render.log'), '--path', str(ROOT / 'game'), '--script', 'tests/integration/mvp_smoke.gd']))
        for script in ['test_devtools.py', 'run_network_process_test.py', 'test_simulation_cli.py', 'test_bot_cli.py']:
            commands.append((Path(script).stem, [sys.executable, str(ROOT / 'tools' / script)]))
        for name, command in commands:
            result = run_case(name, command, directory, args.timeout)
            results.append(result)
            print(f"{name}: {result['status']} ({result['duration_seconds']}s)", flush=True)
            if result['status'] != 'passed':
                print(Path(result['log_path']).read_text(errors='replace')[-12000:])
    except (OSError, KeyboardInterrupt) as error:
        results.append({'name': 'suite', 'status': 'failed', 'reason': str(error), 'duration_seconds': 0, 'log_path': ''})
    finally:
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(json.dumps({'schema_version': 1, 'ok': bool(results) and all(r['status'] == 'passed' for r in results), 'tests': results}, indent=2))
        print('Report: ' + str(report.resolve()))
    return 0 if results and all(r['status'] == 'passed' for r in results) else 1

if __name__ == '__main__':
    sys.exit(main())
