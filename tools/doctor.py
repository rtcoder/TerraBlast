#!/usr/bin/env python3
"""Check local prerequisites, engine compatibility, maps, UIDs and export presets."""
import argparse
import configparser
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.request
from devtools import ROOT,godot_binary
from run_tests import atomic_text
from release import template_directory


def compatible_version(value):
    match=re.match(r'^(\d+)\.(\d+)\.(\d+)\.',value)
    return bool(match and int(match[1])==4 and tuple(map(int,match.groups())) >= (4,6,2))


def inspect_uids(root=ROOT/'game'):
    seen={};errors=[]
    for path in sorted(Path(root).rglob('*.gd.uid')):
        if '.godot' in path.parts:continue
        if path.is_symlink():errors.append(str(path)+': symlink');continue
        value=path.read_text().strip()
        if not re.fullmatch('uid://[a-z0-9]+',value):errors.append(str(path)+': format')
        elif value in seen:errors.append(str(path)+': duplicate '+str(seen[value]))
        if not path.with_suffix('').is_file():errors.append(str(path)+': missing script')
        seen[value]=path
    return {'ok':not errors,'count':len(seen),'errors':errors}


def inspect_presets(path=ROOT/'game/export_presets.cfg'):
    config=configparser.ConfigParser(interpolation=None,strict=True)
    try:
        config.read(path)
        expected={'macOS':'macOS','Windows Desktop':'Windows Desktop','Linux Desktop':'Linux','Linux Server':'Linux'}
        found={}
        for section in config.sections():
            if not re.fullmatch(r'preset\.\d+',section):continue
            row=config[section];name=row.get('name','').strip('"');platform=row.get('platform','').strip('"')
            output=(ROOT/'game'/row.get('export_path','').strip('"')).resolve()
            if name in found or not output.is_relative_to((ROOT/'build').resolve()):raise ValueError('Duplicate preset or unsafe output')
            found[name]=platform
        return {'ok':found==expected,'presets':found}
    except (ValueError,configparser.Error,OSError) as error:return {'ok':False,'reason':str(error)}


def output_path(path):
    path=Path(path).absolute()
    if path.is_symlink() or any(parent.name=='.git' for parent in path.parents):raise ValueError('Unsafe report output')
    resolved=path.resolve()
    if resolved.suffix!='.json' or resolved in [ROOT/'game/project.godot',ROOT/'game/export_presets.cfg']:raise ValueError('Report output must be a JSON artifact')
    if any(parent.name=='.git' for parent in resolved.parents):raise ValueError('Unsafe report output')
    if resolved.is_relative_to(ROOT) and not resolved.is_relative_to(ROOT/'build'):
        raise ValueError('Reports inside the repository must use build/')
    return resolved


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--nakama',action='store_true');parser.add_argument('--templates',action='store_true');parser.add_argument('--output',type=Path)
    args=parser.parse_args();checks={}
    try:target=output_path(args.output) if args.output else None
    except (ValueError,OSError) as error:parser.error(str(error))
    try:
        binary=godot_binary();version=subprocess.run([binary,'--version'],capture_output=True,text=True,timeout=10)
        value=version.stdout.strip();checks['godot']={'ok':version.returncode==0 and compatible_version(value),'version':value}
    except (OSError,subprocess.TimeoutExpired) as error:checks['godot']={'ok':False,'reason':str(error)}
    checks['python']={'ok':sys.version_info >= (3,10),'version':sys.version.split()[0]}
    checks['project']={'ok':(ROOT/'game/project.godot').is_file()}
    checks['uids']=inspect_uids();checks['export_presets']=inspect_presets()
    checks['maps']={'ok':False,'reason':'engine_unavailable'}
    if checks['godot']['ok']:
        try:
            with tempfile.TemporaryDirectory(prefix='terrablast-doctor-') as temp:
                audit=subprocess.run([binary,'--headless','--path',str(ROOT/'game'),'--log-file',str(Path(temp)/'audit.log'),'--','--list-maps'],capture_output=True,text=True,timeout=60)
                data=json.loads(next(line for line in audit.stdout.splitlines() if line.startswith('{')))
                checks['maps']={'ok':audit.returncode==0 and data['ok'],'count':len(data['maps'])}
        except (OSError,subprocess.TimeoutExpired,ValueError,StopIteration,KeyError):checks['maps']={'ok':False,'reason':'map_audit_failed'}
    if args.templates:
        folder=template_directory(checks['godot'].get('version','4.6.2.stable'))
        names=['macos.zip','windows_release_x86_64.exe','linux_release.x86_64']
        missing=[name for name in names if not (folder/name).is_file()]
        checks['templates']={'ok':not missing,'directory':str(folder),'missing':missing,'optional':True}
    if args.nakama:
        try:
            with urllib.request.urlopen('http://127.0.0.1:7350/healthcheck',timeout=2) as response:checks['nakama']={'ok':response.status==200,'optional':True}
        except OSError:checks['nakama']={'ok':False,'optional':True}
    ok=all(v['ok'] for v in checks.values() if not v.get('optional'))
    report={'ok':ok,'checks':checks}
    if target:atomic_text(target,json.dumps(report,indent=2)+'\n')
    print(json.dumps(report));return 0 if ok else 1

if __name__=='__main__':sys.exit(main())
