"""Regression cases for forgotten design updates, including new and deleted inputs."""

import contextlib
from concurrent.futures import ThreadPoolExecutor
import io
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ui_design as design
from ui_design.cli import main

RECORD = "design/review.json"


class DesignChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write('client/screens/Panel.tsx', 'export const panel = {}\n')
        self.write('client/theme/tokens.json', '{}\n')
        self.write('client/config.json', '{}\n')
        self.write('design/README.md', '# Design\n\nC01〜C03、S01、F01、R01、G01\n')
        self.write('design/components.md', self.components())
        self.write('design/screens.md', '## S01 Library\n\nC01〜C03\n')
        self.write('design/foundations.md', '## F01 Layout\n')
        self.write('design/audit.md', '### G01 Discovery\n')
        self.write('evidence.md', '### R01 Primary source\n')
        self.write('product.md', '# Product\n')
        self.policy = {
            'version': 1,
            'record': RECORD,
            'inputs': [
                {'path': 'client', 'kind': 'tree', 'exclude_directories': ['*Tests', 'cache', 'build']},
                {'path': 'design', 'kind': 'tree', 'references': True},
                {'path': 'evidence.md', 'kind': 'file', 'references': True},
                {'path': 'product.md', 'kind': 'file', 'references': True},
            ],
            'registries': [
                {'prefix': 'C', 'path': 'design/components.md', 'format': 'table', 'columns': 4},
                {'prefix': 'S', 'path': 'design/screens.md', 'format': 'heading'},
                {'prefix': 'F', 'path': 'design/foundations.md', 'format': 'heading'},
                {'prefix': 'R', 'path': 'evidence.md', 'format': 'heading'},
                {'prefix': 'G', 'path': 'design/audit.md', 'format': 'heading'},
            ],
        }
        self.write('policy.json', json.dumps(self.policy))
        self.record()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def components(self):
        return '| ID | Purpose | Reason | Evaluation |\n| --- | --- | --- | --- |\n' + ''.join(
            f'| C{number:02} Item | Purpose | Reason | F01・R01 |\n' for number in range(1, 4))

    def record(self):
        value = design.snapshot(self.root, 'policy.json', 'Reviewed navigation, layout and the matching design contracts.',
                                ['design/components.md', 'design/screens.md'])
        self.write(RECORD, json.dumps(value))

    def errors(self):
        return design.check(self.root, 'policy.json')['errors']

    def test_reviewed_tree_passes_without_git_or_network(self):
        result = design.check(self.root, 'policy.json')
        self.assertEqual(result['errors'], [])
        self.assertEqual(result['ids'], {'C': 3, 'S': 1, 'F': 1, 'R': 1, 'G': 1})

    def test_configuration_edits_require_review(self):
        self.write('client/config.json', '{"enabled": true}\n')
        self.assertIn('Unreviewed changed input: client/config.json', self.errors())

    def test_new_source_and_design_inputs_are_detected(self):
        for name, contents in (('client/new-feature/Screen.tsx', 'export const newScreen = {}\n'),
                               ('design/new-pattern.md', '# Pattern\n')):
            with self.subTest(name=name):
                path = self.write(name, contents)
                self.assertIn(f'Unreviewed added input: {name}', self.errors())
                path.unlink()

    def test_deleting_and_renaming_source_fail(self):
        original = self.root / 'client/screens/Panel.tsx'
        original.rename(original.with_name('Renamed.tsx'))
        errors = self.errors()
        self.assertIn('Unreviewed removed input: client/screens/Panel.tsx', errors)
        self.assertIn('Unreviewed added input: client/screens/Renamed.tsx', errors)

    def test_updating_documents_does_not_accept_unreviewed_source(self):
        self.write('client/screens/Panel.tsx', 'export const differentPanel = {}\n')
        self.write('design/screens.md', '## S01 Library\nUpdated text.\n')
        errors = self.errors()
        self.assertIn('Unreviewed changed input: client/screens/Panel.tsx', errors)
        self.assertIn('Unreviewed changed input: design/screens.md', errors)
        self.record()
        self.assertEqual(self.errors(), [])

    def test_missing_or_incomplete_receipt_fails(self):
        path = self.root / RECORD
        value = json.loads(path.read_text())
        del value['files']['client/screens/Panel.tsx']
        path.write_text(json.dumps(value))
        self.assertIn('Unreviewed added input: client/screens/Panel.tsx', self.errors())
        path.unlink()
        self.assertIn(f'Missing review record: {RECORD}', self.errors())


    def test_invalid_receipt_and_empty_reason_fail(self):
        for payload in ('{', '{"version":1,"version":1}', '{}'):
            with self.subTest(payload=payload):
                self.write(RECORD, payload)
                self.assertTrue(any('Invalid review record' in error for error in self.errors()))
        with self.assertRaisesRegex(ValueError, 'summary'):
            design.snapshot(self.root, 'policy.json', '  ', ['design/screens.md'])
        with self.assertRaisesRegex(ValueError, 'references'):
            design.snapshot(self.root, 'policy.json', 'Reviewed.', ['missing.md'])

    def test_unknown_reference_and_missing_id_inside_range_fail(self):
        self.write('design/screens.md', '## S01 Library\nC01〜C03、C99\n')
        self.write('design/components.md', self.components().replace('| C02 Item | Purpose | Reason | F01・R01 |\n', ''))
        errors = self.errors()
        self.assertIn('Undefined design ID: C02', errors)
        self.assertIn('Undefined design ID: C99', errors)
        with self.assertRaisesRegex(ValueError, 'Undefined design ID'):
            self.record()

    def test_duplicate_heading_and_component_ids_fail(self):
        self.write('design/screens.md', '## S01 Library\n## S01 Other\n')
        self.write('design/components.md', self.components() + '| C01 Duplicate | Purpose | Reason | F01 |\n')
        errors = self.errors()
        self.assertTrue(any('Duplicate design ID: C01' in error for error in errors))
        self.assertTrue(any('Duplicate design ID: S01' in error for error in errors))

    def test_empty_component_reason_fails(self):
        self.write('design/components.md', self.components().replace('| C02 Item | Purpose | Reason |', '| C02 Item | Purpose | |'))
        self.assertTrue(any('Incomplete design entry: C02' in error for error in self.errors()))

    def test_examples_and_comments_cannot_define_ids(self):
        self.write('design/screens.md', '<!--\n## S01 Fake\n-->\n\n```markdown\n## S01 Fake\n```\n')
        self.assertIn('No S definitions: design/screens.md', self.errors())
        self.write('design/components.md', '```markdown\n' + self.components() + '```\n')
        self.assertIn('No C definitions: design/components.md', self.errors())

    def test_invalid_reference_ranges_fail(self):
        for reference in ('C03〜C01', 'C01〜F01', 'C01〜C99999'):
            with self.subTest(reference=reference):
                self.write('design/screens.md', f'## S01 Library\n{reference}\n')
                self.assertTrue(any('Invalid design ID range' in error for error in self.errors()))

    def test_removed_registry_fails_even_after_snapshot_attempt(self):
        (self.root / 'design/components.md').unlink()
        self.assertIn('Missing design registry: design/components.md', self.errors())
        with self.assertRaisesRegex(ValueError, 'Missing design registry'):
            self.record()

    def test_excluded_tests_and_local_state_do_not_invalidate_review(self):
        self.write('client/unitTests/Panel.test.ts', 'test data')
        self.write('client/cache/session/state', 'local state')
        self.write('client/build/generated.js', 'generated')
        self.assertEqual(self.errors(), [])

    def test_source_symlink_cannot_hide_outside_changes(self):
        path = self.root / 'client/screens/Panel.tsx'
        path.unlink()
        path.symlink_to(self.root / 'design/screens.md')
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            design.check(self.root, 'policy.json')

    def test_directory_read_failure_cannot_omit_inputs(self):
        original_scandir = os.scandir
        def scandir(path):
            if Path(path).resolve() == self.root.resolve() / 'client/screens':
                raise PermissionError('Cannot read source directory')
            return original_scandir(path)
        with patch('os.scandir', side_effect=scandir):
            with self.assertRaisesRegex(PermissionError, 'Cannot read source directory'):
                design.check(self.root, 'policy.json')
            with self.assertRaises(PermissionError):
                self.record()

    def test_check_is_read_only_and_cli_exits_nonzero(self):
        path = self.root / RECORD
        original = path.read_bytes()
        self.write('client/screens/Panel.tsx', 'changed')
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(main(['--root', str(self.root), '--config', 'policy.json', 'check']))
        self.assertEqual(path.read_bytes(), original)


    def test_narrowed_scope_cannot_reuse_previous_review(self):
        self.policy['inputs'][0]['exclude_files'] = ['config.json']
        self.write('policy.json', json.dumps(self.policy))
        errors = self.errors()
        self.assertIn('Unreviewed changed input: policy.json', errors)
        self.assertIn('Unreviewed removed input: client/config.json', errors)

    def test_missing_or_unsupported_policy_fails(self):
        path = self.root / 'policy.json'
        for version in (2, True, '1'):
            self.policy['version'] = version
            path.write_text(json.dumps(self.policy))
            with self.assertRaisesRegex(ValueError, 'version'):
                self.errors()
        path.unlink()
        with self.assertRaises(OSError):
            self.errors()

    def test_malformed_policy_cannot_disable_checks(self):
        original = json.dumps(self.policy)
        for mutate in (
            lambda p: p.update(inputs=[]),
            lambda p: p.update(registries=[]),
            lambda p: p.update(skip_missing=True),
            lambda p: p['registries'].append(p['registries'][0]),
            lambda p: p['registries'][0].update(format='unknown'),
            lambda p: p['inputs'][0].update(kind='optional'),
            lambda p: p['inputs'][0].update(kind=[]),
            lambda p: p['inputs'][0].update(references='true'),
            lambda p: p['inputs'][0].update(exclude_files=['../*']),
        ):
            policy = json.loads(original)
            mutate(policy)
            self.write('policy.json', json.dumps(policy))
            with self.assertRaises(ValueError):
                self.errors()

    def test_paths_cannot_escape_project(self):
        original = json.dumps(self.policy)
        for field in ('input', 'registry', 'record'):
            for path in (('../outside', '/absolute', 'client/../outside', './client', 'client//screens')
                         if field == 'input' else ('../outside',)):
                with self.subTest(field=field, path=path):
                    policy = json.loads(original)
                    if field == 'record':
                        policy['record'] = path
                    else:
                        policy['inputs' if field == 'input' else 'registries'][0]['path'] = path
                    self.write('policy.json', json.dumps(policy))
                    with self.assertRaises(ValueError):
                        self.errors()

    def test_registry_outside_declared_inputs_is_rejected(self):
        self.write('untracked-registry.md', '## S01 Screen\n')
        self.policy['registries'][1]['path'] = 'untracked-registry.md'
        self.write('policy.json', json.dumps(self.policy))
        self.assertIn('Missing design registry: untracked-registry.md', self.errors())

    def test_source_document_ids_are_not_product_design_references(self):
        self.write('client/README.md', '# Source notes\nC99 refers to an unrelated example.\n')
        self.record()
        self.assertEqual(self.errors(), [])
        with self.assertRaisesRegex(ValueError, 'references'):
            design.snapshot(self.root, 'policy.json', 'Reviewed.', ['client/README.md'])

    def test_noncanonical_id_is_rejected(self):
        self.write('design/screens.md', '## S001 Invalid padding\n')
        self.assertTrue(any('Noncanonical design ID: S001' in error for error in self.errors()))

    def test_overlapping_inputs_still_detect_asset_content_changes(self):
        self.policy['inputs'].append({'path': 'client/assets', 'kind': 'tree'})
        self.write('policy.json', json.dumps(self.policy))
        path = self.root / 'client/assets/asset.bin'
        path.parent.mkdir()
        path.write_bytes(b'asset contents')
        self.record()
        self.assertEqual(self.errors(), [])
        path.write_bytes(b'changed contents')
        self.assertEqual(self.errors(), ['Unreviewed changed input: client/assets/asset.bin'])

    def test_range_endpoints_must_use_canonical_padding(self):
        for reference in ('C001〜C003', 'C1〜C3'):
            with self.subTest(reference=reference):
                self.write('design/screens.md', f'## S01 Library\n{reference}\n')
                with self.assertRaisesRegex(ValueError, 'Noncanonical'):
                    self.record()

    def test_snapshot_rejects_symlink_record_destination(self):
        path = self.root / RECORD
        path.unlink()
        path.symlink_to(self.root / 'product.md')
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            self.record()

    def test_snapshot_owns_its_returned_metadata(self):
        references = ['design/screens.md']
        value = design.snapshot(self.root, 'policy.json', 'Reviewed.', references)
        references.append('unrelated.md')
        self.assertEqual(value['references'], ['design/screens.md'])

    def test_concurrent_products_and_subsequent_checks_are_independent(self):
        self.write('design/screens.md', '## S01 Library\nC99\n')
        with tempfile.TemporaryDirectory() as directory:
            other = Path(directory) / 'other-product'
            shutil.copytree(self.root, other)
            (other / 'design/screens.md').write_text('## S01 Library\nC98\n')
            with ThreadPoolExecutor(max_workers=2) as pool:
                first = pool.submit(design.check, self.root, 'policy.json')
                second = pool.submit(design.check, other, 'policy.json')
                first_errors = '\n'.join(first.result()['errors'])
                second_errors = '\n'.join(second.result()['errors'])
            self.assertIn('C99', first_errors)
            self.assertNotIn('C98', first_errors)
            self.assertIn('C98', second_errors)
            self.assertNotIn('C99', second_errors)
        self.write('design/screens.md', '## S01 Library\nC01〜C03\n')
        self.record()
        self.assertEqual(self.errors(), [])


class ExtractionTests(unittest.TestCase):
    def test_copied_toolkit_runs_against_a_different_product(self):
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            toolkit = root / 'standalone-toolkit'
            shutil.copytree(Path(__file__).resolve().parents[1], toolkit,
                            ignore=shutil.ignore_patterns('__pycache__'))
            product = root / 'other-product'
            (product / 'web').mkdir(parents=True)
            (product / 'experience').mkdir()
            (product / 'web' / 'button.html').write_text('<button>Submit</button>')
            (product / 'experience' / 'parts.md').write_text(
                '| ID | Purpose | Evaluation |\n| --- | --- | --- |\n'
                '| UI01 Submit | Send form | TASK01 |\n| UI02 Cancel | Discard form | TASK01 |\n')
            (product / 'experience' / 'journeys.md').write_text('## TASK01 Submit form\nUI01〜UI02\n')
            policy = {
                'version': 1, 'record': 'experience/checked.json',
                'inputs': [{'path': 'web', 'kind': 'tree'}, {'path': 'experience', 'kind': 'tree', 'references': True}],
                'registries': [
                    {'prefix': 'UI', 'path': 'experience/parts.md', 'format': 'table', 'columns': 3},
                    {'prefix': 'TASK', 'path': 'experience/journeys.md', 'format': 'heading'},
                ],
            }
            (product / 'experience' / 'policy.json').write_text(json.dumps(policy))
            command = [sys.executable, '-m', 'ui_design', '--root', str(product),
                       '--config', 'experience/policy.json']
            def run(*args):
                return subprocess.run(command + list(args), cwd=toolkit, text=True,
                                      capture_output=True, check=False)
            candidate = run('snapshot', '--summary', 'Reviewed form actions and journeys.',
                            '--reference', 'experience/parts.md')
            self.assertEqual(candidate.returncode, 0, candidate.stderr)
            (product / 'experience' / 'checked.json').write_text(candidate.stdout)
            passed = run('check')
            self.assertEqual(passed.returncode, 0, passed.stderr)
            self.assertEqual(json.loads(passed.stdout)['ids'], {'UI': 2, 'TASK': 1})
            (product / 'web' / 'button.html').write_text('<button>Send</button>')
            failed = run('check')
            self.assertEqual(failed.returncode, 1, failed.stderr)
            self.assertIn('Unreviewed changed input: web/button.html', failed.stdout)


if __name__ == '__main__':
    unittest.main()
