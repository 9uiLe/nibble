from contextlib import closing
"""Driver assertions must distinguish saved, copied and externally pasted bytes."""
from pathlib import Path
import sqlite3
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parents[1]))
from check_library_ui import GROUP, SAVE_FAILURE_MESSAGE, SAVE_FAILURE_TITLE, assert_copy_receipt, assert_external_result, assert_save_failure_alert, declared_group_container, dismiss_save_failure, publication_failure, save_failure_alert, workspace_database
from ios import VerificationError


def external_data(body, neighbor):
    values = {'fixture.output': body, 'fixture.output.second': neighbor,
              'fixture.output.bytes': '[' + ','.join(map(str, body.encode('utf-8'))) + ']',
              'fixture.output.second.bytes': '[' + ','.join(map(str, neighbor.encode('utf-8'))) + ']'}
    return {'entries': [{'uniqueId': key, 'value': value} for key, value in values.items()]}


class ExternalEffectAssertions(unittest.TestCase):
    def test_copy_receipt_requires_completed_copy_and_the_next_action(self):
        good = {'entries': [{'uniqueId': 'workspace.use.receipt', 'label': 'コピーしました。入力先でペーストしてください。'}]}
        assert_copy_receipt(good)
        for data in ({'entries': [{'uniqueId': 'workspace.use.receipt', 'label': '保存しました'}]},
                     {'entries': good['entries'] + [{'uniqueId': 'workspace.use.copy'}]}):
            with self.assertRaises(VerificationError):
                assert_copy_receipt(data)

    def test_external_result_requires_exact_unicode_bytes_and_an_unchanged_neighbor(self):
        body, neighbor = '  か\u3099\r\n👩🏽‍💻\0  ', '隣の入力'
        data = external_data(body, neighbor)
        assert_external_result(data, body, neighbor)
        for index, replacement in ((0, '別の本文'), (1, '別の内容'), (2, '[1]'), (3, '[2]')):
            with self.subTest(index=index):
                broken = {'entries': [dict(entry) for entry in data['entries']]}
                broken['entries'][index]['value'] = replacement
                with self.assertRaises(VerificationError):
                    assert_external_result(broken, body, neighbor)

    def test_ax_trimmed_display_still_requires_the_original_outer_whitespace_bytes(self):
        body, neighbor = '  か\u3099\r\n👩🏽‍💻  ', ''
        data = external_data(body, neighbor)
        data['entries'][0]['value'] = body.strip()
        data['entries'][1]['value'] = None
        assert_external_result(data, body, neighbor)
        data['entries'][2]['value'] = '[' + ','.join(map(str, body.strip().encode('utf-8'))) + ']'
        with self.assertRaises(VerificationError):
            assert_external_result(data, body, neighbor)


class PublicationFailureCleanup(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.database = Path(self.temporary.name) / 'workspace.sqlite'
        with closing(sqlite3.connect(self.database)) as connection, connection:
            connection.executescript('CREATE TABLE cards(id TEXT,title TEXT,body TEXT); CREATE TABLE work_drafts(id TEXT,title TEXT,body TEXT);')
            connection.execute('INSERT INTO work_drafts VALUES(?,?,?)', ('draft', '固有の用件', '保持する原文'))
        self.run = SimpleNamespace(manifest={}, save=Mock())

    def test_observation_failure_always_removes_the_scoped_trigger(self):
        with self.assertRaisesRegex(RuntimeError, 'observation failed'):
            with publication_failure(self.run, self.database, '固有の用件'):
                with closing(sqlite3.connect(self.database)) as connection, connection:
                    connection.execute('INSERT INTO cards VALUES(?,?,?)', ('unrelated', '他の用件', '別の本文'))
                    with self.assertRaises(sqlite3.IntegrityError):
                        connection.execute('INSERT INTO cards VALUES(?,?,?)', ('blocked', '固有の用件', '保持する原文'))
                raise RuntimeError('observation failed')
        with closing(sqlite3.connect(self.database)) as connection, connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='trigger'").fetchone()[0], 0)
            connection.execute('INSERT INTO cards VALUES(?,?,?)', ('retry', '固有の用件', '保持する原文'))
        self.assertEqual(self.run.manifest['fault_injections'][0]['events'], ['scoped_sqlite_abort_installed', 'trigger_removed'])

    def test_unknown_or_already_published_targets_are_not_modified(self):
        with self.assertRaises(VerificationError):
            with publication_failure(self.run, self.database, '未確認の用件'):
                self.fail('An unknown target must not install a trigger')
        with closing(sqlite3.connect(self.database)) as connection, connection:
            connection.execute('INSERT INTO cards VALUES(?,?,?)', ('saved', '固有の用件', '本文'))
        with self.assertRaises(VerificationError):
            with publication_failure(self.run, self.database, '固有の用件'):
                self.fail('A published card is not this create-publication failure fixture')
        self.assertEqual(self.run.manifest, {})


class DeclaredGroupContainerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.group = Path(self.temporary.name).resolve() / 'DeclaredAppGroup'
        (self.group / 'Library').mkdir(parents=True)
        (self.group / 'Library/workspace.sqlite').write_bytes(b'fixture')

    def test_resolves_one_exact_tsv_record_without_a_direct_group_request(self):
        output = 'group.unrelated\t/another/container\n' + GROUP + '\t' + str(self.group) + '\n'
        self.assertEqual(declared_group_container(output, GROUP), self.group)
        run = SimpleNamespace(args=SimpleNamespace(device='owned'), config={'bundle_id': 'fixture'},
                              command=Mock(return_value=output), manifest={}, save=Mock())
        self.assertEqual(workspace_database(run), self.group / 'Library/workspace.sqlite')
        self.assertEqual(run.command.call_count, 1)
        self.assertEqual(run.command.call_args.args[0][-1], 'groups')
        self.assertEqual(run.manifest['workspace_group_container']['identifier'], GROUP)

    def test_rejects_missing_ambiguous_relative_and_malformed_group_records(self):
        exact = GROUP + '\t' + str(self.group)
        for output in (GROUP + '.other\t' + str(self.group), exact + '\n' + exact,
                       GROUP + '\trelative/path', GROUP + '\t' + str(self.group) + '\textra', GROUP):
            with self.subTest(output=output), self.assertRaises(VerificationError):
                declared_group_container(output, GROUP)

    def test_rejects_symlink_container_and_database_without_scanning(self):
        link = self.group.parent / 'AliasedAppGroup'
        link.symlink_to(self.group, target_is_directory=True)
        with self.assertRaises(VerificationError):
            declared_group_container(GROUP + '\t' + str(link), GROUP)
        database = self.group / 'Library/workspace.sqlite'
        database.unlink()
        other = self.group.parent / 'outside.sqlite'
        other.write_bytes(b'other fixture')
        database.symlink_to(other)
        run = SimpleNamespace(args=SimpleNamespace(device='owned'), config={'bundle_id': 'fixture'},
                              command=Mock(return_value=GROUP + '\t' + str(self.group)), manifest={}, save=Mock())
        with self.assertRaises(VerificationError):
            workspace_database(run)
        self.assertEqual(run.manifest, {})


class NativeSaveFailureAlertTests(unittest.TestCase):
    def alert(self):
        return {'screen': {'width': 375, 'height': 667}, 'entries': [
            {'role': 'StaticText', 'label': SAVE_FAILURE_TITLE,
             'frame': {'x': 57, 'y': 275, 'width': 260, 'height': 20}},
            {'role': 'StaticText', 'label': SAVE_FAILURE_MESSAGE,
             'frame': {'x': 57, 'y': 303, 'width': 260, 'height': 58}},
            {'label': '入力に戻る', 'role': 'Button', 'frame': {'x': 43, 'y': 381, 'width': 288, 'height': 48}},
        ]}

    def test_reads_actual_native_failure_message_then_returns_to_the_same_editor(self):
        alert = self.alert()
        self.assertTrue(save_failure_alert(alert))
        self.assertEqual(assert_save_failure_alert(alert), SAVE_FAILURE_MESSAGE)
        run = SimpleNamespace(args=SimpleNamespace(device='owned'), ui=Mock(return_value=alert),
                              command=Mock(), wait_ui=Mock())
        dismiss_save_failure(run)
        self.assertEqual(run.command.call_args.args[0], ['sim-use', 'tap', '--label', '入力に戻る',
                         '--element-type', 'Button', '--wait-timeout', '5', '--device', 'owned'])
        predicate = run.wait_ui.call_args.args[1]
        self.assertFalse(predicate(alert))
        self.assertTrue(predicate({'entries': [{'uniqueId': 'workspace.editor.body'}, {'uniqueId': 'workspace.editor.save'}]}))

    def test_success_label_inline_only_and_wrong_title_do_not_pass(self):
        for index, replacement in ((0, '文章を編集'), (1, '保存しました'),
                                   (1, 'コピーしました。入力は残っています。')):
            alert = self.alert()
            alert['entries'][index]['label'] = replacement
            with self.subTest(replacement=replacement), self.assertRaises(VerificationError):
                assert_save_failure_alert(alert)
        inline = {'screen': {'width': 375, 'height': 667}, 'entries': [
            {'uniqueId': 'workspace.error', 'role': 'StaticText', 'label': SAVE_FAILURE_MESSAGE,
             'frame': {'x': 32, 'y': 800, 'width': 311, 'height': 58}},
            {'uniqueId': 'workspace.editor.body'}, {'uniqueId': 'workspace.editor.save'}]}
        self.assertFalse(save_failure_alert(inline))

    def test_hidden_clipped_duplicate_or_disordered_modal_cannot_trigger_a_tap(self):
        for mutation in ('duplicate-title', 'duplicate-button', 'offscreen-message', 'clipped-button',
                         'hidden-button', 'button-before-message', 'no-common-column'):
            alert = self.alert()
            if mutation.startswith('duplicate'):
                alert['entries'].append(dict(alert['entries'][0 if mutation == 'duplicate-title' else 2]))
            elif mutation == 'offscreen-message':
                alert['entries'][1]['frame']['y'] = 700
            elif mutation == 'clipped-button':
                alert['entries'][2]['frame']['x'] = -1
            elif mutation == 'hidden-button':
                alert['entries'][2]['states'] = ['Hidden']
            elif mutation == 'button-before-message':
                alert['entries'][2]['frame']['y'] = 250
            else:
                alert['entries'][2]['frame'].update({'x': 330, 'width': 44})
            run = SimpleNamespace(args=SimpleNamespace(device='owned'), ui=Mock(return_value=alert), command=Mock())
            with self.subTest(mutation=mutation), self.assertRaises(VerificationError):
                dismiss_save_failure(run)
            run.command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
