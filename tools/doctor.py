#!/usr/bin/env python3
"""Report required local prerequisites; optional Nakama never blocks offline work."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import urllib.request
from devtools import ROOT, godot_binary

def main():
    checks = {}
    try:
        binary = godot_binary()
        version = subprocess.run([binary, '--version'], capture_output=True, text=True, timeout=10)
        checks['godot'] = {'ok': version.returncode == 0, 'version': version.stdout.strip()}
    except (OSError, subprocess.TimeoutExpired) as error:
        checks['godot'] = {'ok': False, 'reason': str(error)}
    checks['project'] = {'ok': (ROOT / 'game/project.godot').is_file()}
    maps = sorted((ROOT / 'game/maps').glob('*.toml'))
    checks['maps'] = {'ok': bool(maps), 'count': len(maps)}
    if checks['godot']['ok']:
        try:
            with tempfile.TemporaryDirectory(prefix='terrablast-doctor-') as tmp:
                audit = subprocess.run([binary, '--headless', '--path', str(ROOT / 'game'), '--log-file', str(Path(tmp) / 'audit.log'), '--', '--list-maps'], capture_output=True, text=True, timeout=30)
                data = json.loads(next(line for line in audit.stdout.splitlines() if line.startswith('{')))
                checks['maps'] = {'ok': audit.returncode == 0 and data['ok'], 'count': len(data['maps'])}
        except (OSError, subprocess.TimeoutExpired, ValueError, StopIteration, KeyError):
            checks['maps'] = {'ok': False, 'reason': 'map_audit_failed'}
    if '--nakama' in sys.argv:
        try:
            with urllib.request.urlopen('http://127.0.0.1:7350/healthcheck', timeout=2) as response:
                checks['nakama'] = {'ok': response.status == 200, 'optional': True}
        except OSError:
            checks['nakama'] = {'ok': False, 'optional': True}
    ok = all(item['ok'] for item in checks.values() if not item.get('optional'))
    print(json.dumps({'ok': ok, 'checks': checks}))
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main())
