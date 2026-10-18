"""Offline contracts for delivery tools; no network or export templates required."""
import importlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from devtools import ROOT

class DeliveryTests(unittest.TestCase):
    def test_timeout_validation(self):
        from devtools import valid_timeout
        for value in ('nan','inf','0','-1','3601'):
            with self.assertRaises(ValueError): valid_timeout(value)
        self.assertEqual(valid_timeout('2.5'),2.5)

    def test_selection(self):
        from run_tests import select_cases
        cases=[('unit_one',['safe']),('unit_two',['safe']),('cli',['safe'])]
        self.assertEqual([r[0] for r in select_cases(cases,['unit*'],['*two'])],['unit_one'])
        with self.assertRaises(ValueError): select_cases(cases,['missing'],[])

    def test_rerun_validates_names(self):
        from run_tests import failed_names
        self.assertEqual(failed_names({'schema_version':1,'tests':[{'name':'one','status':'failed'},{'name':'two','status':'passed'}]},['one','two']),['one'])
        with self.assertRaises(ValueError): failed_names({'schema_version':1,'tests':[{'name':'shell','status':'failed','command':['evil']}]},['one'])

    def test_report_and_junit(self):
        from run_tests import write_reports
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'report.json';xml=Path(temp)/'junit.xml'
            report={'schema_version':1,'ok':False,'tests':[{'name':'a<&','status':'failed','duration_seconds':.1,'reason':'bad<&','log_path':'some path'}]}
            write_reports(report,path,xml)
            self.assertEqual(json.loads(path.read_text()),report)
            import xml.etree.ElementTree as ET
            root=ET.parse(xml).getroot();self.assertEqual(root.attrib['failures'],'1')
            self.assertEqual(root.find('testcase').attrib['name'],'a<&')
            self.assertFalse(list(Path(temp).glob('*.tmp*')))

    def test_release_plan(self):
        from release import plan
        with tempfile.TemporaryDirectory() as temp:
            rows=plan(['server','windows','server'],Path(temp).resolve()/'build','godot')
            self.assertEqual(len(rows),2)
            self.assertIn('Linux Server',rows[0]['command'])
            self.assertIn('--export-release',rows[0]['command'])
            self.assertTrue(Path(rows[0]['output']).is_relative_to(Path(temp).resolve()))
        with self.assertRaises(ValueError): plan(['unknown'],ROOT/'build','godot')
        with self.assertRaises(ValueError): plan(['server'],ROOT/'game','godot')

    def test_manifest_and_deterministic_package(self):
        from release import make_manifest,verify_manifest,package
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp).resolve()/'build';folder.mkdir()
            (folder/'TerraBlast').write_bytes(b'engine')
            (folder/'TerraBlast.pck').write_bytes(b'data')
            manifest=make_manifest(folder,'server','4.6.2.stable','abc')
            self.assertEqual(len(manifest['files']),2)
            (folder/'manifest.json').write_text(json.dumps(manifest))
            self.assertTrue(verify_manifest(folder)['ok'])
            target=Path(temp).resolve()/'release.zip'
            package(folder,target)
            first=target.read_bytes()
            package(folder,target,replace=True)
            self.assertEqual(target.read_bytes(),first)
            with self.assertRaises(FileExistsError):package(folder,target)
            (folder/'TerraBlast.pck').write_bytes(b'broken')
            self.assertFalse(verify_manifest(folder)['ok'])

    def test_manifest_rejects_traversal_and_symlink(self):
        from release import verify_manifest
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)
            (folder/'manifest.json').write_text(json.dumps({'schema_version':1,'files':[{'path':'../outside','size':1,'sha256':'0'*64}]}))
            self.assertFalse(verify_manifest(folder)['ok'])

    def test_cli_validation_without_engine(self):
        from run_tests import select_cases
        for args in (['--timeout','nan'],['--timeout','0'],['--include','does-not-exist']):
            result=subprocess.run([sys.executable,str(ROOT/'tools/run_tests.py'),*args],capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,2,result.stdout+result.stderr)
        result=subprocess.run([sys.executable,str(ROOT/'tools/run_tests.py'),'--list','--include','core_tests'],capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual([r['name'] for r in json.loads(result.stdout)],['core_tests'])

class DeliveryEdgeTests(unittest.TestCase):
    def test_doctor_contracts(self):
        from doctor import compatible_version,inspect_uids,inspect_presets,output_path
        self.assertTrue(compatible_version('4.6.2.stable.official.abc'))
        for bad in ['4.5.9.stable','5.0.0.stable','garbage']:self.assertFalse(compatible_version(bad))
        self.assertTrue(inspect_presets()['ok'])
        with self.assertRaises(ValueError):output_path(ROOT/'game/project.godot')
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)
            (folder/'a.gd').write_text('extends RefCounted')
            (folder/'a.gd.uid').write_text('uid://abc')
            self.assertTrue(inspect_uids(folder)['ok'])
            (folder/'b.gd.uid').write_text('uid://abc')
            result=inspect_uids(folder);self.assertFalse(result['ok']);self.assertEqual(len(result['errors']),2)

    def test_empty_artifact_and_symlink(self):
        from release import make_manifest,verify_manifest
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)
            with self.assertRaises(ValueError):make_manifest(folder,'server','4.6.2','rev')
            (folder/'engine').write_bytes(b'')
            with self.assertRaises(ValueError):make_manifest(folder,'server','4.6.2','rev')
            (folder/'engine').write_bytes(b'engine')
            manifest=make_manifest(folder,'server','4.6.2','rev')
            (folder/'manifest.json').write_text(json.dumps(manifest))
            (folder/'extra').write_text('unlisted')
            self.assertFalse(verify_manifest(folder)['ok'])

    def test_fake_export_and_sidecar(self):
        from release import plan,build,verify_manifest,engine_version
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp).resolve();fake=folder/'godot';templates=folder/'templates';templates.mkdir()
            fake.write_text('#!/usr/bin/env python3\nimport sys,pathlib\nif "--version" in sys.argv: print("4.6.2.stable.test");sys.exit(0)\np=pathlib.Path(sys.argv[-1]);p.write_bytes(b"engine");p.with_suffix(".pck").write_bytes(b"data")\n')
            fake.chmod(0o755);(templates/'linux_release.x86_64').write_bytes(b'template')
            rows=plan(['server'],folder/'build',str(fake))
            self.assertEqual(engine_version(str(fake)),'4.6.2.stable.test')
            result=build(rows,'4.6.2.stable',templates,10)
            self.assertEqual(len(result),1);self.assertTrue(verify_manifest(folder/'build/server')['ok'])
            with self.assertRaises(FileExistsError):build(rows,'4.6.2.stable',templates,10)
            build(rows,'4.6.2.stable',templates,10,replace=True)
            self.assertTrue(verify_manifest(folder/'build/server')['ok'])
            (templates/'linux_release.x86_64').unlink()
            with self.assertRaises(ValueError):build(rows,'4.6.2.stable',templates,10,replace=True)

    def test_failed_export_never_success_manifest(self):
        from release import plan,build
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp).resolve();fake=folder/'godot';templates=folder/'templates';templates.mkdir()
            fake.write_text('#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n');fake.chmod(0o755)
            (templates/'linux_release.x86_64').write_bytes(b'template')
            with self.assertRaises(ValueError):build(plan(['server'],folder/'build',str(fake)),'4.6.2.stable',templates,10)
            self.assertFalse((folder/'build/server/manifest.json').exists())

    def test_large_finished_log_and_signal(self):
        from devtools import run_case
        with tempfile.TemporaryDirectory() as temp:
            result=run_case('large',[sys.executable,'-c','print("x"*(9*1024*1024))'],temp,10)
            self.assertEqual(result['status'],'log_limit')
            result=run_case('failed',[sys.executable,'-c','raise SystemExit(4)'],temp,10)
            self.assertEqual(result['reason'],'nonzero_exit');self.assertEqual(result['exit_code'],4)

    def test_launcher_dry_run_and_release_plan(self):
        for args in [('release','plan','--platform','server'),('audit-maps','--dry-run')]:
            result=subprocess.run([sys.executable,str(ROOT/'tools/launch.py'),*args],capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIsInstance(json.loads(result.stdout),dict)

    def test_multiple_checksums_preserved(self):
        from release import make_manifest,package
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)/'build';folder.mkdir();(folder/'engine').write_bytes(b'engine')
            (folder/'manifest.json').write_text(json.dumps(make_manifest(folder,'server','4.6.2','revision')))
            package(folder,Path(temp).resolve()/'one.zip');package(folder,Path(temp).resolve()/'two.zip')
            self.assertEqual(len((Path(temp)/'SHA256SUMS').read_text().splitlines()),2)

if __name__=='__main__':unittest.main()
