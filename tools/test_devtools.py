#!/usr/bin/env python3
"""Regression tests for portable process management, CLI and map auditing."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from devtools import ROOT, godot_binary, run_case

class DevtoolsTests(unittest.TestCase):
    def test_timeout_and_report_record(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = run_case('hang', [sys.executable, '-c', 'import time; time.sleep(60)'], tmp, .1)
            self.assertEqual(result['status'], 'timeout')
            self.assertLess(result['duration_seconds'], 3)
            self.assertTrue(Path(result['log_path']).exists())
            json.dumps(result)

    @unittest.skipIf(os.name == 'nt', 'POSIX process group assertion')
    def test_timeout_kills_descendants(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / 'escaped'
            child = 'import time,pathlib;time.sleep(1.5);pathlib.Path(' + repr(str(marker)) + ').touch()'
            code = 'import subprocess,sys,time;subprocess.Popen([sys.executable,"-c",' + repr(child) + ']);time.sleep(60)'
            self.assertEqual(run_case('tree', [sys.executable, '-c', code], tmp, .15)['status'], 'timeout')
            import time
            time.sleep(1.6)
            self.assertFalse(marker.exists())

    def test_missing_binary_doctor_and_suite_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, GODOT_BIN=str(Path(tmp) / 'missing'))
            result = subprocess.run([sys.executable, str(ROOT / 'tools/doctor.py')], cwd=tmp, env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 1)
            self.assertFalse(json.loads(result.stdout)['checks']['godot']['ok'])
            report = Path(tmp) / 'report.json'
            result = subprocess.run([sys.executable, str(ROOT / 'tools/run_tests.py'), '--report', str(report)], cwd=tmp, env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 1)
            document = json.loads(report.read_text())
            self.assertFalse(document['ok'])
            self.assertEqual(document['schema_version'], 1)
            self.assertTrue(document['tests'])

    def cli(self, *args):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run([godot_binary(), '--headless', '--path', str(ROOT / 'game'), '--log-file', str(Path(tmp) / 'godot.log'), '--', *args], cwd=tmp, capture_output=True, text=True, timeout=30)
            self.assertNotIn('SCRIPT ERROR:', result.stdout + result.stderr)
            return result

    def json_cli(self, *args):
        result = self.cli(*args)
        return result, json.loads(next(line for line in result.stdout.splitlines() if line.startswith('{')))

    def test_help_version(self):
        for flag, expected in [('--help', '--preset'), ('--version', 'TerraBlast 0.0.1 / Godot')]:
            result = self.cli(flag)
            self.assertEqual(result.returncode, 0)
            self.assertIn(expected, result.stdout)
            self.assertNotIn('server ready', result.stdout)

    def test_map_audit_and_invalid_fixtures(self):
        result, document = self.json_cli('--list-maps')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(document['maps']), len(list((ROOT / 'game/maps').glob('*.toml'))))
        self.assertTrue({'twin_forts', 'two_islands', 'canyon_bridge'} <= {row['id'] for row in document['maps']})
        self.assertTrue(all(row['spawn_count'] == row['capacity'] == 10 and not row['errors'] for row in document['maps']))
        self.assertTrue(all(row['theme'] and row['teams'] == [1, 2] for row in document['maps']))
        with tempfile.TemporaryDirectory() as tmp:
            fixtures = ['id = "bad"\nsize = [0, 2, 2]', 'id = "bad"\nsize = [4,4,4]\n[[spawns]]\nposition = [1,1,1]\nteam = 1', 'this is not toml']
            for index, content in enumerate(fixtures):
                (Path(tmp) / (str(index) + '.toml')).write_text(content)
            result, document = self.json_cli('--mode', 'audit-maps', '--maps-dir', tmp)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(len(document['maps']), len(fixtures))
            self.assertTrue(all(row['errors'] for row in document['maps']))
        result, document = self.json_cli('--list-maps', '--maps-dir', '/missing-map-directory')
        self.assertEqual(result.returncode, 2)
        self.assertFalse(document['ok'])

    def test_summary_file_and_presets(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'summary.json'
            for preset in ['classic', 'quick', 'training']:
                result, document = self.json_cli('--mode', 'simulate', '--shots', '1', '--preset', preset, '--output', str(target))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(json.loads(target.read_text()), document)
            result = self.cli('--mode', 'simulate', '--shots', '1', '--output', str(Path(tmp) / 'missing/summary.json'))
            self.assertEqual(result.returncode, 2)
            self.assertFalse(list(Path(tmp).glob('*.tmp-*')))
        self.assertEqual(self.cli('--preset', 'invalid').returncode, 2)

    def test_replay_errors(self):
        self.assertEqual(self.cli('--mode', 'replay').returncode, 2)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad.json'
            for content in ['{', '{"version":1}']:
                path.write_text(content)
                result, document = self.json_cli('--mode', 'replay', '--replay', str(path))
                self.assertEqual(result.returncode, 2)
                self.assertFalse(document['ok'])

    def test_verified_replay_and_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'recording.json'
            result = subprocess.run([godot_binary(), '--headless', '--path', str(ROOT / 'game'), '--log-file', str(Path(tmp) / 'fixture.log'), '--script', 'tests/unit/devtools_next_tests.gd', '--', '--output', str(path)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result, document = self.json_cli('--mode', 'replay', '--replay', str(path))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(document['ok'])
            archive = json.loads(path.read_text())
            archive['expected_hash'] = '0' * 64
            path.write_text(json.dumps(archive))
            result, document = self.json_cli('--mode', 'replay', '--replay', str(path))
            self.assertEqual(result.returncode, 2)
            self.assertEqual(document['reason'], 'hash_mismatch')

    def test_launcher_external_cwd(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tools/launch.py'), 'simulate', '--version'], cwd=tempfile.gettempdir(), capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('TerraBlast', result.stdout)

if __name__ == '__main__':
    unittest.main()
