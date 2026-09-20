"""CLI contracts: parseable result data, hamio status, help and failure exit codes."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]


class InspectionCLITests(unittest.TestCase):
    def execute(self, *arguments):
        return subprocess.run([sys.executable, str(SCRIPTS / 'inspect_ui.py'), *map(str, arguments)],
                              capture_output=True, text=True, timeout=20,
                              env={**os.environ, 'NIBBLE_UI_FORMAT': 'json'})

    def test_processing_errors_produce_no_success_data(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'ui.json'
            source.write_text('{"entries": [null]}')
            result = self.execute('tree', source)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertEqual(json.loads(result.stderr.splitlines()[-1])['blocks'][0]['level'], 'error')

    def test_help_and_argument_errors_belong_to_parser(self):
        result = self.execute('--help')
        self.assertEqual(result.returncode, 0)
        self.assertIn('usage:', result.stdout)
        self.assertEqual(result.stderr, '')
        result = self.execute('image', 'input.png')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertIn('--output', result.stderr)

    def test_documented_sample_emits_exact_diff_and_separates_hamio_status(self):
        result = self.execute('tree', SCRIPTS / 'examples/ui-after.json',
                              '--before', SCRIPTS / 'examples/ui-before.json',
                              '--id', 'fixture.input', '--text-limit', '0')
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report['added']['items'][0]['value'], '  日本語 👩🏽‍💻\nHello, nibble!  ')
        self.assertEqual(report['removed']['items'][0]['value'], '')
        self.assertFalse(report['context_changed'])
        self.assertEqual(report['schema_version'], 1)
        display = json.loads(result.stderr.splitlines()[-1])
        self.assertTrue(display['blocks'][0]['success'])
        if os.environ.get('NIBBLE_REQUIRE_HAMIO') == '1':
            self.assertEqual(display['apiVersion'], 1)
            self.assertNotIn('fallback', result.stderr)


if __name__ == '__main__':
    unittest.main()
