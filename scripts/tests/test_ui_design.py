"""nibble's adapter and required documentation command use the shared module."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_ui_design
from ui_design import snapshot


class DesignAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'app').mkdir()
        (self.root / 'app' / 'View.swift').write_text('struct Example {}\n')
        docs = self.root / 'docs/design'
        docs.mkdir(parents=True)
        (docs / 'components.md').write_text('| ID | Meaning |\n| --- | --- |\n| C01 Example | Content |\n')
        policy = {
            'version': 1, 'record': 'docs/design/review.json',
            'inputs': [{'path': 'app', 'kind': 'tree'}, {'path': 'docs/design', 'kind': 'tree', 'references': True}],
            'registries': [{'prefix': 'C', 'path': 'docs/design/components.md', 'format': 'table', 'columns': 2}],
        }
        (docs / 'policy.json').write_text(json.dumps(policy))
        record = snapshot(self.root, 'docs/design/policy.json', 'Reviewed component structure.', ['docs/design/components.md'])
        (docs / 'review.json').write_text(json.dumps(record))

    def run_command(self, script, *args):
        path = Path(__file__).resolve().parents[1] / script
        return subprocess.run([sys.executable, str(path), '--root', str(self.root), *args],
                              text=True, capture_output=True, check=False)

    def test_adapter_command_and_python_call_pass(self):
        self.assertEqual(check_ui_design.check(self.root)['errors'], [])
        result = self.run_command('check_ui_design.py', 'check')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_required_documentation_command_detects_stale_review(self):
        (self.root / 'app' / 'View.swift').write_text('changed')
        result = self.run_command('check_docs.py')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('Unreviewed changed input: app/View.swift', result.stdout)

    def test_adapter_does_not_allow_overriding_product_policy(self):
        for option in ('--config', '--conf'):
            with self.subTest(option=option):
                result = self.run_command('check_ui_design.py', option, 'other.json', 'check')
                self.assertEqual(result.returncode, 2)

    def test_missing_policy_cannot_disable_required_check(self):
        (self.root / 'docs/design/policy.json').unlink()
        result = self.run_command('check_docs.py')
        self.assertEqual(result.returncode, 1)
        self.assertIn('policy.json', result.stderr)


if __name__ == '__main__':
    unittest.main()
