"""Real server startup and strict lobby flag checks, including external cwd."""
import socket
import subprocess
import sys
import tempfile
from devtools import ROOT, godot_binary


def run(directory, *args, code=0, launcher=True):
    if launcher:
        command = [sys.executable, str(ROOT / 'tools/launch.py'), *args]
    else:
        command = [godot_binary(), '--headless', '--path', str(ROOT / 'game'),
                   '--log-file', str(directory / 'cli.log'), '--', *args]
    result = subprocess.run(command, cwd=directory, capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    assert result.returncode == code, (args, result.returncode, output)
    assert 'SCRIPT ERROR' not in output, output
    return output


def main():
    from pathlib import Path
    with tempfile.TemporaryDirectory(prefix='terrablast-lobby-cli-') as temporary:
        directory = Path(temporary)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.bind(('127.0.0.1', 0))
            port = str(probe.getsockname()[1])
        for count in (2, 4, 10):
            for lobby in (False, True):
                flags = ['--lobby'] if lobby else []
                output = run(directory, 'server', '--map', 'canyon_bridge', '--preset', 'quick',
                             '--port', port, '--players', str(count), '--smoke', *flags)
                for expected in (f'core players={count}', f'capacity={count}', 'map=canyon_bridge',
                                 'preset=quick', 'mode=lobby' if lobby else 'mode=auto'):
                    assert expected in output, output
        output = run(directory, 'server', '--port', port, '--smoke')
        assert 'capacity=2' in output and 'mode=auto' in output, output
        for flags in (['--players', '1'], ['--players', '11'], ['--players', 'no'],
                      ['--players'], ['--lobby', 'true'], ['--lobby', '--lobby']):
            output = run(directory, 'server', '--port', port, '--smoke', *flags, code=2)
            assert 'server ready' not in output
        for mode in ('local-dev', 'client', 'simulate', 'replay', 'audit-maps'):
            output = run(directory, '--mode', mode, '--lobby', code=2, launcher=False)
            assert '--lobby requires --mode server' in output, output
        help_text = run(directory, 'simulate', '--help')
        assert 'canyon_bridge' in help_text and '--lobby' in help_text
    print('Lobby CLI: 2/4/10 slots, lobby/auto, default, invalid flags and external cwd passed')


if __name__ == '__main__':
    main()
