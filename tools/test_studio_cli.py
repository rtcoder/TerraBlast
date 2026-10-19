"""Replay Studio utility modes: real Godot executor with temporary verified fixtures."""
import json
import platform
from pathlib import Path
import subprocess
import tempfile
import unittest
from devtools import ROOT, godot_binary


class StudioCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='terrablast-studio-cli-', dir='/private/tmp' if platform.system() == 'Darwin' else '/tmp')
        cls.base = Path(cls.directory.name)
        cls.binary = godot_binary()
        result = cls.call('--studio-fixture', str(cls.base))
        if result.returncode:
            raise AssertionError(result.stdout)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    @classmethod
    def call(cls, *args):
        return subprocess.run([cls.binary, '--headless', '--log-file', str(cls.base / 'driver.log'), '--path', str(ROOT / 'game'), '--script', str(ROOT / 'game/tests/unit/studio_cli19_driver.gd'), '--', *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)

    def run_mode(self, mode, args):
        result = self.call(mode, json.dumps(args))
        lines = [line for line in result.stdout.splitlines() if line.startswith('{')]
        self.assertTrue(lines, result.stdout)
        return result.returncode, json.loads(lines[-1])

    def test_clip_verified_and_source_protected(self):
        """S44 verified CLI clip and protected input."""
        source = str(self.base / 'source.json')
        output = str(self.base / 'clip.json')
        code, data = self.run_mode('clip-replay', dict(source=source, start=1, end=3, output=output))
        self.assertEqual(code, 0, data)
        self.assertEqual(data['actions'], 2)
        before = Path(source).read_bytes()
        code, data = self.run_mode('clip-replay', dict(source=source, start=0, end=2, output=source))
        self.assertEqual(code, 2)
        self.assertEqual(Path(source).read_bytes(), before)
        code, data = self.run_mode('clip-replay', dict(source=source, start=4, end=4, output=str(self.base / 'empty.json')))
        self.assertEqual(code, 2)

    def test_detailed_diff_and_invalid_input(self):
        """S45 detailed CLI report and error exit."""
        source = str(self.base / 'source.json')
        code, data = self.run_mode('diff-replays', dict(source=source, second=source))
        self.assertEqual(code, 0, data)
        self.assertTrue(data['report']['configuration']['initial_equal'])
        self.assertEqual(data['report']['terrain']['count'], 0)
        code, data = self.run_mode('diff-replays', dict(source=source, second=str(self.base / 'missing.json')))
        self.assertEqual(code, 2)

    def test_verify_bundle_read_only(self):
        """S46 read-only CLI bundle verification."""
        before = sorted(p.name for p in self.base.iterdir())
        code, data = self.run_mode('verify-bundle', dict(bundle=str(self.base / 'portable.zip')))
        self.assertEqual(code, 0, data)
        self.assertEqual(len(data['entries']), 1)
        self.assertNotIn('envelopes', data)
        self.assertEqual(sorted(p.name for p in self.base.iterdir()), before)
        code, data = self.run_mode('verify-bundle', dict(bundle=str(self.base / 'source.json')))
        self.assertEqual(code, 2)

    def test_application_dispatch(self):
        """S44 S45 S46 application entry point dispatches all three modes."""
        modes = [
            ['--mode', 'clip-replay', '--replay', str(self.base / 'source.json'), '--clip-start', '1', '--clip-end', '3', '--output', str(self.base / 'dispatch-clip.json')],
            ['--mode', 'diff-replays', '--replay', str(self.base / 'source.json'), '--replay-other', str(self.base / 'source.json')],
            ['--mode', 'verify-bundle', '--bundle', str(self.base / 'portable.zip')],
        ]
        for arguments in modes:
            with self.subTest(mode=arguments[1]):
                result = subprocess.run([self.binary, '--headless', '--log-file', str(self.base / 'main.log'), '--path', str(ROOT / 'game'), '--', *arguments], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn('"ok":true', result.stdout.replace(' ', ''))


if __name__ == '__main__':
    unittest.main()
