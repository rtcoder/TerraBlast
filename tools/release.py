#!/usr/bin/env python3
"""Plan/build/package/verify local desktop releases. Does not publish artifacts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile
from devtools import ROOT,godot_binary,run_case,valid_timeout
from run_tests import atomic_text

PRESETS={'macos':('macOS','TerraBlast.zip','macos.zip'),'windows':('Windows Desktop','TerraBlast.exe','windows_release_x86_64.exe'),'linux':('Linux Desktop','TerraBlast.x86_64','linux_release.x86_64'),'server':('Linux Server','TerraBlast.x86_64','linux_release.x86_64')}


def safe_root(path):
    path=Path(path).absolute()
    if any(part.is_symlink() for part in [path,*path.parents]):raise ValueError('Build path has symlink components')
    path=path.resolve()
    protected=[ROOT/'game',ROOT/'tools',ROOT/'docs',ROOT/'backend',ROOT/'server',ROOT/'.git',ROOT/'.github']
    if path==ROOT or any(path==p or path.is_relative_to(p) or p.is_relative_to(path) for p in protected):raise ValueError('Build root overlaps source tree')
    return path


def plan(platforms,build_root,binary):
    build_root=safe_root(build_root)
    rows=[]
    for name in dict.fromkeys(platforms):
        if name not in PRESETS:raise ValueError('Unknown platform: '+name)
        preset,filename,_=PRESETS[name];output=build_root/name/filename
        rows.append({'platform':name,'preset':preset,'output':str(output),'command':[binary,'--headless','--path',str(ROOT/'game'),'--export-release',preset,str(output)]})
    if not rows:raise ValueError('No platforms selected')
    return rows


def engine_version(binary):
    result=subprocess.run([binary,'--version'],capture_output=True,text=True,timeout=10)
    value=result.stdout.strip();match=re.match(r'^(\d+)\.(\d+)\.(\d+)\.',value)
    if result.returncode or not match or tuple(map(int,match.groups()))[:2]!=(4,6) or int(match[3])<2:raise ValueError('Godot 4.6.2+ in the 4.6 release line is required')
    return value


def template_directory(version):
    version='.'.join(version.split('.')[:4])
    if sys.platform=='darwin':base=Path.home()/'Library/Application Support/Godot/export_templates'
    elif os.name=='nt':base=Path(os.environ.get('APPDATA',str(Path.home()))) /'Godot/export_templates'
    else:base=Path(os.environ.get('XDG_DATA_HOME',str(Path.home()/'.local/share')))/'godot/export_templates'
    return base/version


def sha256(path):
    digest=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):digest.update(block)
    return digest.hexdigest()


def make_manifest(folder,platform_name,version,revision):
    folder=Path(folder).resolve();files=[]
    for path in sorted(folder.rglob('*')):
        if path.is_symlink():raise ValueError('Symlink in artifact')
        if not path.is_file() or path==folder/'manifest.json':continue
        relative=path.relative_to(folder).as_posix()
        if any(part.startswith('.') for part in path.relative_to(folder).parts):raise ValueError('Hidden file in artifact')
        files.append({'path':relative,'size':path.stat().st_size,'sha256':sha256(path)})
    if not files or any(row['size']==0 for row in files):raise ValueError('Missing or empty artifact')
    return {'schema_version':1,'platform':platform_name,'godot_version':version,'game_version':'0.0.1','revision':revision,'files':files}


def verify_manifest(folder):
    folder=Path(folder).absolute()
    try:
        if folder.is_symlink():raise ValueError('Symlink artifact directory')
        folder=folder.resolve();manifest=folder/'manifest.json'
        if manifest.is_symlink() or manifest.stat().st_size>1024*1024:raise ValueError('Invalid manifest file')
        data=json.loads(manifest.read_text())
        if not isinstance(data,dict) or data.get('schema_version')!=1 or not isinstance(data.get('files'),list) or not 0<len(data['files'])<=1024:raise ValueError('Invalid manifest schema')
        seen=set()
        for row in data['files']:
            if not isinstance(row,dict) or set(row)!={'path','size','sha256'}:raise ValueError('Invalid file entry')
            name=row['path']
            if not isinstance(name,str) or not name or '\\' in name or Path(name).is_absolute() or any(part in ['..','.'] or part.startswith('.') for part in name.split('/')) or name in seen:raise ValueError('Unsafe manifest path')
            seen.add(name);path=folder/name
            if any(p.is_symlink() for p in [path,*path.parents] if p!=folder and p.is_relative_to(folder)):raise ValueError('Symlink artifact')
            if not path.resolve().is_relative_to(folder) or not path.is_file():raise ValueError('Missing artifact')
            if type(row['size']) is not int or row['size']<=0 or path.stat().st_size!=row['size'] or not isinstance(row['sha256'],str) or not re.fullmatch('[0-9a-f]{64}',row['sha256']) or sha256(path)!=row['sha256']:raise ValueError('Artifact checksum/size mismatch: '+name)
        all_paths=list(folder.rglob('*'))
        if any(p.is_symlink() for p in all_paths):raise ValueError('Symlink artifact')
        actual={p.relative_to(folder).as_posix() for p in all_paths if p.is_file() and p!=manifest}
        if actual!=seen:raise ValueError('Unlisted artifact files')
        return {'ok':True,'manifest':data}
    except (OSError,ValueError,TypeError,KeyError) as error:return {'ok':False,'reason':str(error)}


def package(folder,target,replace=False):
    folder=Path(folder).absolute();target=Path(target).absolute()
    checked=verify_manifest(folder)
    if not checked['ok']:raise ValueError(checked['reason'])
    folder=folder.resolve()
    if any(p.is_symlink() for p in [target,*target.parents]) or target.resolve().is_relative_to(folder):raise ValueError('Package output overlaps artifact or symlink')
    safe_root(target.parent)
    if target.suffix.lower()!='.zip' or not re.fullmatch(r'[A-Za-z0-9._ -]+',target.name):raise ValueError('Unsafe package name')
    sums=target.parent/'SHA256SUMS';known={}
    if sums.is_symlink():raise ValueError('Invalid checksum file')
    if sums.exists():
        if sums.stat().st_size>1024*1024:raise ValueError('Invalid checksum file')
        for line in sums.read_text().splitlines():
            match=re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9._ -]+)',line)
            if not match:raise ValueError('Invalid checksum entry')
            known[match[2]]=match[1]
    if target.exists() and not replace:raise FileExistsError(str(target))
    if not target.parent.is_dir():raise ValueError('Package parent does not exist')
    fd,name=tempfile.mkstemp(prefix=target.name+'.tmp-',dir=target.parent);os.close(fd);temporary=Path(name)
    try:
        with zipfile.ZipFile(temporary,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
            for name in sorted([row['path'] for row in checked['manifest']['files']]+['manifest.json']):
                path=folder/name;info=zipfile.ZipInfo(name,date_time=(1980,1,1,0,0,0))
                info.compress_type=zipfile.ZIP_DEFLATED
                info.external_attr=(0o100755 if os.access(path,os.X_OK) else 0o100644)<<16
                with path.open('rb') as source,archive.open(info,'w') as dest:
                    import shutil
                    shutil.copyfileobj(source,dest,1024*1024)
        os.replace(temporary,target)
        known[target.name]=sha256(target)
        atomic_text(sums,''.join(known[name]+'  '+name+'\n' for name in sorted(known)))
    finally:temporary.unlink(missing_ok=True)
    return {'ok':True,'path':str(target),'sha256':sha256(target),'size':target.stat().st_size}


def build(rows,version,templates,timeout,replace=False):
    results=[]
    for row in rows:
        # Revalidate descendants at execution time, not only the planned root.
        output=Path(row['output'])
        safe_root(output.parent)
        safe_root(output.parent.parent/'logs'/row['platform'])
        if output.is_symlink():raise ValueError('Symlink export destination')
        expected=Path(templates)/PRESETS[row['platform']][2]
        if not expected.is_file():raise ValueError('Missing export template: '+str(expected))
    revision=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,capture_output=True,text=True,timeout=5).stdout.strip()
    for row in rows:
        output=Path(row['output']);folder=output.parent
        if folder.exists() and any(folder.iterdir()):
            if not replace:raise FileExistsError('Build output exists: '+str(folder))
            # Replacement accepts only a previously verified, self-contained artifact.
            checked=verify_manifest(folder)
            if not checked['ok']:raise ValueError('Refusing to replace unverified directory')
            for entry in checked['manifest']['files']:(folder/entry['path']).unlink()
            (folder/'manifest.json').unlink()
        folder.mkdir(parents=True,exist_ok=True)
        logs=folder.parent/'logs'/row['platform'];logs.mkdir(parents=True,exist_ok=True)
        command=row['command'][:];command[1:1]=['--log-file',str(logs/'godot.log')]
        result=run_case('export',command,logs,timeout)
        if result['status']!='passed' or not output.is_file() or output.stat().st_size==0:
            raise ValueError('Export failed or artifact missing: '+str(logs))
        manifest=make_manifest(folder,row['platform'],version,revision)
        atomic_text(folder/'manifest.json',json.dumps(manifest,indent=2)+'\n')
        results.append({'platform':row['platform'],'output':str(output),'manifest':str(folder/'manifest.json')})
    return results


def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='action',required=True)
    for action in ['plan','build']:
        p=sub.add_parser(action);p.add_argument('--platform',action='append',choices=list(PRESETS),default=[]);p.add_argument('--build-root',type=Path,default=ROOT/'build');p.add_argument('--timeout',type=valid_timeout,default=300);p.add_argument('--replace',action='store_true')
    p=sub.add_parser('verify');p.add_argument('folder',type=Path)
    p=sub.add_parser('package');p.add_argument('folder',type=Path);p.add_argument('output',type=Path);p.add_argument('--replace',action='store_true')
    args=parser.parse_args()
    try:
        if args.action=='verify':result=verify_manifest(args.folder)
        elif args.action=='package':result=package(args.folder,args.output,args.replace)
        else:
            binary='godot' if args.action=='plan' else godot_binary()
            rows=plan(args.platform or list(PRESETS),args.build_root,binary)
            if args.action=='plan':result={'ok':True,'builds':rows}
            else:
                version=engine_version(binary);result={'ok':True,'builds':build(rows,version,template_directory(version),args.timeout,args.replace)}
        print(json.dumps(result));return 0 if result['ok'] else 2
    except (OSError,ValueError,subprocess.TimeoutExpired) as error:print(json.dumps({'ok':False,'reason':str(error)}));return 2

if __name__=='__main__':sys.exit(main())
