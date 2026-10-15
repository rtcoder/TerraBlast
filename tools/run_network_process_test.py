#!/usr/bin/env python3
"""Exercise a real server and two gameplay clients, with bounded durable logs."""
import argparse
import signal
from pathlib import Path
import socket
import tempfile
import time
from devtools import ROOT, godot_binary, spawn, stop

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--timeout', type=float, default=30)
    parser.add_argument('--log-dir', type=Path)
    args = parser.parse_args()
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    if not 0 <= args.port <= 65535:
        parser.error('port must be 0..65535')
    port = args.port
    if not port:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
    directory = args.log_dir or Path(tempfile.mkdtemp(prefix='terrablast-network-'))
    directory.mkdir(parents=True, exist_ok=True)
    processes, files = [], []
    def start(name, arguments):
        output = (directory / (name + '.out')).open('w')
        files.append(output)
        process = spawn([godot_binary(), '--headless', '--log-file', str(directory / (name + '.log')), '--path', str(ROOT / 'game'), *arguments], stdout=output, stderr=-2)
        processes.append(process)
        return process
    def read(name):
        path = directory / (name + '.out')
        if path.stat().st_size > 8 * 1024 * 1024:
            raise RuntimeError(name + ': log limit exceeded')
        return path.read_text(errors='replace')
    try:
        server = start('server', ['--', '--mode', 'server', '--port', str(port)])
        deadline = time.monotonic() + args.timeout
        while 'server ready' not in read('server'):
            if server.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError('Server did not become ready: ' + read('server'))
            time.sleep(.05)
        clients = [start('client-' + str(i), ['--script', 'tests/integration/network_process_client.gd', '--', '--mode', 'client', '--port', str(port)]) for i in range(2)]
        while any(client.poll() is None for client in clients):
            for name in ['server', 'client-0', 'client-1']:
                read(name)
            if time.monotonic() >= deadline:
                raise RuntimeError('Separate-process clients timed out')
            time.sleep(.05)
        for i, client in enumerate(clients):
            output = read('client-' + str(i))
            if client.returncode or 'ERROR:' in output or 'leaked at exit' in output or 'Network process client passed' not in output:
                raise RuntimeError(output)
        if 'ERROR:' in read('server'):
            raise RuntimeError(read('server'))
        print('Separate-process server + two gameplay clients passed')
        return 0
    finally:
        for process in processes:
            stop(process)
        for output in files:
            output.close()
        print('Network logs: ' + str(directory.resolve()))

if __name__ == '__main__':
    raise SystemExit(main())
