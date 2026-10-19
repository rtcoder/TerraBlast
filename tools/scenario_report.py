"""Validated, portable scenario reports and escaped offline exports."""
import csv
import hashlib
import html
import io
import json
import math
import re
import statistics
from urllib.parse import quote
from pathlib import PurePosixPath
from collections import Counter, defaultdict

STATUSES = {'pending', 'passed', 'failed', 'timeout', 'interrupted', 'skipped', 'log_limit'}

def finite_number(value):
    if type(value) not in (int,float):return False
    try:return math.isfinite(value)
    except (OverflowError,ValueError):return False

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False)

def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()

def validate_summary(value):
    if not isinstance(value, dict) or not all(k in value for k in ('map','seed','shots','deltas','terrain_hash','state')):
        raise ValueError('missing simulation summary fields')
    if not isinstance(value['map'], str) or not isinstance(value['state'], dict):
        raise ValueError('invalid summary map/state')
    for key in ('seed','shots','deltas'):
        if type(value[key]) is not int or value[key] < 0: raise ValueError('invalid summary '+key)
    if not isinstance(value['terrain_hash'], str) or not value['terrain_hash']: raise ValueError('invalid terrain hash')
    canonical(value)
    return value

def validate_report(value):
    if not isinstance(value, dict) or value.get('schema_version') != 1 or type(value.get('schema_version')) is not int:
        raise ValueError('unsupported report schema')
    rows = value.get('tests')
    if not isinstance(rows, list) or len(rows) > 128: raise ValueError('invalid report case count')
    ids = set()
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get('id'),str) or row['id'] in ids: raise ValueError('invalid/duplicate case ID')
        ids.add(row['id'])
        if row.get('status') not in STATUSES: raise ValueError('invalid status')
        duration = row.get('duration_seconds',0)
        if not finite_number(duration) or duration < 0: raise ValueError('invalid duration')
        if not isinstance(row.get('config_digest'),str) or not re.fullmatch('[0-9a-f]{64}',row['config_digest']) or not isinstance(row.get('config'),dict): raise ValueError('invalid case config')
        if digest(row['config'])!=row['config_digest']:raise ValueError('config digest mismatch')
        if row.get('summary') is not None: validate_summary(row['summary'])
        metrics(row)
        if row['status']=='passed' and not row.get('summary'): raise ValueError('passed case lacks summary')
        if not isinstance(row.get('artifacts',[]),list): raise ValueError('invalid artifacts')
        for artifact in row.get('artifacts',[]):
            if not isinstance(artifact,dict) or type(artifact.get('size')) is not int or artifact['size']<0 or not isinstance(artifact.get('sha256'),str) or not re.fullmatch('[0-9a-f]{64}',artifact['sha256']) or not isinstance(artifact.get('path'),str):raise ValueError('invalid artifact metadata')
    canonical(value)
    return value

def state_digest(row):
    summary=row.get('summary',{})
    return digest({'state':summary.get('state'), 'terrain_hash':summary.get('terrain_hash')})

def metrics(row):
    result={k:0 for k in ('shots','hits','damage','kills')}
    stats=row.get('summary',{}).get('state',{}).get('statistics',{})
    values=stats.values() if isinstance(stats,dict) else []
    for player in values:
        if not isinstance(player,dict): continue
        for key in result:
            v=player.get(key,0)
            if not finite_number(v) or v<0: raise ValueError('invalid statistic '+key)
            result[key]+=v
    return result

def summarize(report, filters=None):
    validate_report(report)
    filters=filters or {}
    rows=[r for r in report['tests'] if (not filters.get('status') or r['status']==filters['status']) and (not filters.get('map') or r['config'].get('map')==filters['map'])]
    counts=dict(Counter(r['status'] for r in rows)); outcomes=Counter(); totals=Counter(); groups=defaultdict(list); aggregates=defaultdict(lambda:{'cases':0,'outcomes':Counter(),'deltas':0,'terrain_hashes':set()})
    for row in rows:
        totals.update(metrics(row))
        state=row.get('summary',{}).get('state',{})
        outcome='team_'+str(state['winner_team']) if state.get('status')=='ended' and state.get('winner_team') in (0,1,2) else 'unresolved'
        outcomes[outcome]+=1
        key=canonical({k:row['config'].get(k) for k in ('map','preset','players')});aggregate=aggregates[key]
        aggregate['cases']+=1;aggregate['outcomes'][outcome]+=1;aggregate['deltas']+=row.get('summary',{}).get('deltas',0)
        if row.get('summary'):aggregate['terrain_hashes'].add(row['summary']['terrain_hash'])
        if row['status']=='passed':groups[row['config_digest']].append(row)
    timings=sorted(r.get('duration_seconds',0) for r in rows)
    nondeterministic=[{'config_digest':key,'cases':[r['id'] for r in group]} for key,group in sorted(groups.items()) if len({state_digest(r) for r in group})>1]
    return {'counts':counts,'outcomes':dict(outcomes),'metrics':dict(totals),'groups':[{**json.loads(key),**{k:v for k,v in value.items() if k!='terrain_hashes'},'terrain_hashes':sorted(value['terrain_hashes'])} for key,value in sorted(aggregates.items())],'timing':{'min':min(timings,default=0),'max':max(timings,default=0),'median':statistics.median(timings) if timings else 0,'p95':timings[math.ceil(len(timings)*.95)-1] if timings else 0},'nondeterministic':nondeterministic}

def compare_reports(first, second, time_relative=.2, time_absolute=.1, strict=True):
    validate_report(first);validate_report(second)
    for threshold in (time_relative,time_absolute):
        if not finite_number(threshold) or threshold<0:raise ValueError('invalid comparison threshold')
    a={r['id']:r for r in first['tests']};b={r['id']:r for r in second['tests']};changes=[]
    for key in sorted(a.keys()-b.keys()):changes.append({'id':key,'kind':'removed','regression':strict})
    for key in sorted(b.keys()-a.keys()):changes.append({'id':key,'kind':'added','regression':b[key]['status']!='passed'})
    for key in sorted(a.keys()&b.keys()):
        x,y=a[key],b[key]
        comparable=x['status']=='passed' and y['status']=='passed'
        for kind,changed in [('config',x['config_digest']!=y['config_digest']),('status',x['status']!=y['status']),('state',state_digest(x)!=state_digest(y)),('shots',x.get('summary',{}).get('shots')!=y.get('summary',{}).get('shots')),('damage',metrics(x)['damage']!=metrics(y)['damage'])]:
            if kind in ('state','shots','damage') and not comparable:continue
            if changed:
                before,after=({'shots':x.get('summary',{}).get('shots'),'damage':metrics(x)['damage'],'status':x['status'],'state':state_digest(x),'config':x['config_digest']}[kind],{'shots':y.get('summary',{}).get('shots'),'damage':metrics(y)['damage'],'status':y['status'],'state':state_digest(y),'config':y['config_digest']}[kind])
                changes.append({'id':key,'kind':kind,'before':before,'after':after,'regression':kind!='status' or y['status']!='passed'})
        old=x.get('duration_seconds',0);new=y.get('duration_seconds',0)
        if comparable and new-old>time_absolute and new>old*(1+time_relative):changes.append({'id':key,'kind':'timing','before':old,'after':new,'regression':True})
        if y['status']!='passed' and x['status']==y['status']:changes.append({'id':key,'kind':'failure','regression':True})
    return {'schema_version':1,'ok':not any(c['regression'] for c in changes),'changes':changes,'matched':sorted(a.keys()&b.keys()),'environment_changed':first.get('environment')!=second.get('environment'),'manifest_changed':first.get('manifest_digest')!=second.get('manifest_digest')}

def table_rows(report):
    validate_report(report)
    return [['case_id','map','status','duration_seconds','reason','shots','damage','deltas','log']]+[[r['id'],r['config'].get('map',''),r['status'],r.get('duration_seconds',0),r.get('reason',''),r.get('summary',{}).get('shots',0),metrics(r)['damage'],r.get('summary',{}).get('deltas',0),r.get('log_path','')] for r in report['tests']]

def to_csv(report):
    output=io.StringIO();writer=csv.writer(output)
    for row in table_rows(report):writer.writerow([("'"+str(v)) if str(v).startswith(('=','+','-','@','\t','\r')) else v for v in row])
    return output.getvalue()

def to_markdown(report):
    rows=table_rows(report)
    escape=lambda v:str(v).replace('\\','\\\\').replace('|','\\|').replace('\n','<br>').replace('<','&lt;').replace('>','&gt;')
    lines=[]
    for index,row in enumerate([rows[0],['---']*len(rows[0])]+rows[1:]):
        cells=[escape(v) for v in row]
        if index>1 and row[-1]:
            path=PurePosixPath(str(row[-1]))
            if not path.is_absolute() and '..' not in path.parts:cells[-1]='[log]('+quote(str(path),safe='/')+')'
        lines.append('| '+' | '.join(cells)+' |')
    return '\n'.join(lines)+'\n'

def to_html(report):
    rows=table_rows(report)
    cells=lambda row,tag:'<tr>'+''.join('<'+tag+'>'+html.escape(str(v))+'</'+tag+'>' for v in row)+'</tr>'
    return '<!doctype html><meta charset="utf-8"><title>Scenario report</title><style>body{font:16px system-ui;margin:2rem}td,th{padding:.5rem;text-align:left;border-bottom:1px solid #ccc}table{border-collapse:collapse}</style><h1>Scenario report</h1><label>Status <select id="status"><option value="">All</option>'+''.join('<option>'+s+'</option>' for s in sorted(STATUSES))+'</select></label><table><thead>'+cells(rows[0],'th')+'</thead><tbody>'+''.join(cells(r,'td') for r in rows[1:])+'</tbody></table><script>document.querySelector("select").onchange=function(){for(const r of document.querySelectorAll("tbody tr"))r.hidden=!!this.value&&r.cells[2].textContent!==this.value;};</script>'
