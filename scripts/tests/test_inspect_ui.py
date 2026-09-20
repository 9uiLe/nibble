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

    def test_stdout_contains_one_report_and_hamio_status_is_on_stderr(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'ui.json'
            source.write_text(json.dumps({'entries': [{'uniqueId': 'body', 'value': ' 原文\n'}]}))
            result = self.execute('tree', source, '--id', 'body', '--text-limit', '0')
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report['elements']['items'][0]['value'], ' 原文\n')
        self.assertEqual(report['schema_version'], 1)
        display = json.loads(result.stderr.splitlines()[-1])
        self.assertTrue(display['blocks'][0]['success'])
        if os.environ.get('NIBBLE_REQUIRE_HAMIO') == '1':
            self.assertEqual(display['apiVersion'], 1)
            self.assertNotIn('fallback', result.stderr)

    def test_processing_errors_produce_no_success_data(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'ui.json'
            for contents in ('{"ok":false}', '{"entries": [null]}', 'not-json'):
                source.write_text(contents)
                with self.subTest(contents=contents):
                    result = self.execute('tree', source)
                    self.assertEqual(result.returncode, 1)
                    self.assertEqual(result.stdout, '')
                    self.assertEqual(json.loads(result.stderr.splitlines()[-1])['blocks'][0]['level'], 'error')

    def test_help_and_argument_errors_belong_to_parser(self):
        for arguments in (('--help',), ('tree', '--help'), ('image', '--help')):
            result = self.execute(*arguments)
            self.assertEqual(result.returncode, 0)
            self.assertIn('usage:', result.stdout)
            self.assertEqual(result.stderr, '')
        result = self.execute('image', 'input.png')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertIn('--output', result.stderr)

    def test_documented_sample_compares_exact_input_values(self):
        result = self.execute('tree', SCRIPTS / 'examples/ui-after.json',
                              '--before', SCRIPTS / 'examples/ui-before.json',
                              '--id', 'fixture.input', '--text-limit', '0')
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report['added']['items'][0]['value'], '  日本語 👩🏽‍💻\nHello, nibble!  ')
        self.assertEqual(report['removed']['items'][0]['value'], '')
        self.assertFalse(report['context_changed'])


if __name__ == '__main__':
    unittest.main()
