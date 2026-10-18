"""Real archive analysis CLI and raw library export contracts."""
import json
from pathlib import Path
import tempfile
from test_bot_cli import run

def main():
    with tempfile.TemporaryDirectory() as temporary:
        root=Path(temporary).resolve();source=root/'source.json'
        run(root,'simulate','--shots','2','--record',str(source))
        report=run(root,'analyze-replay','--replay',str(source))[0]
        assert report['ok'] and len(report['shots'])==2 and report['action_count']==2,report
        target=root/'report.json';run(root,'analyze-replay','--replay',str(source),'--output',str(target))
        assert json.loads(target.read_text())==report
        target=root/'players.csv';run(root,'analyze-replay','--replay',str(source),'--analysis-format','players','--output',str(target))
        assert target.read_text().startswith('id,name,team,shots')
        compare=run(root,'compare-replays','--replay',str(source),'--replay-other',str(source))[0]
        assert compare['same_initial'] and compare['same_final'] and compare['duration_delta']==0
        before=source.read_bytes()
        assert not run(root,'analyze-replay','--replay',str(source),'--output',str(source),code=2)[0]['ok']
        assert source.read_bytes()==before
        alias=root/'alias';alias.symlink_to(root,target_is_directory=True)
        assert not run(root,'analyze-replay','--replay',str(source),'--output',str(alias/'source.json'),code=2)[0]['ok']
        assert source.read_bytes()==before
        run(root,'analyze-replay','--analysis-format','wrong',code=2)
        run(root,'compare-replays','--replay',str(source),code=2)
        run(root,'library','--sort','wrong',code=2)
    print('Analysis CLI: exact report, CSV, compare, input protection and invalid args passed')

if __name__=='__main__':main()
