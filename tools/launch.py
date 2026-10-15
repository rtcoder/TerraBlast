#!/usr/bin/env python3
"""Cwd-independent launcher: launch.py client|server|test|doctor [arguments]."""
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
    if mode in ('test', 'doctor'):
        script = 'run_tests.py' if mode == 'test' else 'doctor.py'
        return subprocess.call([sys.executable, str(ROOT / 'tools' / script), *args], cwd=ROOT)
    if mode not in ('client', 'server', 'local-dev', 'simulate', 'replay'):
        print('Unknown launcher mode: ' + mode, file=sys.stderr)
        return 2
    try:
        command = [godot_binary(), '--path', str(ROOT / 'game'), '--log-file', str(Path(tempfile.mkdtemp(prefix='terrablast-launch-')) / 'godot.log')]
    except FileNotFoundError as error:
        print(error, file=sys.stderr)
        return 2
    if mode in ('server', 'simulate', 'replay'):
        command.append('--headless')
    return subprocess.call(command + ['--', '--mode', mode, *args], cwd=ROOT)

if __name__ == '__main__':
    sys.exit(main())
