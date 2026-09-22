"""Verification selection and fail-fast orchestration contracts, without Apple tools."""
import importlib.util
import io
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

    def test_runtime_definition_changes_require_the_complete_regression(self):
        for path in ['runtime/rive/Package.swift', 'runtime/rive/build.json',
                     'runtime/rive/dependency.lua', 'runtime/rive/drawable-acquisition.patch']:
            with self.subTest(path=path):
                self.assertEqual(self.selected([path]), set(verify.REGRESSION_STEPS))

    def test_docs_do_not_start_simulators(self):
        self.assertEqual(self.selected(['docs/ios-verification.md', 'AGENTS.md', '.agents/skills/example/SKILL.md']), {'static'})

    def test_static_tooling_changes_do_not_start_ios(self):
        self.assertEqual(self.selected(['scripts/check_docs.py', 'tools/ui-design/cli.py', '.github/workflows/check.yml']), {'static'})

    def test_controls_driver_selects_its_matching_evidence_stage(self):
        self.assertEqual(self.selected(['scripts/check_controls_ui.py']), {'static', 'controls-ui'})
        self.assertEqual(verify.command_for('controls-ui', 'device-id'),
                         [sys.executable, 'scripts/check_controls_ui.py', '--device', 'device-id'])
        self.assertIn('controls-ui', self.selected(['app/Shared/Editing/EditorToolbar.swift']))

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

    def test_preconditions_describe_only_the_selected_environment(self):
        static = ' '.join(verify.plan(['README.md'])['preconditions'])
        self.assertIn('Nix', static)
        self.assertNotIn('Simulator', static)
        inspection = ' '.join(verify.plan([], 'inspection')['preconditions'])
        self.assertIn('sips', inspection)
        self.assertNotIn('Simulator', inspection)
        fixture = ' '.join(verify.plan([], 'fixture')['preconditions'])
        self.assertIn('iOS 26.5', fixture)
        self.assertIn('--device', fixture)
        self.assertNotIn('初期化', fixture)
        self.assertIn('初期化', ' '.join(verify.plan([], 'product')['preconditions']))

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
            original = {'status': 'passed', 'steps': [{'id': 'static', 'status': 'passed'}],
                        'source_start': {'gone': 'a', 'changed': 'b', 'same': 'c'},
                        'source_end': {'gone': 'a', 'changed': 'b', 'same': 'c'}}
            path.write_text(json.dumps(original))
            self.assertEqual(verify.changes_since(path, {'new': 'd', 'changed': 'z', 'same': 'c'}),
                             ['changed', 'gone', 'new'])
            for key, value in [('status', 'failed'), ('steps', [{'id': 'static', 'status': 'pending'}]), ('source_end', {})]:
                path.write_text(json.dumps({**original, key: value}))
                with self.assertRaises(ValueError):
                    verify.changes_since(path, {})
            for malformed in [[], {}, {**original, 'steps': [None]}]:
                path.write_text(json.dumps(malformed))
                with self.subTest(malformed=malformed), self.assertRaises(ValueError):
                    verify.changes_since(path, {})


class ExecutionTests(unittest.TestCase):
    def test_command_result_and_diagnostics_stay_in_separate_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'command.log'
            # Use repr for a standalone Python program; no shell is involved.
            code = 'import sys; print(' + repr('{"result": true}') + '); print("diagnostic", file=sys.stderr)'
            self.assertEqual(verify.execute([sys.executable, '-c', code], log, 5), 0)
            self.assertEqual(json.loads(log.read_text()), {'result': True})
            self.assertEqual(log.with_suffix('.stderr.log').read_text(), 'diagnostic\n')

    def test_status_preserves_failed_and_pending_work_without_reusing_success(self):
        report = {'status': 'failed', 'source_start': {'a': 'old'},
                  'source_end': {'a': 'new'}, 'error': 'Sources changed during verification',
                  'steps': [{'id': 'static', 'status': 'passed', 'seconds': 2, 'log': 'static.log'},
                            {'id': 'product-test', 'status': 'pending'}],
                  'manual_review': ['録画を確認する']}
        result = verify.summarize_report(report, Path('artifacts/run/result.json'), {'a': 'new', 'b': 'added'})
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['steps'], report['steps'])
        self.assertEqual(result['error'], report['error'])
        self.assertEqual(result['manual_review'], report['manual_review'])
        self.assertFalse(result['source_stable'])
        self.assertFalse(result['source_matches_current'])
        self.assertEqual(result['changed_since_start'], ['a', 'b'])
        self.assertNotIn('source_start', result)

    def test_running_status_does_not_claim_completion_or_process_liveness(self):
        report = {'status': 'running', 'source_start': {'a': 'hash'},
                  'steps': [{'id': 'static', 'status': 'running'}]}
        result = verify.summarize_report(report, Path('result.json'), {'a': 'hash'})
        self.assertEqual(result['status'], 'running')
        self.assertIsNone(result['source_stable'])
        self.assertIsNone(result['source_matches_current'])
        for malformed in [[], {}, {**report, 'status': []}, {**report, 'steps': []},
                          {**report, 'steps': [None]}, {**report, 'steps': [{'id': 'static', 'status': []}]},
                          {**report, 'source_end': None}]:
            with self.subTest(malformed=malformed), self.assertRaises(ValueError):
                verify.summarize_report(malformed, Path('result.json'), {})

    def test_report_publication_keeps_old_snapshot_when_replace_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'result.json'
            verify.save_report(path, {'status': 'running'})
            with patch.object(Path, 'replace', side_effect=OSError('interrupted')), self.assertRaises(OSError):
                verify.save_report(path, {'status': 'passed'})
            self.assertEqual(json.loads(path.read_text()), {'status': 'running'})
            verify.save_report(path, {'status': 'failed'})
            self.assertEqual(json.loads(path.read_text()), {'status': 'failed'})
            self.assertFalse(path.with_suffix('.json.tmp').exists())

    def test_plan_output_saves_complete_reasons_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(verify, 'ui'), \
                patch.object(verify, 'working_hashes', return_value={'a': 'hash'}), \
                patch.object(verify, 'changed_files', return_value=('commit', ['README.md'])), \
                patch('builtins.print') as emit, patch.object(verify, 'execute') as execute:
            output = Path(directory) / 'plan'
            self.assertEqual(verify.main(['plan', '--output', str(output)]), 0)
            saved = json.loads((output / 'plan.json').read_text())
            self.assertEqual(saved['planning_source'], {'a': 'hash'})
            self.assertTrue(saved['excluded'])
            self.assertTrue(saved['steps'][0]['reasons'])
            summary = json.loads(emit.call_args.args[0])
            self.assertEqual(summary['steps'], ['static'])
            self.assertEqual(summary['preconditions'], saved['preconditions'])
            self.assertNotIn('planning_source', summary)
            self.assertEqual(verify.main(['plan', '--output', str(output)]), 1)
            execute.assert_not_called()

    def test_default_plan_saves_details_in_distinct_directories_without_execution(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(verify, 'ui'), \
                patch.object(verify, 'ROOT', Path(directory)), \
                patch.object(verify, 'working_hashes', return_value={'README.md': 'hash'}), \
                patch.object(verify, 'changed_files', return_value=('commit', ['README.md'])), \
                patch('builtins.print') as emit, patch.object(verify, 'run_plan') as run:
            paths = []
            for _ in range(2):
                self.assertEqual(verify.main(['plan']), 0)
                summary = json.loads(emit.call_args.args[0])
                path = Path(summary['plan'])
                self.assertEqual(path.parent.parent, Path(directory) / 'artifacts/verify')
                saved = json.loads(path.read_text())
                self.assertEqual(saved['planning_source'], {'README.md': 'hash'})
                self.assertEqual(summary['changed_file_count'], 1)
                self.assertNotIn('excluded', summary)
                paths.append(path)
            self.assertNotEqual(*paths)
            run.assert_not_called()

    def test_since_plan_uses_the_snapshot_without_resolving_a_git_base(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(verify, 'ui'), \
                patch.object(verify, 'working_hashes', return_value={'README.md': 'new'}), \
                patch.object(verify, 'changed_files') as changed, patch('builtins.print') as emit:
            result = Path(directory) / 'result.json'
            result.write_text(json.dumps({'status': 'passed', 'steps': [{'id': 'static', 'status': 'passed'}],
                                         'source_start': {'README.md': 'old'}, 'source_end': {'README.md': 'old'}}))
            output = Path(directory) / 'plan'
            self.assertEqual(verify.main(['plan', '--since', str(result), '--output', str(output)]), 0)
            saved = json.loads((output / 'plan.json').read_text())
            self.assertEqual(saved['changed_files'], ['README.md'])
            self.assertIsNone(saved['base'])
            self.assertEqual(json.loads(emit.call_args.args[0])['since'], str(result))
            changed.assert_not_called()

    def test_arguments_are_validated_for_the_selected_operation_before_reading_sources(self):
        invalid = [['status'], ['status', '--result', 'result.json', '--scope', 'product'],
                   ['status', '--result', 'result.json', '--output', 'out'],
                   ['plan', '--device', 'device'], ['run', '--result', 'result.json'],
                   ['plan', '--base', 'HEAD', '--since', 'result.json'],
                   ['run', '--base', 'HEAD', '--since', 'result.json']]
        with patch.object(verify, 'working_hashes') as read, patch('sys.stderr', new=io.StringIO()):
            for argv in invalid:
                with self.subTest(argv=argv), self.assertRaises(SystemExit) as failure:
                    verify.main(argv)
                self.assertEqual(failure.exception.code, 2)
            read.assert_not_called()

    def test_status_is_read_only_and_does_not_resolve_base_or_run_stages(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(verify, 'ui'), \
                patch.object(verify, 'working_hashes', return_value={'a': 'hash'}), \
                patch.object(verify, 'changed_files') as changed, \
                patch.object(verify, 'run_plan') as run, patch('builtins.print'):
            path = Path(directory) / 'result.json'
            data = {'status': 'passed', 'source_start': {'a': 'hash'}, 'source_end': {'a': 'hash'},
                    'steps': [{'id': 'static', 'status': 'passed'}]}
            path.write_text(json.dumps(data))
            original = path.read_bytes()
            self.assertEqual(verify.main(['status', '--result', str(path)]), 0)
            self.assertEqual(path.read_bytes(), original)
            changed.assert_not_called()
            run.assert_not_called()

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
