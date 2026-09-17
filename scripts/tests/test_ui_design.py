"""Regression cases for forgotten design updates, including new and deleted inputs."""

import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_ui_design as design


class DesignChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write('app/App/View.swift', 'struct View {}\n')
        self.write('app/App/Assets.xcassets/Contents.json', '{}\n')
        self.write('app/App/Info.plist', '<plist/>\n')
        self.write('docs/design/README.md', '# Design\n\nC01〜C03、S01、F01、R01、G01\n')
        self.write('docs/design/components.md', self.components())
        self.write('docs/design/screens.md', '## S01 Library\n\nC01〜C03\n')
        self.write('docs/design/foundations.md', '## F01 Layout\n')
        self.write('docs/design/audit.md', '### G01 Discovery\n')
        self.write('research/06-interface-design-evidence.md', '### R01 Primary source\n')
        self.write('docs/decisions/0002-mvp-app.md', '# Product\n')
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
        value = design.snapshot(self.root, 'Reviewed navigation, layout and the matching design contracts.',
                                ['docs/design/components.md', 'docs/design/screens.md'])
        self.write(design.RECORD, json.dumps(value))

    def errors(self):
        return design.check(self.root)['errors']

    def test_reviewed_tree_passes_without_git_or_network(self):
        self.assertEqual(self.errors(), [])
        self.assertEqual(design.check(self.root)['ids'], {'C': 3, 'S': 1, 'F': 1, 'R': 1, 'G': 1})

    def test_source_asset_and_configuration_edits_require_review(self):
        for name in ('app/App/View.swift', 'app/App/Assets.xcassets/Contents.json', 'app/App/Info.plist'):
            with self.subTest(name=name):
                path = self.root / name
                original = path.read_text()
                path.write_text(original + '\n')
                self.assertIn(f'Unreviewed changed input: {name}', self.errors())
                path.write_text(original)

    def test_new_target_is_detected_without_registering_its_directory(self):
        name = 'app/NewExtension/Screen.swift'
        self.write(name, 'struct NewScreen {}\n')
        self.assertIn(f'Unreviewed added input: {name}', self.errors())

    def test_deleting_and_renaming_source_fail(self):
        original = self.root / 'app/App/View.swift'
        original.rename(original.with_name('Renamed.swift'))
        errors = self.errors()
        self.assertIn('Unreviewed removed input: app/App/View.swift', errors)
        self.assertIn('Unreviewed added input: app/App/Renamed.swift', errors)

    def test_design_only_edit_requires_review(self):
        self.write('docs/design/screens.md', '## S01 Library\n\nC01〜C03\nChanged placement.\n')
        self.assertIn('Unreviewed changed input: docs/design/screens.md', self.errors())

    def test_new_design_document_is_detected(self):
        self.write('docs/design/new-pattern.md', '# Pattern\n')
        self.assertIn('Unreviewed added input: docs/design/new-pattern.md', self.errors())

    def test_updating_documents_does_not_accept_unreviewed_source(self):
        self.write('app/App/View.swift', 'struct DifferentView {}\n')
        self.write('docs/design/screens.md', '## S01 Library\nUpdated text.\n')
        self.assertEqual(sum('Unreviewed changed' in error for error in self.errors()), 2)
        self.record()
        self.assertEqual(self.errors(), [])

    def test_missing_or_incomplete_receipt_fails(self):
        path = self.root / design.RECORD
        value = json.loads(path.read_text())
        del value['files']['app/App/View.swift']
        path.write_text(json.dumps(value))
        self.assertIn('Unreviewed added input: app/App/View.swift', self.errors())
        path.unlink()
        self.assertIn(f'Missing review record: {design.RECORD}', self.errors())

    def test_receipt_cannot_shrink_scope(self):
        path = self.root / design.RECORD
        value = json.loads(path.read_text())
        value['files'] = {}
        path.write_text(json.dumps(value))
        self.assertTrue(any('app/App/View.swift' in error for error in self.errors()))

    def test_invalid_receipt_and_empty_reason_fail(self):
        for payload in ('{', '{"version":1,"version":1}', '{}'):
            with self.subTest(payload=payload):
                self.write(design.RECORD, payload)
                self.assertTrue(any('Invalid review record' in error for error in self.errors()))
        with self.assertRaisesRegex(ValueError, 'summary'):
            design.snapshot(self.root, '  ', ['docs/design/screens.md'])
        with self.assertRaisesRegex(ValueError, 'references'):
            design.snapshot(self.root, 'Reviewed.', ['missing.md'])

    def test_unknown_reference_and_missing_id_inside_range_fail(self):
        self.write('docs/design/screens.md', '## S01 Library\nC01〜C03、C99\n')
        self.write('docs/design/components.md', self.components().replace('| C02 Item | Purpose | Reason | F01・R01 |\n', ''))
        errors = self.errors()
        self.assertIn('Undefined design ID: C02', errors)
        self.assertIn('Undefined design ID: C99', errors)
        with self.assertRaisesRegex(ValueError, 'Undefined design ID'):
            self.record()

    def test_duplicate_heading_and_component_ids_fail(self):
        self.write('docs/design/screens.md', '## S01 Library\n## S01 Other\n')
        self.write('docs/design/components.md', self.components() + '| C01 Duplicate | Purpose | Reason | F01 |\n')
        errors = self.errors()
        self.assertTrue(any('Duplicate design ID: C01' in error for error in errors))
        self.assertTrue(any('Duplicate design ID: S01' in error for error in errors))

    def test_empty_component_reason_fails(self):
        self.write('docs/design/components.md', self.components().replace('| C02 Item | Purpose | Reason |', '| C02 Item | Purpose | |'))
        self.assertTrue(any('Incomplete design entry: C02' in error for error in self.errors()))

    def test_examples_and_comments_cannot_define_ids(self):
        self.write('docs/design/screens.md', '<!--\n## S01 Fake\n-->\n\n```markdown\n## S01 Fake\n```\n')
        self.assertIn('No S definitions: docs/design/screens.md', self.errors())
        self.write('docs/design/components.md', '```markdown\n' + self.components() + '```\n')
        self.assertIn('No C definitions: docs/design/components.md', self.errors())

    def test_invalid_reference_ranges_fail(self):
        for reference in ('C03〜C01', 'C01〜F01', 'C01〜C99999'):
            with self.subTest(reference=reference):
                self.write('docs/design/screens.md', f'## S01 Library\n{reference}\n')
                self.assertTrue(any('Invalid design ID range' in error for error in self.errors()))

    def test_removed_registry_fails_even_after_snapshot_attempt(self):
        (self.root / 'docs/design/components.md').unlink()
        self.assertIn('Missing design registry: docs/design/components.md', self.errors())
        with self.assertRaisesRegex(ValueError, 'Missing design registry'):
            self.record()

    def test_test_fixtures_and_local_xcode_state_do_not_invalidate_review(self):
        self.write('app/AppTests/ViewTests.swift', 'test data')
        self.write('app/App.xcodeproj/xcuserdata/user.xcuserdatad/state', 'local state')
        self.write('app/DerivedData/build.swift', 'generated')
        self.assertEqual(self.errors(), [])

    def test_source_symlink_cannot_hide_outside_changes(self):
        path = self.root / 'app/App/View.swift'
        path.unlink()
        path.symlink_to(self.root / 'docs/design/screens.md')
        with self.assertRaisesRegex(ValueError, 'regular file'):
            design.inventory(self.root)

    def test_check_is_read_only_and_cli_exits_nonzero(self):
        path = self.root / design.RECORD
        original = path.read_bytes()
        self.write('app/App/View.swift', 'changed')
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(design.main(['--root', str(self.root), 'check']))
        self.assertEqual(path.read_bytes(), original)

    def test_required_documentation_command_detects_stale_review(self):
        self.write('app/App/View.swift', 'changed')
        script = Path(__file__).resolve().parents[1] / 'check_docs.py'
        result = subprocess.run([sys.executable, str(script), '--root', str(self.root)],
                                text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('Unreviewed changed input: app/App/View.swift', result.stdout)


if __name__ == '__main__':
    unittest.main()
