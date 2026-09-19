"""Test the actual display protocol and CLI boundaries without Apple credentials."""

from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
from script_ui import Reporter
import script_ui

SCRIPTS = Path(__file__).resolve().parents[1]


class ReporterTests(unittest.TestCase):
    def setUp(self):
        self.reporter = Reporter()
        self.out, self.err = io.StringIO(), io.StringIO()

    def test_json_is_checked_and_routed_only_to_stderr_without_ambient_secrets(self):
        block = {'kind': 'result', 'success': False, 'message': '検査失敗'}
        result = Mock(returncode=0, stdout=json.dumps({'apiVersion': 1, 'status': 'ok', 'blocks': [block]}), stderr='')
        with patch.dict(os.environ, {'NIBBLE_UI_FORMAT': 'json', 'GH_TOKEN': 'FAKE_SECRET',
                                     'ASC_KEY_ID': 'FAKE_PRIVATE', 'PYTHONPATH': '/untrusted'}), \
                patch.object(script_ui.shutil, 'which', return_value='/locked/bin/hamio'), \
                patch.object(script_ui.subprocess, 'run', return_value=result) as process, \
                redirect_stdout(self.out), redirect_stderr(self.err):
            self.reporter.result(False, '検査失敗')
        self.assertEqual(self.out.getvalue(), '')
        self.assertEqual(json.loads(self.err.getvalue())['blocks'], [block])
        call = process.call_args
        self.assertEqual(call.args[0], ['/locked/bin/hamio', 'render', '--format', 'json', '--color', 'never'])
        self.assertEqual(json.loads(call.kwargs['input']), {'apiVersion': 1, 'blocks': [block]})
        self.assertTrue(0 < call.kwargs['timeout'] < float('inf'))
        for key in ['GH_TOKEN', 'ASC_KEY_ID', 'PYTHONPATH', 'HOME']:
            self.assertNotIn(key, call.kwargs['env'])

    def test_missing_hung_failed_or_malformed_display_falls_back_once(self):
        cases = [OSError('FAKE_PRIVATE_PATH'), subprocess.TimeoutExpired('FAKE_PRIVATE_ARG', 3),
                 Mock(returncode=7, stdout='FAKE_PRIVATE_STDOUT', stderr='FAKE_PRIVATE_STDERR'),
                 Mock(returncode=0, stdout='[]', stderr=''),
                 Mock(returncode=0, stdout='{"apiVersion":2,"status":"ok"}', stderr=''),
                 Mock(returncode=0, stdout='{"apiVersion":1,"status":"ok"}', stderr=''),
                 Mock(returncode=0, stdout='{"apiVersion":1,"status":"ok","blocks":[]}', stderr='')]
        for failure in cases:
            with self.subTest(failure=repr(failure)), patch.dict(os.environ, {'NIBBLE_UI_FORMAT': 'json'}), \
                    patch.object(script_ui.shutil, 'which', return_value='/locked/bin/hamio'), \
                    patch.object(script_ui.subprocess, 'run') as process, redirect_stderr(io.StringIO()) as err:
                if isinstance(failure, Exception):
                    process.side_effect = failure
                else:
                    process.return_value = failure
                reporter = Reporter()
                reporter.result(False, 'Business failed')
                reporter.result(True, 'Later operation passed')
                self.assertEqual(process.call_count, 1)
                lines = err.getvalue().splitlines()
                self.assertIn('hamio display unavailable', lines[0])
                self.assertFalse(json.loads(lines[1])['blocks'][0]['success'])
                self.assertTrue(json.loads(lines[2])['blocks'][0]['success'])
                self.assertNotIn('FAKE_PRIVATE', err.getvalue())

    def test_missing_binary_and_invalid_mode_do_not_start_a_process(self):
        for mode, binary in [('json', None), ('invalid', '/locked/bin/hamio')]:
            with self.subTest(mode=mode), patch.dict(os.environ, {'NIBBLE_UI_FORMAT': mode}), \
                    patch.object(script_ui.shutil, 'which', return_value=binary), \
                    patch.object(script_ui.subprocess, 'run') as process, redirect_stderr(io.StringIO()) as err:
                Reporter().message('public')
                process.assert_not_called()
                self.assertIn('"display": "fallback"', err.getvalue())

    def test_step_propagates_original_failure_and_never_displays_exception(self):
        for failure in [ValueError('FAKE_SECRET'), KeyboardInterrupt()]:
            with self.subTest(failure=type(failure)), patch.object(self.reporter, '_render') as render:
                with self.assertRaises(type(failure)) as caught:
                    with self.reporter.step('archive'):
                        raise failure
                self.assertIs(caught.exception, failure)
                blocks = [call.args[0][0] for call in render.call_args_list]
                self.assertEqual([block['text'] for block in blocks], ['archive: 開始', 'archive: 未完了'])
                self.assertNotIn('FAKE_SECRET', str(blocks))

    def test_long_unicode_diagnostics_are_preserved_within_string_limit(self):
        text = '🙂' * 1025
        with patch.object(self.reporter, '_render') as render:
            self.reporter.message(text, 'error')
        parts = [call.args[0][0]['text'] for call in render.call_args_list]
        self.assertEqual(''.join(parts), text)
        self.assertTrue(all(len(part.encode()) <= 4096 for part in parts))

    def test_closed_terminal_does_not_turn_completion_into_a_retry(self):
        terminal = Mock()
        terminal.write.side_effect = BrokenPipeError()
        reporter = Reporter()
        reporter._unavailable = True
        completed = []
        with patch.object(sys, 'stderr', terminal):
            with reporter.step('upload'):
                completed.append('once')
        self.assertEqual(completed, ['once'])

    def test_ci_uses_json_even_when_stderr_is_a_terminal(self):
        block = {'kind': 'message', 'level': 'info', 'text': 'check'}
        result = Mock(returncode=0, stdout=json.dumps({'apiVersion': 1, 'status': 'ok', 'blocks': [block]}), stderr='')
        with patch.dict(os.environ, {'CI': 'true', 'NIBBLE_UI_FORMAT': ''}), \
                patch.object(script_ui.shutil, 'which', return_value='/locked/bin/hamio'), \
                patch.object(script_ui.subprocess, 'run', return_value=result) as process, \
                redirect_stderr(self.err), patch.object(self.err, 'isatty', return_value=True):
            self.reporter.message('check')
        self.assertEqual(process.call_args.args[0][2:4], ['--format', 'json'])


class InstalledHamioTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.hamio = shutil.which('hamio')
        if not cls.hamio:
            if os.environ.get('NIBBLE_REQUIRE_HAMIO') == '1':
                raise AssertionError('Supported Nix checks must exercise the installed hamio binary')
            raise unittest.SkipTest('hamio unavailable; run the supported locked Nix environment')

    def execute(self, arguments, **kwargs):
        return subprocess.run([sys.executable, *map(str, arguments)], text=True, capture_output=True,
                              timeout=20, env={**os.environ, 'NIBBLE_UI_FORMAT': 'json'}, **kwargs)

    def test_actual_hamio_version_contract_and_display_of_business_failure(self):
        result = self.execute(['-c', 'from script_ui import ui; ui.result(False, "失敗を表示"); print("payload"); raise SystemExit(23)'], cwd=SCRIPTS)
        self.assertEqual(result.returncode, 23)
        self.assertEqual(result.stdout, 'payload\n')
        response = json.loads(result.stderr)
        self.assertEqual(response['status'], 'ok')
        self.assertFalse(response['blocks'][0]['success'])

    def test_human_display_has_no_protocol_acknowledgement_on_stdout(self):
        result = subprocess.run([sys.executable, '-c', 'from script_ui import ui; ui.result(True, "検査完了")'],
                                cwd=SCRIPTS, capture_output=True, text=True, timeout=20,
                                env={**os.environ, 'NIBBLE_UI_FORMAT': 'human', 'NO_COLOR': '1'})
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertIn('検査完了', result.stderr)
        self.assertNotIn('fallback', result.stderr)
        self.assertNotIn('\x1b', result.stderr)

    def test_swift_check_reports_real_success_and_failure_exit_codes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'app').mkdir()
            source = root / 'app/Example.swift'
            source.write_text('import SwiftUI\nstruct Invalid: View { var body: some View { Text("x") } }')
            failed = self.execute([SCRIPTS / 'check_swift_policy.py', '--root', root])
            self.assertEqual(failed.returncode, 1, failed.stderr)
            self.assertEqual(failed.stdout, '')
            self.assertIn('app/Example.swift:2:1: error:', failed.stderr)
            self.assertFalse(json.loads(failed.stderr.splitlines()[0])['blocks'][0]['success'])
            source.write_text('struct Value: Equatable { let count: Int }')
            passed = self.execute([SCRIPTS / 'check_swift_policy.py', '--root', root])
            self.assertEqual(passed.returncode, 0, passed.stderr)
            self.assertTrue(json.loads(passed.stderr)['blocks'][0]['success'])

    def test_isolated_archive_check_loads_only_reviewed_display_and_preserves_json(self):
        from test_testflight import make_archive
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            make_archive(root / 'fixture.xcarchive')
            (root / 'script_ui.py').write_text('raise RuntimeError("UNTRUSTED_IMPORT")')
            result = self.execute(['-I', SCRIPTS / 'testflight.py', 'archive-check', root / 'fixture.xcarchive'], cwd=root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['metadata']['bundle_id'], 'nibble.9uiLe.com')
            # Missing archive takes the non-secret error path and never reads credentials.
            failed = self.execute(['-I', SCRIPTS / 'testflight.py', 'archive-check', root / 'absent'], cwd=root)
            self.assertEqual(failed.returncode, 1)
            self.assertEqual(failed.stdout, '')
            self.assertFalse(json.loads(failed.stderr)['blocks'][0]['success'])
            self.assertNotIn(str(root), failed.stderr)


if __name__ == '__main__':
    unittest.main()
