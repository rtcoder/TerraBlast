"""Regression tests for export containment and complete manifest coverage."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import release
import doctor
import run_tests
import io
import sys
import signal
from contextlib import redirect_stdout

class ReleaseContainmentTests(unittest.TestCase):
    def test_empty_platform_symlink_cannot_redirect_export(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();build=root/'build';outside=root/'outside'
            build.mkdir();outside.mkdir();(build/'server').symlink_to(outside,target_is_directory=True)
            templates=root/'templates';templates.mkdir();(templates/'linux_release.x86_64').write_bytes(b'template')
            rows=release.plan(['server'],build,'godot')
            def export(*args):
                Path(rows[0]['output']).write_bytes(b'export')
                return {'status':'passed'}
            with mock.patch.object(release,'run_case',side_effect=export):
                with self.assertRaises(ValueError):release.build(rows,'4.6.2.stable',templates,10)
            self.assertFalse(list(outside.iterdir()))

    def test_unlisted_directory_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();artifact=root/'artifact';artifact.mkdir()
            (artifact/'engine').write_bytes(b'engine')
            (artifact/'manifest.json').write_text(json.dumps(release.make_manifest(artifact,'server','4.6.2','rev')))
            (artifact/'escape').symlink_to(root,target_is_directory=True)
            self.assertFalse(release.verify_manifest(artifact)['ok'])

    def test_nested_manifest_is_not_silently_excluded(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();(root/'data').mkdir()
            (root/'engine').write_bytes(b'engine');(root/'data/manifest.json').write_text('nested asset')
            manifest=release.make_manifest(root,'server','4.6.2','rev')
            self.assertIn('data/manifest.json',{r['path'] for r in manifest['files']})
            (root/'manifest.json').write_text(json.dumps(manifest))
            (root/'data/manifest.json').write_text('tampered')
            self.assertFalse(release.verify_manifest(root)['ok'])

class RunnerAndDoctorTests(unittest.TestCase):
    def test_doctor_rejects_untracked_source_and_git_alias(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();repo=root/'repo';(repo/'game').mkdir(parents=True);(repo/'.git').mkdir()
            alias=root/'alias';alias.symlink_to(repo/'.git',target_is_directory=True)
            with mock.patch.object(doctor,'ROOT',repo):
                for target in [repo/'game/new.json',alias/'report.json']:
                    with self.assertRaises(ValueError):doctor.output_path(target)

    def invoke(self,root,side_effect,*flags):
        report=root/'report.json';stdout=io.StringIO();previous=signal.getsignal(signal.SIGTERM)
        try:
            with mock.patch.object(sys,'argv',['run_tests','--report',str(report),'--log-dir',str(root/'logs'),*flags]),mock.patch.object(run_tests,'godot_binary',return_value='godot'),mock.patch.object(run_tests,'build_cases',return_value=[('first',['fake']),('second',['fake'])]),mock.patch.object(run_tests,'run_case',side_effect=side_effect) as runner,redirect_stdout(stdout):
                code=run_tests.main()
            return code,json.loads(report.read_text()),stdout.getvalue(),runner.call_count
        finally:signal.signal(signal.SIGTERM,previous)

    def test_fail_fast_preserves_skipped_and_jsonl(self):
        with tempfile.TemporaryDirectory() as temp:
            result={'name':'first','status':'failed','duration_seconds':0,'log_path':''}
            code,report,output,calls=self.invoke(Path(temp),[result],'--fail-fast','--jsonl')
            self.assertEqual((code,calls),(1,1))
            self.assertEqual([r['status'] for r in report['tests']],['failed','skipped'])
            self.assertEqual([json.loads(line) for line in output.splitlines()],report['tests'])
            self.assertEqual(report['tests'][1]['reason'],'fail_fast')

    def test_incremental_report_survives_interrupt(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);calls=[]
            def execute(name,*args):
                current=json.loads((root/'report.json').read_text())
                self.assertEqual(current['status'],'running')
                if calls:
                    self.assertEqual(current['tests'][0]['status'],'passed')
                    raise KeyboardInterrupt
                calls.append(name)
                return {'name':name,'status':'passed','duration_seconds':0,'log_path':''}
            code,report,output,count=self.invoke(root,execute)
            self.assertEqual(code,1);self.assertEqual(count,2)
            self.assertEqual(report['status'],'finished');self.assertFalse(report['ok'])
            self.assertEqual([r['status'] for r in report['tests']],['passed','interrupted'])

if __name__=='__main__':unittest.main()
