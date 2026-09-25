"""Regression checks for stale evidence, misleading PRs and broken contributor references."""

import copy
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import check_docs
import check_evidence
import check_pr
import ios
from verification_evidence import media_hashes, revision_hashes, working_hashes

SHA = 'a' * 40
BODY = f'''## 目的・背景
証跡の取り違えを防ぐ。
## アウトカム
更新漏れを検出する。
## 変更内容
| コミットハッシュ | 変更の説明 |
| --- | --- |
| `{SHA}` | 検証ツールを整備 |
## スクリーンショット・画面録画
対象外：文書と検査基盤のみ。
## 検証結果
Python回帰テストとNix検査を実行。
性能：対象外（製品コードは変更なし）
未実施項目・残る制約：iOS実行検証は対象外。
## レビュー前の確認
- [x] 必要な検証を確認
'''


class PRTests(unittest.TestCase):
    def snapshot(self, body=BODY, files=None):
        return {'head': SHA, 'commits': [SHA], 'body': body, 'files': files or ['docs/guide.md']}

    def test_document_only_pr_and_current_ci(self):
        snapshot = self.snapshot()
        snapshot['checks'] = [{'id': 2, 'name': 'workflow-policy', 'app': {'slug': 'github-actions'},
                               'status': 'completed', 'conclusion': 'success'}]
        self.assertEqual(check_pr.check(snapshot, complete=True, expected_head=SHA, check_ci=True), [])

    def test_ci_uses_latest_run_for_each_check_name(self):
        older = {'id': 1, 'name': 'workflow-policy', 'app': {'slug': 'github-actions'},
                 'status': 'completed', 'conclusion': 'cancelled'}
        newer = {**older, 'id': 2, 'conclusion': 'success'}
        snapshot = self.snapshot()
        snapshot['checks'] = [newer, older]
        self.assertEqual(check_pr.check(snapshot, check_ci=True), [])
        snapshot['checks'] = [older, {**newer, 'conclusion': 'failure'}]
        self.assertTrue(check_pr.check(snapshot, check_ci=True))
        snapshot['checks'] = [newer, {**newer, 'id': 3, 'name': 'another-check', 'conclusion': 'failure'}]
        self.assertTrue(check_pr.check(snapshot, check_ci=True))

    def test_commit_addition_removal_duplicate_and_abbreviation_rejected(self):
        cases = [self.snapshot(BODY.replace(f'`{SHA}`', '`aaaaaaa`')),
                 self.snapshot(BODY.replace(f'| `{SHA}` | 検証ツールを整備 |', '')),
                 self.snapshot(BODY.replace(f'| `{SHA}` | 検証ツールを整備 |', f'| `{SHA}` | 一部 |\n| `{SHA}` | 重複 |'))]
        added = self.snapshot()
        added['commits'].append('b' * 40)
        cases.append(added)
        for snapshot in cases:
            with self.subTest(snapshot=snapshot):
                self.assertTrue(check_pr.check(snapshot))

    def test_blank_template_comments_and_code_examples_do_not_pass(self):
        for replacement in ['<!-- 説明を書く -->', '```markdown\nサンプルの説明\n```', '']:
            with self.subTest(replacement=replacement):
                self.assertTrue(check_pr.check(self.snapshot(BODY.replace('証跡の取り違えを防ぐ。', replacement))))

    def test_old_head_failed_ci_and_unfinished_checklist_rejected(self):
        self.assertTrue(check_pr.check(self.snapshot(), expected_head='b' * 40))
        self.assertTrue(check_pr.check(self.snapshot(), check_ci=True))
        self.assertTrue(check_pr.check(self.snapshot(BODY.replace('[x]', '[ ]')), complete=True))
        snapshot = self.snapshot()
        snapshot['checks'] = [{'id': 1, 'name': 'workflow-policy', 'app': {'slug': 'github-actions'},
                               'status': 'completed', 'conclusion': 'failure'}]
        self.assertTrue(check_pr.check(snapshot, check_ci=True))

    def test_ci_checks_structure_while_merge_review_requires_completed_checklist(self):
        snapshot = self.snapshot(BODY.replace('[x]', '[ ]'))
        with patch.object(check_pr, 'remote_snapshot', return_value=snapshot), redirect_stdout(io.StringIO()):
            self.assertEqual(check_pr.main(['remote', '--repo', 'example/repo', '--number', '1']), 0)
        with patch.object(check_pr, 'remote_snapshot', return_value=snapshot), redirect_stdout(io.StringIO()):
            self.assertEqual(check_pr.main(['remote', '--repo', 'example/repo', '--number', '1',
                                            '--complete']), 1)

    def test_ui_cannot_declare_out_of_scope_and_tests_can(self):
        for path in ['app/Shared/LibraryModel.swift', 'app/Nibble/View.swift', 'app/Nibble.xcodeproj/project.pbxproj',
                     'validation/VerificationApp/App.swift']:
            with self.subTest(path=path):
                self.assertTrue(check_pr.check(self.snapshot(files=[path])))
        self.assertEqual(check_pr.check(self.snapshot(files=['app/NibbleTests/Tests.swift'])), [])

    def test_ui_attachments_and_source_fields_required(self):
        evidence = '''- 対象コミット：`aaaaaaa`
- 端末：Simulator / iOS 26.5
- 操作：保存→検索
![変更前](https://github.com/user-attachments/assets/before)
![変更後](https://github.com/user-attachments/assets/after)
画面録画：[保存と検索](https://github.com/user-attachments/assets/video)'''
        snapshot = self.snapshot(BODY.replace('対象外：文書と検査基盤のみ。', evidence), ['app/Nibble/View.swift'])
        self.assertEqual(check_pr.check(snapshot), [])
        for old, new in [('https://github.com/user-attachments/assets/after', '/Users/me/after.png'),
                         ('iOS 26.5', 'iOS 27.0'), ('画面録画：', '録画なし：')]:
            altered = copy.deepcopy(snapshot)
            altered['body'] = altered['body'].replace(old, new)
            with self.subTest(old=old):
                self.assertTrue(check_pr.check(altered))

    def test_remote_snapshot_rejects_api_truncation_and_racing_push(self):
        pr = {'head': {'sha': SHA}, 'body': BODY, 'commits': 1, 'changed_files': 1}
        rows = [{'filename': 'docs/guide.md'}]
        with patch.object(check_pr, 'api', side_effect=[pr, [], rows]):
            with self.assertRaisesRegex(ValueError, 'Incomplete'):
                check_pr.remote_snapshot('example/repo', 1)
        changed = {**pr, 'head': {'sha': 'b' * 40}}
        with patch.object(check_pr, 'api', side_effect=[pr, [{'sha': SHA}], rows, changed]):
            with self.assertRaisesRegex(ValueError, 'changed'):
                check_pr.remote_snapshot('example/repo', 1)


class EvidenceFixture:
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.run = self.root / 'artifacts/run'
        self.run.mkdir(parents=True)
        (self.root / 'app').mkdir()
        (self.root / 'scripts').mkdir()
        (self.root / 'app/source.swift').write_text('let value = 1\n')
        (self.root / 'scripts/driver.py').write_text('print(1)\n')
        (self.root / 'README.md').write_text('# Docs\n')
        (self.root / '.gitignore').write_text('artifacts/\n')
        self.revision, self.hashes = self.source_identity()
        (self.run / 'image.png').write_bytes(b'fixture-image')
        (self.run / 'command.log').write_text('success')
        self.manifest = {'evidence_version': 1, 'status': 'passed', 'command': 'library-ui', 'commit': self.revision,
                         'dirty': False, 'files_sha256': self.hashes, 'files_sha256_end': self.hashes,
                         'project': {'project': 'app/Nibble.xcodeproj', 'scheme': 'Nibble'},
                         'device': {'udid': '12345678-1234-1234-1234-123456789abc',
                                    'runtime': {'version': '26.5', 'buildversion': '23F77'}},
                         'commands': [{'argv': ['xcodebuild', '-scheme', 'Nibble', '-destination',
                                                'platform=iOS Simulator,id=12345678-1234-1234-1234-123456789abc', 'build'],
                                       'stdout': 'command.log', 'exit_code': 0}],
                         'media_sha256': media_hashes(self.run)}
        self.save()

    def git(self, *args):
        return subprocess.check_output(['git', '-c', 'core.hooksPath=/dev/null', *args], cwd=self.root, stderr=subprocess.DEVNULL)

    def save(self):
        (self.run / 'manifest.json').write_text(json.dumps(self.manifest))

    def source_identity(self):
        return 'a' * 40, {'app/source.swift': 'b' * 64, 'scripts/driver.py': 'c' * 64}


class EvidenceSourceTests(EvidenceFixture, unittest.TestCase):
    def source_identity(self):
        self.git('init', '-b', 'main')
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--no-gpg-sign', '-m', 'fixture')
        return revision_hashes(self.root, 'HEAD')

    def test_reference_compares_files_and_allows_document_only_commit(self):
        self.assertEqual(check_evidence.check_run(self.run, self.hashes)['status'], 'passed')
        (self.root / 'README.md').write_text('# Better docs\n')
        self.git('add', 'README.md')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--no-gpg-sign', '-m', 'docs')
        _, hashes = revision_hashes(self.root, 'HEAD')
        check_evidence.check_run(self.run, hashes)
        for name in ['app/source.swift', 'scripts/driver.py', 'app/new.swift', 'runtime/rive/build.json', 'runtime/rive/drawable-acquisition.patch', 'flake.lock']:
            changed = {**hashes, name: 'b' * 64}
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'reference inputs'):
                check_evidence.check_run(self.run, changed)
        removed = {k: v for k, v in hashes.items() if k != 'app/source.swift'}
        with self.assertRaises(ValueError):
            check_evidence.check_run(self.run, removed)

    def test_run_changed_during_execution_fails_and_keeps_manifest(self):
        run = ios.Run.__new__(ios.Run)
        run.path, run.manifest = self.run, copy.deepcopy(self.manifest)
        run.args = SimpleNamespace(command='library-ui')
        (self.root / 'app/source.swift').write_text('let value = 2\n')
        with patch.object(ios, 'ROOT', self.root), redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ios.VerificationError, 'changed during'):
                run.finish()
        saved = json.loads((self.run / 'manifest.json').read_text())
        self.assertEqual(saved['status'], 'failed')
        self.assertTrue(saved['files_sha256_end'])
        self.assertTrue((self.run / 'REVIEW.md').exists())


class EvidenceTests(EvidenceFixture, unittest.TestCase):
    def test_tampered_media_failed_run_old_os_or_missing_logs_rejected(self):
        original = copy.deepcopy(self.manifest)
        for mutation in ['status', 'runtime', 'media', 'logs', 'missing_version']:
            self.manifest = copy.deepcopy(original)
            if mutation == 'status': self.manifest['status'] = 'failed'
            if mutation == 'runtime': self.manifest['device']['runtime']['version'] = '26.0'
            if mutation == 'media': self.manifest['media_sha256']['image.png'] = '0' * 64
            if mutation == 'logs': self.manifest['commands'][0]['stdout'] = 'missing.log'
            if mutation == 'missing_version': self.manifest.pop('evidence_version')
            self.save()
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                check_evidence.check_run(self.run, self.hashes)

    def test_failed_commands_cannot_be_reclassified_by_an_assertion(self):
        event = {'argv': ['sim-use', 'paste'], 'stdout': 'command.log'}
        self.manifest['commands'].append(event)
        event['exit_code'] = 1
        event['handled_error'] = {'reason': 'observed localized menu', 'assertion': 'exact_copy'}
        self.save()
        with self.assertRaises(ValueError): check_evidence.check_run(self.run, self.hashes)
        self.manifest['assertions'] = {'exact_copy': True}
        self.save()
        with self.assertRaises(ValueError): check_evidence.check_run(self.run, self.hashes)
        event['error'] = 'timeout'
        self.save()
        with self.assertRaises(ValueError): check_evidence.check_run(self.run, self.hashes)

    def test_standalone_media_or_build_for_another_target_cannot_certify_source(self):
        original = copy.deepcopy(self.manifest['commands'])
        for argv in [['simctl', 'screenshot'], ['xcodebuild', '-scheme', 'Another', '-destination',
                      'platform=iOS Simulator,id=12345678-1234-1234-1234-123456789abc', 'build']]:
            self.manifest['commands'] = copy.deepcopy(original)
            self.manifest['commands'][0]['argv'] = argv
            self.save()
            with self.subTest(argv=argv), self.assertRaisesRegex(ValueError, 'No successful target build'):
                check_evidence.check_run(self.run, self.hashes)

    def test_review_bound_to_media_and_access_declaration(self):
        review = check_evidence.init_review(self.run)
        with self.assertRaises(ValueError): check_evidence.check_review(self.run, self.manifest, review)
        review.update(reviewer='Fixture reviewer', scope='確認した一覧行')
        row = review['media'][0]
        row.update(observations='編集した本文の表示を確認', url='https://github.com/user-attachments/assets/image')
        row['access'] = {'method': 'browser', 'result': 'loaded', 'checked_at': '2026-09-16T01:00:00+09:00', 'scope': 'signed-in reviewer'}
        check_evidence.check_review(self.run, self.manifest, review)
        for key, value in [('url', 'http://localhost/image.png'), ('url', 'https://example.com/image?jwt=secret'),
                           ('sha256', '0' * 64), ('observations', '')]:
            altered = copy.deepcopy(review)
            altered['media'][0][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                check_evidence.check_review(self.run, self.manifest, altered)
        row['access']['method'] = 'HEAD'
        with self.assertRaises(ValueError): check_evidence.check_review(self.run, self.manifest, review)

    def test_sampled_video_requires_real_timestamp_and_not_full_playback_claim(self):
        (self.run / 'recording.mp4').write_bytes(b'fixture-video')
        (self.run / 'video-frames').mkdir()
        (self.run / 'video-frames/video.json').write_text('{"duration_seconds": 10}')
        self.manifest['media_sha256'] = media_hashes(self.run)
        self.save()
        review = check_evidence.init_review(self.run)
        review.update(reviewer='Fixture', scope='sample frames')
        for row in review['media']:
            row.update(observations='sample', url='https://example.com/' + row['file'])
            row['access'] = {'method': 'browser', 'result': 'loaded', 'checked_at': '2026-09-16T01:00:00+09:00', 'scope': 'signed-in'}
        video = next(row for row in review['media'] if row['file'].endswith('.mp4'))
        with self.assertRaises(ValueError): check_evidence.check_review(self.run, self.manifest, review)
        video['seconds'] = [1, 5, 9]
        check_evidence.check_review(self.run, self.manifest, review)
        video['seconds'] = [11]
        with self.assertRaises(ValueError): check_evidence.check_review(self.run, self.manifest, review)


class DocumentationTests(unittest.TestCase):
    def test_hosting_pages_check_internal_links_and_redirect_destinations(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'README.md').write_text('# Project\n')
            public = root / 'marketing/public'
            public.mkdir(parents=True)
            (root / 'marketing/firebase.json').write_text(json.dumps({
                'hosting': {'redirects': [{'source': '/contact', 'destination': '/contact.html'}]}
            }))
            (public / 'index.html').write_text('<a href="/contact">Contact</a><a href="https://example.com">External</a>')
            contact = public / 'contact.html'
            contact.write_text('<link href="/styles.css" rel="stylesheet">')
            (public / 'styles.css').write_text('')
            result = check_docs.check(root)
            self.assertEqual(result['errors'], [])
            self.assertEqual(result['site_links'], 2)
            (public / 'styles.css').unlink()
            self.assertTrue(any('missing/outside site link' in error for error in check_docs.check(root)['errors']))
            (public / 'styles.css').write_text('')
            contact.unlink()
            self.assertTrue(any('missing/outside redirect destination' in error for error in check_docs.check(root)['errors']))

    def test_context_dependent_prose_is_rejected_but_code_examples_are_not(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            document = root / 'README.md'
            document.write_text('現在の仕様を説明する。\n\n```md\n以前は別の仕様\n```\n')
            self.assertEqual(check_docs.check(root)['errors'], [])
            document.write_text('以前は別の仕様を使った。\n')
            self.assertTrue(any('context-dependent design prose' in error for error in check_docs.check(root)['errors']))

    def test_shell_examples_require_real_repository_commands_and_configs(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'scripts').mkdir()
            (root / 'scripts/run.py').write_text('')
            (root / 'app').mkdir()
            (root / 'app/project.json').write_text('{}')
            document = root / 'README.md'
            document.write_text('```sh\npython3 scripts/run.py --config app/project.json > artifacts/result.json\n```\n')
            self.assertEqual(check_docs.check(root)['errors'], [])
            (root / 'scripts/run.py').unlink()
            self.assertTrue(any('scripts/run.py' in error for error in check_docs.check(root)['errors']))
            (root / 'app/project.json').unlink()
            self.assertEqual(len(check_docs.check(root)['errors']), 2)

    def test_reference_links_encoded_paths_duplicates_and_fenced_examples(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'guide name.md').write_text('# 日本語とAPI\n# 日本語とAPI\n')
            source = '[guide][g] [again][g]\n\n[g]: <guide name.md#日本語とapi-1>\n\n```md\n[example](missing.md)\n```\n'
            (root / 'README.md').write_text(source)
            result = check_docs.check(root)
            self.assertEqual(result['errors'], [])
            self.assertEqual(result['local_links'], 2)
            (root / 'README.md').write_text(source.replace('api-1', 'api-2'))
            self.assertTrue(check_docs.check(root)['errors'])
            (root / 'README.md').write_text('[bad](absent.md)')
            self.assertTrue(check_docs.check(root)['errors'])

    def test_cached_source_keeps_each_paths_validation_rules(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / 'examples.md'
            source.write_text('```swift\nTask {}\n```\n')
            (root / 'docs').mkdir()
            (root / 'docs/library-policy.md').symlink_to(source)
            result = check_docs.check(root)
            self.assertEqual(result['swift_examples'], 1)
            self.assertTrue(any('library-policy.md' in error for error in result['errors']))

    def test_skill_metadata_and_swift_examples_are_checked(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            skill = root / '.agents/skills/my-skill'
            skill.mkdir(parents=True)
            (skill / 'SKILL.md').write_text('---\nname: my-skill\ndescription: Verify this repository\n---\n# Skill\n')
            docs = root / 'docs'
            docs.mkdir()
            (docs / 'library-policy.md').write_text('```swift\nlet value = 1\n```\n')
            self.assertEqual(check_docs.check(root)['errors'], [])
            (docs / 'library-policy.md').write_text('```swift\nTask {}\n```\n')
            self.assertTrue(check_docs.check(root)['errors'])
            (skill / 'SKILL.md').write_text('---\nname: another\n---\n')
            self.assertTrue(any('frontmatter' in e for e in check_docs.check(root)['errors']))


if __name__ == '__main__':
    unittest.main()
