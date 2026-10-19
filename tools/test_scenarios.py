import json
import tempfile
import unittest
from pathlib import Path
import scenarios as S
import scenario_report as R

MANIFEST={'version':1,'maps':['two_islands'],'players':[2],'presets':['classic'],'seeds':[1,2],'shots':2,'bots':['seeded'],'repeats':1}
class ScenarioContracts(unittest.TestCase):
    def test_schema_and_limits(self):
        self.assertEqual(len(S.expand_matrix(MANIFEST)),2)
        for patch in [{'version':2},{'shots':True},{'players':[1]},{'seeds':[-1]},{'repeats':11},{'extra':1},{'maps':['../bad']},{'bots':['unsafe']}]:
            with self.assertRaises(ValueError):S.validate_manifest(dict(MANIFEST,**patch))
        with self.assertRaises(ValueError):S.expand_matrix(dict(MANIFEST,seeds=list(range(100)),repeats=2))
    def test_stable_ids_and_repeats(self):
        a=S.expand_matrix(dict(MANIFEST,seeds=[2,1,1]));b=S.expand_matrix(MANIFEST)
        self.assertEqual(a,b)
        rows=S.expand_matrix(dict(MANIFEST,seeds=[1],repeats=2))
        self.assertNotEqual(rows[0]['id'],rows[1]['id']);self.assertEqual(rows[0]['config_digest'],rows[1]['config_digest'])
    def test_selection(self):
        rows=S.expand_matrix(MANIFEST)
        self.assertEqual(S.select_cases(rows,[rows[0]['id']],[]),rows[:1])
        with self.assertRaises(ValueError):S.select_cases(rows,['missing'],[])
    def fixture(self):
        rows=S.expand_matrix(dict(MANIFEST,seeds=[1],repeats=2))
        state={'status':'ended','winner_team':1,'statistics':{'a':{'shots':2,'hits':1,'damage':12,'kills':0}}}
        for i,row in enumerate(rows):row.update(status='passed',duration_seconds=i+1,summary={'map':'two_islands','seed':1,'shots':2,'deltas':3,'terrain_hash':'a'*64,'state':state},artifacts=[])
        return {'schema_version':1,'ok':True,'manifest_digest':'a'*64,'tests':rows,'environment':{'godot':'4.6.2'}}
    def test_summary_and_repeatability(self):
        report=self.fixture();summary=R.summarize(report)
        self.assertEqual(summary['counts']['passed'],2);self.assertEqual(summary['outcomes']['team_1'],2)
        self.assertEqual(summary['metrics']['damage'],24);self.assertEqual(summary['timing']['p95'],2)
        self.assertEqual(summary['nondeterministic'],[])
        report['tests'][1]['summary']=json.loads(json.dumps(report['tests'][1]['summary']));report['tests'][1]['summary']['terrain_hash']='b'*64
        self.assertEqual(len(R.summarize(report)['nondeterministic']),1)
    def test_comparison(self):
        first=self.fixture();second=json.loads(json.dumps(first))
        self.assertTrue(R.compare_reports(first,second)['ok'])
        second['tests'][0]['duration_seconds']=5
        self.assertFalse(R.compare_reports(first,second)['ok'])
        second=self.fixture();extra=json.loads(json.dumps(second['tests'][0]));extra.update(id='new-failed',status='failed');second['tests'].append(extra)
        self.assertFalse(R.compare_reports(first,second)['ok'])
        second=self.fixture();second['tests'].pop()
        self.assertFalse(R.compare_reports(first,second)['ok']);self.assertTrue(R.compare_reports(first,second,strict=False)['ok'])
    def test_exports_and_report_validation(self):
        report=self.fixture();report['tests'][0]['reason']='<script>alert(1)</script>'
        self.assertNotIn('<script>alert',R.to_html(report));self.assertIn('case_id',R.to_csv(report));self.assertIn('|',R.to_markdown(report))
        report['tests'][0]['duration_seconds']=float('nan')
        with self.assertRaises(ValueError):R.validate_report(report)

class ExecutionContracts(unittest.TestCase):
    def test_safe_root_and_bounded_load(self):
        with self.assertRaises(ValueError):S.safe_root(S.ROOT/'game'/'outputs')
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();(root/'link').symlink_to(root,target_is_directory=True)
            with self.assertRaises(ValueError):S.safe_root(root/'link'/'out')
            f=root/'large.json';f.write_text(' '*200)
            with self.assertRaises(ValueError):S.load_json(f,100)
    def test_fake_engine_resume_and_tamper(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();engine=root/'engine.py'
            engine.write_text("#!/usr/bin/env python3\nimport sys,json\na=sys.argv\nif '--version' in a: print('4.6.2');sys.exit(0)\nif 'audit-maps' in a: print(json.dumps({'ok':True,'maps':[{'id':'two_islands'}]}));sys.exit(0)\njson.dump({'map':'two_islands','seed':int(a[a.index('--seed')+1]),'shots':2,'deltas':0,'terrain_hash':'abc','state':{'status':'playing','statistics':{}}},open(a[a.index('--output')+1],'w'))\n")
            engine.chmod(0o755);out=root/'output'
            first=S.run_matrix(MANIFEST,out,str(engine),jobs=2)
            self.assertTrue(first['ok']);self.assertEqual(len(first['tests']),2)
            tampered=json.loads(json.dumps(first['tests'][0]));tampered['summary']['state']['winner_team']=2
            self.assertFalse(S._reusable(out,tampered,first['tests'][0],False,False))
            second=S.run_matrix(MANIFEST,out,str(engine),resume=True)
            self.assertEqual(first['tests'][0]['artifacts'],second['tests'][0]['artifacts'])
            artifact=out/first['tests'][0]['artifacts'][0]['path'];artifact.write_text('{}')
            third=S.run_matrix(MANIFEST,out,str(engine),resume=True)
            self.assertTrue(third['ok']);self.assertNotEqual(first['tests'][0]['artifacts'][0]['path'],third['tests'][0]['artifacts'][0]['path'])

class FailureContracts(unittest.TestCase):
    def test_worker_failures_and_cancellation(self):
        import threading,time,os
        for mode,expected in [('crash','failed'),('sleep','timeout'),('large','log_limit'),('cancel','interrupted')]:
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as d:
                root=Path(d).resolve();script=root/'engine.py'
                script.write_text("import sys,time,os\n"+{'crash':"sys.exit(7)",'sleep':"time.sleep(30)",'large':"print('x'*9000000);time.sleep(30)",'cancel':"time.sleep(30)"}[mode])
                cancel=threading.Event()
                if mode=='cancel':threading.Timer(.1,cancel.set).start()
                result=S._execute([__import__('sys').executable,str(script)],root,.2,cancel)
                self.assertEqual(result['status'],expected,result)
    @unittest.skipIf(__import__('os').name=='nt','POSIX signal and process group test')
    def test_parallel_signal_kills_children_and_preserves_report(self):
        import subprocess,sys,time,os,signal
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();engine=root/'engine';manifest=root/'manifest.json';manifest.write_text(json.dumps(MANIFEST))
            engine.write_text("#!/usr/bin/env python3\nimport sys,json,time,subprocess,pathlib\nroot=pathlib.Path(__file__).parent\na=sys.argv\nif '--version' in a: print('4.6.2');sys.exit()\nif 'audit-maps' in a: print(json.dumps({'ok':True,'maps':[{'id':'two_islands'}]}));sys.exit()\np=pathlib.Path(a[a.index('--output')+1]);subprocess.Popen([sys.executable,'-c',\"import time,pathlib;time.sleep(1);pathlib.Path(\"+repr(str(root/'escaped'))+\").touch()\"])\np.with_suffix('.started').touch()\ntime.sleep(30)\n")
            engine.chmod(0o755);env=dict(os.environ,GODOT_BIN=str(engine));out=root/'out'
            proc=subprocess.Popen([sys.executable,str(S.ROOT/'tools/scenarios.py'),'run','--manifest',str(manifest),'--output-root',str(out),'--jobs','2'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                until=time.monotonic()+5
                while len(list(out.glob('cases/*/*/*.started')))<2 and time.monotonic()<until:time.sleep(.02)
                self.assertEqual(len(list(out.glob('cases/*/*/*.started'))),2)
                proc.send_signal(signal.SIGTERM);stdout,stderr=proc.communicate(timeout=5)
                self.assertEqual(proc.returncode,1,stderr)
                value=json.loads(stdout);self.assertTrue(all(r['status']=='interrupted' for r in value['tests']),(value,[(p.read_text()) for p in out.glob('cases/*/*/process.log')]))
                time.sleep(1.1);self.assertFalse((root/'escaped').exists())
                self.assertEqual(S.load_json(out/'report.json')['tests'],value['tests'])
            finally:
                if proc.poll() is None:proc.kill();proc.wait()

    def test_total_deadline_and_foreign_directory(self):
        import sys
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();engine=root/'engine'
            engine.write_text("#!/usr/bin/env python3\nimport sys,json,time\na=sys.argv\nif '--version' in a:print('4.6.2');sys.exit()\nif 'audit-maps' in a:print(json.dumps({'ok':True,'maps':[{'id':'two_islands'}]}));sys.exit()\ntime.sleep(30)\n")
            engine.chmod(0o755)
            value=S.run_matrix(dict(MANIFEST,seeds=[1,2,3,4]),root/'out',str(engine),timeout=2,deadline=5)
            self.assertFalse(value['ok']);self.assertIn('interrupted',[r['status'] for r in value['tests']]);self.assertIn('timeout',[r['status'] for r in value['tests']])
            with self.assertRaises(ValueError):S.run_matrix(MANIFEST,root,str(engine))

    def test_review_fast_output_recovery_and_huge_numbers(self):
        import sys,threading
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve()
            value=S._execute([sys.executable,'-c',"print('x'*9000000)"],root,5,threading.Event())
            self.assertEqual(value['status'],'log_limit')
        first=ScenarioContracts().fixture();second=ScenarioContracts().fixture()
        first['tests'][0].update(status='timeout');first['tests'][0].pop('summary')
        self.assertTrue(R.compare_reports(first,second,time_absolute=10)['ok'])
        second['tests'][0]['duration_seconds']=10**400
        with self.assertRaises(ValueError):R.validate_report(second)

    def test_plan_foreign_cwd_and_empty_selection(self):
        import subprocess,sys
        with tempfile.TemporaryDirectory() as d:
            command=[sys.executable,str(S.ROOT/'tools/launch.py'),'scenarios','plan','--manifest',str(S.ROOT/'tools/scenarios/smoke.json')]
            result=subprocess.run(command,cwd=d,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            value=json.loads(result.stdout);self.assertEqual(value['cost']['upper_shots'],4)
            result=subprocess.run(command+['--exclude','*'],cwd=d,capture_output=True,text=True)
            self.assertEqual(result.returncode,2)
    def test_report_integrity_and_export_escaping(self):
        report=ScenarioContracts().fixture()
        report['tests'][0]['config']['seed']=999
        with self.assertRaises(ValueError):R.validate_report(report)
        report=ScenarioContracts().fixture();report['tests'][0]['reason']='=HYPERLINK("evil")'
        self.assertIn("'=HYPERLINK",R.to_csv(report))
        self.assertEqual(R.summarize(report)['timing']['min'],1)
        self.assertEqual(R.summarize(report)['groups'][0]['deltas'],6)

if __name__=='__main__':unittest.main()
