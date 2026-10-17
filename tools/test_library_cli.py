"""Read-only library listing, exact verification, corrupt entry and mode guards."""
import json
from pathlib import Path
import tempfile
from test_bot_cli import run


def main():
    with tempfile.TemporaryDirectory(prefix='terrablast-library-cli-', dir=Path(tempfile.gettempdir()).resolve()) as temp:
        directory = Path(temp)
        archive = directory / 'replay.json'
        run(directory, 'simulate', '--shots', '1', '--record', str(archive))
        library = directory / 'library with spaces'
        library.mkdir()
        ident = 'a' * 32
        entry = {'format': 'terrablast_library', 'version': 1,
                 'metadata': {'id': ident, 'kind': 'replay', 'title': 'CLI replay', 'created': 1700000000},
                 'payload': json.loads(archive.read_text())}
        path = library / (ident + '.json')
        path.write_text(json.dumps(entry))
        before = path.read_bytes()
        listing = run(directory, 'library', '--library-dir', str(library))[0]
        assert listing['ok'] and len(listing['entries']) == 1, listing
        verified = run(directory, 'library', '--library-dir', str(library), '--verify-library')[0]
        assert verified['ok'] and verified['entries'][0]['verified'], verified
        assert path.read_bytes() == before
        entry['payload']['expected_hash'] = '0' * 64
        path.write_text(json.dumps(entry))
        assert not run(directory, 'library', '--library-dir', str(library), '--verify-library', code=2)[0]['ok']
        path.write_text('{invalid')
        broken = run(directory, 'library', '--library-dir', str(library), code=2)[0]
        assert not broken['ok'] and broken['errors'], broken
        run(directory, 'replay', '--library-dir', str(library), code=2)
        run(directory, 'library', '--library-dir', code=2)
        run(directory, 'library', '--lobby', code=2)
    print('Library CLI: list, verify, corruption, read-only and mode guards passed')


if __name__ == '__main__':
    main()
