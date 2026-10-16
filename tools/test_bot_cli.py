"""Public bot simulation, replay export and strict argument regressions."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from devtools import ROOT


def run(directory, *args, code=0):
    result = subprocess.run(
        [sys.executable, str(ROOT / 'tools/launch.py'), *args],
        cwd=directory, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    assert result.returncode == code, (args, result.returncode, output)
    assert 'SCRIPT ERROR' not in output, output
    return [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]


def main():
    with tempfile.TemporaryDirectory(prefix='terrablast-bot-cli-') as temporary:
        directory = Path(temporary)
        for arena in ('twin_forts', 'two_islands'):
            summaries = []
            for attempt in range(2):
                archive = directory / f'{arena} replay {attempt}.json'
                summary_file = directory / f'{arena} summary {attempt}.json'
                summary = run(directory, 'simulate', '--map', arena, '--bots', 'easy',
                              '--shots', '4', '--record', str(archive), '--output', str(summary_file))[0]
                assert summary == json.loads(summary_file.read_text())
                assert summary['bot_difficulty'] == 'easy'
                assert summary['bot_decisions'] == summary['shots'] > 0
                assert len(summary['terrain_hash']) == 64
                recording = json.loads(archive.read_text())
                assert len(recording['recording']['actions']) == summary['shots']
                verified = run(directory, 'replay', '--replay', str(archive))[0]
                assert verified['ok'] and verified['reason'] == 'verified'
                assert verified['state'] == summary['state']
                summaries.append(summary)
            assert summaries[0] == summaries[1], arena
        normal = run(directory, 'simulate', '--bots', 'normal', '--shots', '2')[0]
        assert normal['bot_difficulty'] == 'normal' and normal['bot_decisions'] > 0
        default = run(directory, 'simulate', '--shots', '2', '--record', str(directory / 'default.json'))[0]
        assert default['bot_decisions'] == 0 and default['bot_difficulty'] == ''
        assert run(directory, 'replay', '--replay', str(directory / 'default.json'))[0]['ok']
        corrupted = directory / 'corrupted.json'
        recording['expected_hash'] = '0' * 64
        corrupted.write_text(json.dumps(recording))
        assert not run(directory, 'replay', '--replay', str(corrupted), code=2)[0]['ok']
        for args in (
            ('simulate', '--bots', 'hard'), ('simulate', '--bots'),
            ('simulate', '--record'), ('server', '--record', str(directory / 'invalid.json')),
            ('server', '--bots', 'easy'), ('simulate', '--bots', 'easy', '--bots', 'normal'),
            ('simulate', '--record', str(directory / 'same.json'), '--output', str(directory / 'same.json')),
            ('simulate', '--shots', '1', '--record', os.path.relpath(directory / 'alias.json', ROOT / 'game'),
             '--output', str(directory / 'alias.json')),
            ('simulate', '--bots', 'easy', '--shots', '1', '--output', str(directory / 'missing/summary.json')),
            ('simulate', '--shots', '1', '--record', str(directory / 'missing/replay.json')),
        ):
            run(directory, *args, code=2)
    print('Bot CLI: both arenas deterministic, normal/default, replay verification and invalid outputs passed')


if __name__ == '__main__':
    main()
