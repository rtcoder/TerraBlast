#!/usr/bin/env python3
"""Run a real server and two real gameplay clients; no mock transports."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

binary = os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot')
with tempfile.TemporaryDirectory(prefix='terrablast-network-') as tmp:
    root = Path(tmp)
    processes = []
    files = []
    def start(name, args):
        output = (root / f'{name}.out').open('w')
        files.append(output)
        process = subprocess.Popen([binary, '--headless', '--log-file', str(root / f'{name}.log'), '--path', 'game', *args], stdout=output, stderr=subprocess.STDOUT)
        processes.append(process)
        return process
    try:
        server = start('server', ['--', '--mode', 'server', '--port', '19175'])
        deadline = time.monotonic() + 10
        while 'server ready' not in (root / 'server.out').read_text():
            if server.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError((root / 'server.out').read_text())
            time.sleep(.05)
        clients = [start(f'client-{i}', ['--script', 'tests/integration/network_process_client.gd', '--', '--mode', 'client', '--port', '19175']) for i in range(2)]
        for client in clients:
            client.wait(timeout=20)
        for i, client in enumerate(clients):
            output = (root / f'client-{i}.out').read_text()
            print(output)
            if client.returncode or 'ERROR:' in output or 'leaked at exit' in output or 'Network process client passed' not in output:
                raise RuntimeError('Separate-process client failed')
        server_output = (root / 'server.out').read_text()
        if 'ERROR:' in server_output:
            raise RuntimeError(server_output)
        print('Separate-process server + two gameplay clients passed')
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
        for process in processes:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        for file in files:
            file.close()
