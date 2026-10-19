"""Bounded reproducible simulation matrices; commands are never read from reports."""
import argparse
import fnmatch
import itertools
import json
import re
from pathlib import Path
import scenario_report as report

MAPS={'ballistics_range','terraced_quarry','split_pass','bunker_court','ring_island','three_lane_foundry','twin_forts','two_islands','canyon_bridge'}
PRESETS={'classic','quick','training'}

def validate_manifest(value):
    keys={'version','maps','players','presets','seeds','shots','bots','repeats'}
    if not isinstance(value,dict) or set(value)-keys or not keys-{'repeats'}<=value.keys():raise ValueError('invalid manifest fields')
    out=dict(value);out.setdefault('repeats',1)
    for key,lo,hi in [('version',1,1),('shots',1,256),('repeats',1,10)]:
        if type(out[key]) is not int or not lo<=out[key]<=hi:raise ValueError('invalid '+key)
    for key in ('maps','players','presets','seeds','bots'):
        values=out[key]
        if not isinstance(values,list) or not values:raise ValueError('empty axis '+key)
        for v in values:
            if key=='maps':ok=isinstance(v,str) and v in MAPS
            elif key=='players':ok=type(v) is int and v in (2,4,6,8,10)
            elif key=='seeds':ok=type(v) is int and 0<=v<=2147483647
            elif key=='presets':ok=isinstance(v,str) and v in PRESETS
            else:ok=isinstance(v,str) and v in ('seeded','easy','normal')
            if not ok:raise ValueError('invalid axis '+key)
        out[key]=sorted(set(values))
    count=out['repeats']
    for key in ('maps','players','presets','seeds','bots'):count*=len(out[key])
    if count>128:raise ValueError('matrix exceeds 128 cases')
    return out

def expand_matrix(value):
    m=validate_manifest(value);rows=[]
    for values in itertools.product(*(m[k] for k in ('maps','players','presets','seeds','bots'))):
        config=dict(zip(('map','players','preset','seed','bots'),values),shots=m['shots']);digest=report.digest(config)
        for repeat in range(1,m['repeats']+1):rows.append({'id':digest[:20]+'-r'+str(repeat),'config_digest':digest,'config':config.copy(),'repeat':repeat})
    return rows

def select_cases(cases,includes=None,excludes=None):
    includes=includes or [];excludes=excludes or []
    for pattern in includes+excludes:
        if not any(fnmatch.fnmatchcase(r['id'],pattern) for r in cases):raise ValueError('selection matches no case: '+pattern)
    return [r for r in cases if (not includes or any(fnmatch.fnmatchcase(r['id'],p) for p in includes)) and not any(fnmatch.fnmatchcase(r['id'],p) for p in excludes)]

import concurrent.futures
import hashlib
import os
import platform
import signal
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from devtools import ROOT, godot_binary, spawn, stop, valid_timeout, bounded_text

def load_json(path, limit=8*1024*1024):
    path=Path(path)
    with path.open('rb') as f:data=f.read(limit+1)
    if len(data)>limit:raise ValueError('JSON exceeds byte limit')
    return json.loads(data,parse_constant=lambda v:(_ for _ in ()).throw(ValueError('nonfinite JSON')))

def safe_root(path):
    path=Path(os.path.abspath(path))
    if any(p.is_symlink() for p in [path,*path.parents]):raise ValueError('symlink output path')
    resolved=path.resolve();source=ROOT.resolve()
    if resolved==source or (source in resolved.parents and not source/'build' in [resolved,*resolved.parents]):raise ValueError('output overlaps source')
    if resolved in source.parents:raise ValueError('output contains source')
    return resolved

def atomic_json(path,value):
    path=Path(path)
    content=report.canonical(value)+'\n'
    if len(content.encode('utf-8'))>8*1024*1024:raise ValueError('report exceeds 8 MiB')
    with tempfile.NamedTemporaryFile(mode='w',dir=path.parent,prefix='.scenario-',delete=False,encoding='utf-8') as f:
        temporary=Path(f.name);f.write(content)
    try:os.replace(temporary,path)
    finally:temporary.unlink(missing_ok=True)

def _command(binary,directory,args):
    return [str(binary),'--headless','--path',str(ROOT/'game'),'--log-file',str(directory/'godot.log'),'--',*args]

def _execute(command,directory,timeout,cancel):
    started=time.monotonic();log=directory/'process.log';status='failed';reason='';code=None
    with log.open('w') as output:
        process=None
        try:
            process=spawn(command,stdout=output,stderr=subprocess.STDOUT)
            while process.poll() is None:
                if cancel.is_set():status='interrupted';reason='cancelled';break
                if time.monotonic()-started>=timeout:status='timeout';reason='deadline_exceeded';break
                if log.stat().st_size>8*1024*1024:status='log_limit';reason='output_limit';break
                cancel.wait(.02)
            else:
                code=process.returncode;status='passed' if code==0 else 'failed';reason='' if code==0 else 'exit_'+str(code)
        except OSError as error:reason='spawn_failure: '+str(error)
        finally:
            if process is not None:stop(process)
    if log.stat().st_size>8*1024*1024:status='log_limit';reason='output_limit'
    text=bounded_text(log)
    if status=='passed' and ('SCRIPT ERROR:' in text or '\nERROR:' in text):status='failed';reason='engine_error'
    return {'status':status,'reason':reason,'exit_code':code,'duration_seconds':round(time.monotonic()-started,4)}

def _artifacts(root,paths):
    result=[]
    for p in paths:
        if p.is_symlink() or p.stat().st_size>32*1024*1024:raise ValueError('invalid artifact')
        result.append({'path':str(p.relative_to(root)),'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    return result

def _reusable(root,row,expected,record,verify):
    if row.get('status')!='passed' or row.get('config_digest')!=expected['config_digest'] or row.get('config')!=expected['config']:return False
    if record and not row.get('recorded') or verify and not row.get('verified'):return False
    artifacts=row.get('artifacts',[])
    if not artifacts:return False
    names=[Path(a.get('path','')).name for a in artifacts if isinstance(a,dict)]
    if names.count('summary.json')!=1 or ((record or row.get('recorded')) and names.count('replay.json')!=1):return False
    try:
        for item in artifacts:
            relative=Path(item['path']);path=root/relative
            if relative.is_absolute() or '..' in relative.parts or len(relative.parts)!=4 or relative.parts[:2]!=('cases',row['id']):return False
            if any(p.is_symlink() for p in [path,*path.parents]) or not path.is_file() or path.stat().st_size!=item['size']:return False
            if path.stat().st_size>32*1024*1024 or hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']:return False
            if path.name=='summary.json' and report.canonical(load_json(path))!=report.canonical(row.get('summary')):return False
        return True
    except (OSError,KeyError,TypeError,ValueError):return False

def run_matrix(manifest,root,binary,jobs=1,timeout=60,deadline=3600,record=False,verify=False,resume=False,retry_failed=False,includes=None,excludes=None):
    manifest=validate_manifest(manifest);rows=select_cases(expand_matrix(manifest),includes,excludes)
    if not rows:raise ValueError('empty selected matrix')
    if type(jobs) is not int or not 1<=jobs<=4:raise ValueError('jobs must be 1..4')
    timeout=valid_timeout(timeout);deadline=valid_timeout(deadline);record=record or verify
    root=safe_root(root)
    marker=root/'.terrablast-scenarios'
    if marker.is_symlink() or (root/'report.json').is_symlink():raise ValueError('symlink metadata path')
    if root.exists() and any(root.iterdir()) and not marker.is_file():raise ValueError('output directory is not a scenario directory')
    root.mkdir(parents=True,exist_ok=True)
    marker.write_text('1\n')
    lock=root/'.running'
    try:fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
    except FileExistsError:raise ValueError('output root is locked by another run; inspect .running before removing stale lock')
    os.close(fd);cancel=threading.Event();previous_handlers={};started=time.monotonic()
    try:
        for sig in (signal.SIGINT,signal.SIGTERM):
            if threading.current_thread() is threading.main_thread():
                previous_handlers[sig]=signal.signal(sig,lambda *_:cancel.set())
        old={};report_path=root/'report.json';manifest_digest=report.digest(manifest)
        if (resume or retry_failed) and report_path.exists():
            previous=report.validate_report(load_json(report_path))
            if previous.get('manifest_digest')!=manifest_digest:raise ValueError('resume manifest differs')
            old={r['id']:r for r in previous['tests']}
        preflight=Path(tempfile.mkdtemp(prefix='preflight-',dir=root))
        version=_execute([str(binary),'--version'],preflight,min(timeout,deadline),cancel)
        if version['status']!='passed':raise ValueError('Godot version preflight failed: '+version['reason'])
        version_text=bounded_text(preflight/'process.log',4096).strip()
        audit=preflight/'audit';audit.mkdir()
        check=_execute(_command(binary,audit,['--mode','audit-maps']),audit,min(timeout,max(.01,deadline-(time.monotonic()-started))),cancel)
        audit_data=None
        for line in bounded_text(audit/'process.log').splitlines():
            try:
                value=json.loads(line)
                if isinstance(value,dict) and 'maps' in value:audit_data=value
            except ValueError:pass
        if check['status']!='passed' or not audit_data or not audit_data.get('ok'):raise ValueError('Godot map audit failed')
        available={m['id'] for m in audit_data['maps']}
        if any(r['config']['map'] not in available for r in rows):raise ValueError('map absent from engine registry')
        revision=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,capture_output=True,text=True,timeout=5).stdout.strip()
        result={'created_at':datetime.now(timezone.utc).isoformat(),'schema_version':1,'manifest_digest':manifest_digest,'environment':{'godot':version_text,'platform':platform.platform(),'revision':revision},'ok':False,'tests':[]}
        for r in rows:
            if r['id'] in old and old[r['id']].get('producer')==result['environment'] and _reusable(root,old[r['id']],r,record,verify):result['tests'].append(old[r['id']])
            else:result['tests'].append(dict(r,status='pending',duration_seconds=0,artifacts=[]))
        atomic_json(report_path,result)
        def worker(row):
            remaining=deadline-(time.monotonic()-started)
            if cancel.is_set() or remaining<=0:return dict(row,status='interrupted',reason='total_deadline',duration_seconds=0,artifacts=[])
            case=root/'cases'/row['id'];safe_root(case);case.mkdir(parents=True,exist_ok=True)
            directory=Path(tempfile.mkdtemp(prefix='attempt-',dir=case));summary=directory/'summary.json';replay=directory/'replay.json'
            cfg=row['config'];args=['--mode','simulate']
            for key in ('map','players','preset','seed','shots'):args.extend(['--'+key,str(cfg[key])])
            if cfg['bots']!='seeded':args.extend(['--bots',cfg['bots']])
            args.extend(['--output',str(summary)])
            if record:args.extend(['--record',str(replay)])
            outcome=_execute(_command(binary,directory,args),directory,min(timeout,remaining),cancel)
            updated=dict(row,**outcome,artifacts=[],recorded=record,verified=False,producer=result['environment'],log_path=str((directory/'process.log').relative_to(root)))
            if outcome['status']=='passed':
                try:
                    value=report.validate_summary(load_json(summary))
                    if value['map']!=cfg['map'] or value['seed']!=cfg['seed'] or value['shots']>cfg['shots']:raise ValueError('summary configuration mismatch')
                    updated['summary']=value
                    if verify:
                        if cancel.is_set() or time.monotonic()-started>=deadline:
                            updated.update(status='interrupted',reason='total_deadline');return updated
                        verify_dir=directory/'verify';verify_dir.mkdir()
                        checked=_execute(_command(binary,verify_dir,['--mode','replay','--replay',str(replay)]),verify_dir,min(timeout,max(.01,deadline-(time.monotonic()-started))),cancel)
                        if checked['status']!='passed':raise ValueError('replay verification failed: '+checked['reason'])
                        updated['verified']=True
                    updated['artifacts']=_artifacts(root,[summary]+([replay] if record else []))
                except (ValueError,OSError,KeyError,TypeError) as error:updated.update(status='failed',reason=('replay_failure: ' if 'replay verification' in str(error) else 'invalid_summary: ')+str(error))
            return updated
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            futures={pool.submit(worker,r):i for i,r in enumerate(result['tests']) if r['status']=='pending'}
            try:
                for future in concurrent.futures.as_completed(futures):
                    i=futures[future]
                    try:result['tests'][i]=future.result()
                    except Exception as error:result['tests'][i].update(status='failed',reason=str(error))
                    atomic_json(report_path,result)
            except BaseException:
                cancel.set()
                raise
        result['ok']=all(r['status']=='passed' for r in result['tests'])
        result['duration_seconds']=round(time.monotonic()-started,4)
        atomic_json(report_path,result)
        return result
    finally:
        cancel.set()
        for sig,handler in previous_handlers.items():signal.signal(sig,handler)
        lock.unlink(missing_ok=True)

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='command',required=True)
    for name in ('plan','validate','run'):
        p=sub.add_parser(name);p.add_argument('--manifest',required=True);p.add_argument('--include',action='append',default=[]);p.add_argument('--exclude',action='append',default=[])
        if name=='run':
            p.add_argument('--output-root',required=True);p.add_argument('--jobs',type=int,default=1);p.add_argument('--timeout',type=float,default=60);p.add_argument('--deadline',type=float,default=3600)
            for flag in ('record-all','verify-recordings','resume','retry-failed'):p.add_argument('--'+flag,action='store_true')
    for name in ('summary','validate-report','export'):
        p=sub.add_parser(name);p.add_argument('report')
        if name=='summary':p.add_argument('--status');p.add_argument('--map')
        if name=='export':p.add_argument('--format',choices=['json','csv','markdown','html'],required=True);p.add_argument('--output',required=True)
    p=sub.add_parser('compare');p.add_argument('baseline');p.add_argument('candidate');p.add_argument('--time-relative',type=float,default=.2);p.add_argument('--time-absolute',type=float,default=.1);p.add_argument('--permissive',action='store_true')
    args=parser.parse_args(argv)
    try:
        if args.command in ('plan','validate','run'):
            manifest=validate_manifest(load_json(args.manifest,1024*1024));cases=select_cases(expand_matrix(manifest),args.include,args.exclude)
            if not cases:raise ValueError('empty selected matrix')
            planned=[]
            for case in cases:
                cfg=case['config'];command=['godot','--headless','--path',str(ROOT/'game'),'--','--mode','simulate']
                for key in ('map','players','preset','seed','shots'):command.extend(['--'+key,str(cfg[key])])
                if cfg['bots']!='seeded':command.extend(['--bots',cfg['bots']])
                planned.append(dict(case,command=command))
            value={'ok':True,'manifest':manifest,'cases':planned,'cost':{'cases':len(cases),'upper_shots':sum(c['config']['shots'] for c in cases),'recordings':len(cases) if getattr(args,'record_all',False) or getattr(args,'verify_recordings',False) else 0}}
            if args.command=='run':value=run_matrix(manifest,args.output_root,godot_binary(),args.jobs,args.timeout,args.deadline,args.record_all,args.verify_recordings,args.resume,args.retry_failed,args.include,args.exclude)
        elif args.command=='compare':value=report.compare_reports(load_json(args.baseline),load_json(args.candidate),args.time_relative,args.time_absolute,not args.permissive)
        else:
            value=report.validate_report(load_json(args.report))
            if args.command=='summary':value=report.summarize(value,{'status':args.status,'map':args.map})
            elif args.command=='export':
                output=safe_root(args.output)
                if output.resolve()==Path(args.report).resolve():raise ValueError('export overlaps input')
                if output.exists():raise ValueError('export destination already exists')
                content={'json':lambda v:report.canonical(v)+'\n','csv':report.to_csv,'markdown':report.to_markdown,'html':report.to_html}[args.format](value)
                output.parent.mkdir(parents=True,exist_ok=True)
                with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=output.parent,delete=False) as f:f.write(content);temporary=f.name
                os.replace(temporary,output);value={'ok':True,'output':str(output)}
        print(json.dumps(value,ensure_ascii=False,allow_nan=False));return 0 if value.get('ok',True) else 1
    except (ValueError,OSError,KeyError,TypeError) as error:
        print(json.dumps({'ok':False,'reason':str(error)}));return 2

if __name__=='__main__':sys.exit(main())
