"""Portable process primitives shared by launchers and diagnostics (stdlib only)."""
import math
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

def valid_timeout(value):
    result = float(value)
    if not math.isfinite(result) or not 0 < result <= 3600:
        raise ValueError('timeout must be finite and in (0, 3600]')
    return result


def bounded_text(path, limit=8 * 1024 * 1024):
    with Path(path).open('rb') as source:
        return source.read(limit).decode('utf-8', errors='replace')


def run_case(name, command, directory, timeout=60):
    timeout = valid_timeout(timeout)
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    log = directory / (name + '.out')
    started = time.monotonic()
    status, code, reason = 'failed', None, ''
    with log.open('w') as output:
        process = None
        try:
            process = spawn(command, stdout=output, stderr=subprocess.STDOUT)
            deadline = started + timeout
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    status = 'timeout'
                    reason = 'deadline_exceeded'
                    break
                if log.stat().st_size > 8 * 1024 * 1024:
                    status = 'log_limit'
                    reason = 'output_limit_exceeded'
                    break
                time.sleep(.02)
            if process.poll() is not None:
                code = process.returncode
                status = 'passed' if code == 0 else 'failed'
                reason = ('signal_' + str(-code)) if code < 0 else ('' if code == 0 else 'nonzero_exit')
        except OSError as error:
            output.write(str(error))
            reason = "spawn_failed: " + str(error)
        finally:
            if process is not None:
                stop(process)
    if log.stat().st_size > 8 * 1024 * 1024:
        status, reason = 'log_limit', 'output_limit_exceeded'
    content = bounded_text(log)
    if status == 'passed' and ('SCRIPT ERROR:' in content or '\nERROR:' in content):
        status = 'failed'
        reason = 'engine_error'
    return {'name': name, 'status': status, 'reason': reason, 'exit_code': code, 'duration_seconds': round(time.monotonic() - started, 3), 'log_path': str(log.resolve())}
