"""Verification selection and fail-fast orchestration contracts, without Apple tools."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import verify


class SelectionTests(unittest.TestCase):
    def selected(self, paths, scope='auto'):
        return {step['id'] for step in verify.plan(paths, scope)['steps']}

    def test_docs_do_not_start_simulators(self):
        self.assertEqual(self.selected(['docs/ios-verification.md', 'AGENTS.md', '.agents/skills/example/SKILL.md']), {'static'})

    def test_static_tooling_changes_do_not_start_ios(self):
        self.assertEqual(self.selected(['scripts/check_docs.py', 'tools/ui-design/cli.py', '.github/workflows/check.yml']), {'static'})

    def test_saved_observation_tool_does_not_start_ios(self):
        self.assertEqual(self.selected(['scripts/ui_observation.py']), {'static'})
        for path in ('scripts/inspect_ui.py', 'scripts/ui_preview.py', 'scripts/tests/macos/test_ui_preview_native.py'):
            with self.subTest(path=path):
                self.assertEqual(self.selected([path]), {'static', 'preview-native'})
        self.assertEqual(self.selected([], 'inspection'), {'static', 'preview-native'})
        self.assertNotIn('--device', verify.command_for('preview-native', None))

    def test_test_only_changes_select_whole_target_suite_without_ui(self):
        self.assertEqual(self.selected(['app/NibbleTests/NoticeTests.swift']), {'static', 'product-test'})
        self.assertEqual(self.selected(['validation/VerificationAppTests/Tests.swift']), {'static', 'fixture-test'})

    def test_shared_config_and_unknown_changes_broaden_scope(self):
        for path in ['scripts/ios.py', 'flake.lock', 'new/config.json']:
            with self.subTest(path=path):
                selected = self.selected([path])
                self.assertTrue({'static', 'preview-native', 'fixture-test', 'fixture-smoke',
                                 'product-test', 'library-ui', 'notice-ui', 'interface-ui', 'about-ui', 'keyboard-guide-ui'} <= selected)
                self.assertNotIn('performance-test', selected)
        selected = verify.plan(['app/Shared/Domain/LibraryRequest.swift'])
        self.assertIn('product-test', self.selected(['app/Shared/Domain/LibraryRequest.swift']))
        self.assertTrue(selected['manual_review'])
        self.assertTrue(selected['preconditions'])

    def test_measurement_requires_explicit_scope(self):
        for path in ('validation/StoreBenchmark.swift', 'app/NibblePerformanceTests/Measurements.swift'):
            with self.subTest(path=path):
                result = verify.plan([path])
                self.assertEqual({step['id'] for step in result['steps']}, {'static'})
                self.assertTrue(result['manual_review'])
        self.assertEqual(self.selected([], 'performance'), {'static', 'performance-test'})
        self.assertNotIn('performance-test', self.selected([], 'regression'))
        self.assertEqual(self.selected(['app/TestSupport/RiveTestSupport.swift']), {'static', 'product-test'})
        self.assertIn('app/performance-project.json', verify.command_for('performance-test', 'explicit'))

    def test_ui_driver_changes_select_the_affected_flow(self):
        self.assertEqual(self.selected(['scripts/check_notice_ui.py']), {'static', 'notice-ui'})
        self.assertEqual(self.selected(['scripts/check_library_ui.py']), {'static', 'library-ui'})
        self.assertEqual(self.selected(['scripts/check_about_ui.py']), {'static', 'about-ui', 'keyboard-guide-ui'})
        self.assertEqual(verify.command_for('keyboard-guide-ui', 'explicit')[-2:], ['--story', 'keyboard'])
        result = verify.plan(['README.md'], 'fixture')
        self.assertEqual({step['id'] for step in result['steps']}, {'static', 'fixture-test', 'fixture-smoke'})
        self.assertTrue(all(row['reason'] for row in result['excluded']))

    def test_test_selection_flags_are_not_inferred(self):
        for name in ['fixture-test', 'product-test', 'performance-test']:
            argv = verify.command_for(name, 'explicit')
            self.assertEqual(argv[2], 'test')
            self.assertFalse(any('only-testing' in value or 'skip-testing' in value for value in argv))
            self.assertIn('Release', argv)

    def test_changed_files_include_untracked_deleted_and_staged_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                # Detached maintenance must not outlive this temporary repository.
                return subprocess.check_output(['git', '-c', 'core.hooksPath=/dev/null',
                                                '-c', 'maintenance.auto=false', *args],
                                               cwd=root, stderr=subprocess.DEVNULL)
            git('init')
            (root / 'old.swift').write_text('before')
            (root / 'staged.swift').write_text('before')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '--no-gpg-sign', '-m', 'base')
            (root / 'old.swift').unlink()
            (root / 'staged.swift').write_text('after')
            git('add', 'staged.swift')
            (root / 'new.swift').write_text('new')
            _, paths = verify.changed_files(root, 'HEAD')
            self.assertEqual(paths, ['new.swift', 'old.swift', 'staged.swift'])

    def test_since_requires_success_and_compares_additions_deletions_and_content(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'result.json'
            original = {'status': 'passed', 'steps': [{'status': 'passed'}],
                        'source_start': {'gone': 'a', 'changed': 'b', 'same': 'c'},
                        'source_end': {'gone': 'a', 'changed': 'b', 'same': 'c'}}
            path.write_text(json.dumps(original))
            self.assertEqual(verify.changes_since(path, {'new': 'd', 'changed': 'z', 'same': 'c'}),
                             ['changed', 'gone', 'new'])
            for key, value in [('status', 'failed'), ('steps', [{'status': 'pending'}]), ('source_end', {})]:
                path.write_text(json.dumps({**original, key: value}))
                with self.assertRaises(ValueError):
                    verify.changes_since(path, {})


class ExecutionTests(unittest.TestCase):
    def test_native_preview_step_completes_without_ios_run_or_device(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(verify, 'ui'):
            root = Path(directory)
            with patch.object(verify, 'ROOT', root), patch.object(verify, 'working_hashes', return_value={}), \
                    patch.object(verify, 'execute', return_value=0):
                result = verify.run_plan(verify.plan([], 'inspection'), root / 'result', None)
            self.assertEqual(result['status'], 'passed')
            self.assertEqual(result['steps'][1]['runs'], [])

    def test_failure_keeps_results_and_never_runs_later_steps(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(verify, 'ui'):
            root = Path(directory)
            with patch.object(verify, 'ROOT', root), patch.object(verify, 'working_hashes', return_value={'a': 'hash'}), \
                    patch.object(verify, 'execute', side_effect=[2]) as execute:
                selected = verify.plan(['app/NibbleTests/Tests.swift'])
                result = verify.run_plan(selected, root / 'result', 'explicit')
            self.assertEqual(result['status'], 'failed')
            self.assertEqual([step['status'] for step in result['steps']], ['failed', 'pending'])
            self.assertEqual(execute.call_count, 1)
            self.assertTrue((root / 'result/result.json').is_file())
            with self.assertRaises(FileExistsError):
                verify.run_plan(selected, root / 'result', 'explicit')

    def test_missing_device_is_rejected_before_any_work(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(verify, 'execute') as execute:
            output = Path(directory) / 'new'
            with self.assertRaises(ValueError):
                verify.run_plan(verify.plan(['app/NibbleTests/Tests.swift']), output, None)
            execute.assert_not_called()
            self.assertFalse(output.exists())

    def test_source_change_after_static_check_prevents_ios_execution(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(verify, 'ui'):
            root = Path(directory)
            with patch.object(verify, 'ROOT', root), patch.object(verify, 'working_hashes',
                    side_effect=[{'a': 'before'}, {'a': 'before'}, {'a': 'after'}, {'a': 'after'}]), \
                    patch.object(verify, 'execute', return_value=0) as execute:
                result = verify.run_plan(verify.plan(['app/NibbleTests/Tests.swift']), root / 'result', 'explicit')
            self.assertEqual(result['status'], 'failed')
            self.assertEqual(execute.call_count, 1)
            self.assertEqual(result['steps'][1]['status'], 'pending')

    def test_timeout_signals_and_reaps_the_command_group(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(verify, 'ROOT', Path(directory)):
            log = Path(directory) / 'command.log'
            with self.assertRaises(subprocess.TimeoutExpired):
                verify.execute([sys.executable, '-c', 'import time; time.sleep(60)'], log, .1)
            self.assertTrue(log.is_file())

    def test_keyboard_interrupt_is_preserved_and_pending_steps_are_not_successful(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(verify, 'ui'):
            root = Path(directory)
            with patch.object(verify, 'ROOT', root), patch.object(verify, 'working_hashes', return_value={}), \
                    patch.object(verify, 'execute', side_effect=KeyboardInterrupt):
                result = verify.run_plan(verify.plan(['app/NibbleTests/Tests.swift']), root / 'result', 'explicit')
            self.assertEqual(result['status'], 'failed')
            self.assertEqual(result['error'], 'Interrupted')
            self.assertEqual(result['steps'][1]['status'], 'pending')


class PlannedEvidenceTests(unittest.TestCase):
    def test_wrong_device_configuration_target_or_action_cannot_satisfy_selected_tests(self):
        valid = {'device': {'udid': 'explicit'}, 'environment': {'configuration': 'Release'},
                 'project': {'scheme': 'VerificationApp'}, 'command': 'test'}
        alternatives = [dict(valid, device={'udid': 'another'}),
                        dict(valid, environment={'configuration': 'Debug'}),
                        dict(valid, project={'scheme': 'Another'}), dict(valid, command='build')]
        for manifest in alternatives:
            with self.subTest(manifest=manifest), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                output = root / 'result'
                def execute(argv, log, timeout, session=None):
                    if '--device' in argv:
                        run = root / 'artifacts/ios/run'
                        run.mkdir(parents=True)
                        (run / 'manifest.json').write_text(json.dumps({'session': session}))
                    return 0
                with patch.object(verify, 'ROOT', root), patch.object(verify, 'ui'), \
                        patch.object(verify, 'working_hashes', return_value={}), \
                        patch.object(verify, 'execute', side_effect=execute), \
                        patch('check_evidence.check_run', return_value=manifest):
                    report = verify.run_plan(verify.plan(['validation/VerificationAppTests/Tests.swift']), output, 'explicit')
                self.assertEqual(report['status'], 'failed')
                self.assertEqual(report['steps'][1]['status'], 'failed')
