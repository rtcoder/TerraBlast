"""Portable process primitives shared by launchers and diagnostics (stdlib only)."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]

def godot_binary():
    requested = os.environ.get('GODOT_BIN')
    candidates = [requested] if requested else ['godot', 'godot4', '/Applications/Godot.app/Contents/MacOS/Godot']
    for candidate in candidates:
        found = shutil.which(candidate)
        if found:
            return found
    raise FileNotFoundError('Godot not found; set GODOT_BIN to an executable')

def spawn(command, **kwargs):
    options = {'start_new_session': True} if os.name != 'nt' else {'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP}
    return subprocess.Popen(command, cwd=ROOT, **options, **kwargs)

def stop(process):
    if os.name == 'nt':
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
    else:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        # Descendants can outlive their parent, so always kill the group too.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    process.wait()

def run_case(name, command, directory, timeout=60):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    log = directory / (name + '.out')
    started = time.monotonic()
    status, code = 'failed', None
    with log.open('w') as output:
        process = None
        try:
            process = spawn(command, stdout=output, stderr=subprocess.STDOUT)
            deadline = started + timeout
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    status = 'timeout'
                    break
                if log.stat().st_size > 8 * 1024 * 1024:
                    status = 'log_limit'
                    break
                time.sleep(.02)
            if process.poll() is not None:
                code = process.returncode
                status = 'passed' if code == 0 else 'failed'
        except OSError as error:
            output.write(str(error))
        finally:
            if process is not None:
                stop(process)
    content = log.read_text(errors='replace')
    if status == 'passed' and ('SCRIPT ERROR:' in content or '\nERROR:' in content):
        status = 'failed'
    return {'name': name, 'status': status, 'exit_code': code, 'duration_seconds': round(time.monotonic() - started, 3), 'log_path': str(log.resolve())}
