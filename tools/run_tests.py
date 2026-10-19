#!/usr/bin/env python3
"""Bounded test suite: select, resume failures, incremental JSON and JUnit reports."""
import argparse
from datetime import datetime, timezone
import fnmatch
import json
import os
from pathlib import Path
import platform
import signal
import socket
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from devtools import ROOT, godot_binary, run_case, valid_timeout, bounded_text


def select_cases(cases, includes, excludes):
    selected=[case for case in cases if (not includes or any(fnmatch.fnmatchcase(case[0],p) for p in includes)) and not any(fnmatch.fnmatchcase(case[0],p) for p in excludes)]
    if not selected: raise ValueError('No tests match the selection')
    return selected


def failed_names(report, known):
    if not isinstance(report,dict) or report.get('schema_version')!=1 or not isinstance(report.get('tests'),list): raise ValueError('Invalid report schema')
    names=[]
    for item in report['tests']:
        if not isinstance(item,dict) or item.get('name') not in known or item.get('status') not in ['passed','failed','timeout','log_limit','skipped','interrupted']:
            raise ValueError('Unknown test or status in report')
        if item['status'] not in ['passed','skipped']:names.append(item['name'])
    return list(dict.fromkeys(names))


def atomic_text(path, content):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=path.parent,prefix=path.name+'.tmp-',delete=False) as output:
        temporary=Path(output.name);output.write(content);output.flush();os.fsync(output.fileno())
    try:os.replace(temporary,path)
    finally:temporary.unlink(missing_ok=True)


def write_reports(report, path, junit=None):
    atomic_text(path,json.dumps(report,indent=2)+'\n')
    if junit:
        tests=report['tests'];failed=sum(t['status'] not in ['passed','skipped'] for t in tests)
        root=ET.Element('testsuite',name='TerraBlast',tests=str(len(tests)),failures=str(failed),skipped=str(sum(t['status']=='skipped' for t in tests)))
        for row in tests:
            case=ET.SubElement(root,'testcase',name=row['name'],time=str(row.get('duration_seconds',0)))
            if row['status']=='skipped':ET.SubElement(case,'skipped',message=row.get('reason',''))
            elif row['status']!='passed':ET.SubElement(case,'failure',message=row.get('reason',row['status'])).text=row.get('log_path','')
            ET.SubElement(case,'system-out').text=row.get('log_path','')
        atomic_text(junit,ET.tostring(root,encoding='unicode'))


def build_cases(binary,directory):
    scripts=sorted((ROOT/'game/tests/unit').glob('*tests.gd'))
    names=['debug_scene_smoke','artillery_flow_tests','match_ui_tests','mvp_smoke','review_regressions','network_smoke','client50_tests','network50_tests']
    names += [p.stem for p in sorted((ROOT/'game/tests/integration').glob('*next_tests.gd'))]
    if os.environ.get('RUN_NAKAMA_TESTS')=='1':names+=['nakama_smoke','nakama50_tests']
    scripts += [ROOT/'game/tests/integration'/(name+'.gd') for name in dict.fromkeys(names)]
    cases=[(p.stem,[binary,'--headless','--path',str(ROOT/'game'),'--log-file',str(directory/(p.stem+'.log')),'--script',str(p)]) for p in scripts]
    port=19170
    if binary != 'godot':
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
            sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    cases.append(('server',[binary,'--headless','--path',str(ROOT/'game'),'--log-file',str(directory/'server.log'),'--','--mode','server','--port',str(port),'--smoke']))
    if os.environ.get('RUN_RENDER_TESTS')=='1':cases.append(('render',[binary,'--path',str(ROOT/'game'),'--log-file',str(directory/'render.log'),'--script','tests/integration/mvp_smoke.gd']))
    for script in ['test_devtools.py','run_network_process_test.py','test_simulation_cli.py','test_bot_cli.py','test_lobby_cli.py','test_library_cli.py','test_delivery.py','test_analysis_cli.py','test_release_review.py','test_scenarios.py','test_scenarios_engine.py','test_studio_cli.py']:
        cases.append((Path(script).stem,[sys.executable,str(ROOT/'tools'/script)]))
    # Stable names are the trusted execution registry; report files supply names only.
    if len({x[0] for x in cases})!=len(cases):raise ValueError('Duplicate test names')
    return cases


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout',type=valid_timeout,default=90)
    parser.add_argument('--report',type=Path);parser.add_argument('--log-dir',type=Path)
    parser.add_argument('--include',action='append',default=[]);parser.add_argument('--exclude',action='append',default=[])
    parser.add_argument('--list',action='store_true');parser.add_argument('--rerun-failed',type=Path)
    parser.add_argument('--fail-fast',action='store_true');parser.add_argument('--junit',type=Path);parser.add_argument('--jsonl',action='store_true')
    args=parser.parse_args()
    directory=args.log_dir or Path(tempfile.mkdtemp(prefix='terrablast-tests-'))
    # Each invocation retains its own attempt, even when a caller reuses --log-dir.
    directory.mkdir(parents=True,exist_ok=True)
    attempt=Path(tempfile.mkdtemp(prefix='attempt-',dir=directory))
    target=args.report or directory/'report.json'
    try:
        binary=godot_binary() if not args.list else 'godot'
    except OSError as error:
        report={'schema_version':1,'ok':False,'status':'finished','tests':[{'name':'environment','status':'failed','reason':str(error),'duration_seconds':0,'log_path':''}]}
        write_reports(report,target,args.junit)
        print(json.dumps(report) if args.jsonl else str(error))
        return 1
    try:
        cases=build_cases(binary,attempt)
        if args.rerun_failed:
            if args.rerun_failed.stat().st_size>8*1024*1024:raise ValueError('Report too large')
            names=failed_names(json.loads(args.rerun_failed.read_text()),[c[0] for c in cases])
            if not names:raise ValueError('Report has no failed tests')
            cases=[c for c in cases if c[0] in names]
        cases=select_cases(cases,args.include,args.exclude)
    except (OSError,ValueError) as error:parser.error(str(error))
    if args.list:
        print(json.dumps([{'name':name,'command':command} for name,command in cases]));return 0
    def interrupted(_signum,_frame):raise KeyboardInterrupt
    signal.signal(signal.SIGTERM,interrupted)
    try:revision=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,capture_output=True,text=True,timeout=5).stdout.strip()
    except (OSError,subprocess.TimeoutExpired):revision=''
    report={'schema_version':1,'ok':False,'status':'running','started_at':datetime.now(timezone.utc).isoformat(),'platform':platform.platform(),'revision':revision,'optional_checks':{'nakama':os.environ.get('RUN_NAKAMA_TESTS')=='1','render':os.environ.get('RUN_RENDER_TESTS')=='1'},'tests':[]}
    write_reports(report,target,args.junit)
    current='';blocked=False
    try:
        for name,command in cases:
            current=name
            if blocked:result={'name':name,'status':'skipped','reason':'fail_fast','duration_seconds':0,'log_path':''}
            else:result=run_case(name,command,attempt,args.timeout)
            report['tests'].append(result);write_reports(report,target,args.junit)
            if args.jsonl:print(json.dumps(result),flush=True)
            else:
                print(f"{name}: {result['status']} ({result['duration_seconds']}s)",flush=True)
                if result['status'] not in ['passed','skipped'] and result.get('log_path'):print(bounded_text(result['log_path'])[-12000:])
            if args.fail_fast and result['status']!='passed':blocked=True
    except KeyboardInterrupt:
        report['tests'].append({'name':current,'status':'interrupted','reason':'signal','duration_seconds':0,'log_path':''})
    except OSError as error:
        report['tests'].append({'name':current,'status':'failed','reason':str(error),'duration_seconds':0,'log_path':''})
    finally:
        report['status']='finished';report['finished_at']=datetime.now(timezone.utc).isoformat()
        report['ok']=len(report['tests'])==len(cases) and all(r['status']=='passed' for r in report['tests'])
        write_reports(report,target,args.junit)
        if not args.jsonl:print('Report: '+str(target.resolve()))
    return 0 if report['ok'] else 1

if __name__=='__main__':sys.exit(main())
