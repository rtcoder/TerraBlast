#!/usr/bin/env python3
"""Cwd-independent launcher: launch.py client|local-dev|server|simulate|replay|library|test|doctor [arguments].
Simulation: --bots easy|normal --record PATH --output PATH --map MAP --shots N.
Arguments are forwarded separately; quote paths containing spaces.
"""
import sys
from pathlib import Path
import subprocess
import tempfile
from devtools import ROOT, godot_binary

def main():
    args = sys.argv[1:]
    if not args or args[0] in ('-h', '--help'):
        print(__doc__)
        return 0
    mode = args.pop(0)
    if mode in ('test', 'doctor', 'release'):
        script = {'test':'run_tests.py','doctor':'doctor.py','release':'release.py'}[mode]
        return subprocess.call([sys.executable, str(ROOT / 'tools' / script), *args], cwd=ROOT)
    if mode not in ('client', 'server', 'local-dev', 'simulate', 'replay', 'library', 'audit-maps', 'analyze-replay', 'compare-replays'):
        print('Unknown launcher mode: ' + mode, file=sys.stderr)
        return 2
    try:
        command = [godot_binary(), '--path', str(ROOT / 'game'), '--log-file', str(Path(tempfile.mkdtemp(prefix='terrablast-launch-')) / 'godot.log')]
    except FileNotFoundError as error:
        print(error, file=sys.stderr)
        return 2
    if mode in ('server', 'simulate', 'replay', 'library', 'audit-maps', 'analyze-replay', 'compare-replays'):
        command.append('--headless')
    command += ['--', '--mode', mode, *[arg for arg in args if arg != '--dry-run']]
    if '--dry-run' in args:
        import json
        print(json.dumps({'command':command,'cwd':str(ROOT)}))
        return 0
    return subprocess.call(command, cwd=ROOT)

if __name__ == '__main__':
    sys.exit(main())
