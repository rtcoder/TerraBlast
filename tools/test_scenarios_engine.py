"""Small real-engine matrix: record, verify and resume two deterministic cases."""
import tempfile
import unittest
from pathlib import Path
import scenarios as S
import scenario_report as R

class EngineMatrix(unittest.TestCase):
    def test_real_matrix(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory).resolve()/'matrix'
            manifest=S.load_json(S.ROOT/'tools/scenarios/smoke.json')
            result=S.run_matrix(manifest,root,S.godot_binary(),jobs=2,timeout=60,verify=True)
            self.assertTrue(result['ok'],result)
            self.assertEqual(len(result['tests']),2)
            self.assertTrue(all(r['verified'] for r in result['tests']))
            self.assertFalse(R.summarize(result)['nondeterministic'])
            second=S.run_matrix(manifest,root,S.godot_binary(),resume=True,verify=True)
            self.assertTrue(R.compare_reports(result,second)['ok'])

if __name__=='__main__':unittest.main()
