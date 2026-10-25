from contextlib import closing
"""A generic success label or another target cannot certify a completed mutation."""
from pathlib import Path
import copy
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import Mock, call

sys.path.insert(0, str(Path(__file__).parents[1]))
from check_notice_ui import assert_completed_notice, delete_cancellation_frame, delete_named, stored_card, use_recovered_card
from ios import VerificationError


def native_delete_popover():
    # Reduced actual iOS 26.5 observation from notice-ui-6793c8. The dismiss
    # label belongs to the region, not a directly exposed Cancel button.
    return {'screen': {'x': 0, 'y': 0, 'width': 402, 'height': 874}, 'entries': [
        {'role': 'Button', 'label': 'nibble 検証へ戻る', 'uniqueId': 'breadcrumb',
         'frame': {'x': 12, 'y': 33, 'width': 69, 'height': 13}},
        {'role': 'StaticText', 'label': '「整理と回復」をごみ箱へ移しますか？ 後から戻せます。',
         'frame': {'x': 111, 'y': 94, 'width': 180, 'height': 64}},
        {'role': 'Group', 'label': '', 'region': {'kind': 'Group', 'label': 'ポップアップを閉じる'},
         'frame': {'x': 81, 'y': 72, 'width': 240, 'height': 181}},
        {'role': 'Button', 'label': 'ごみ箱へ移す',
         'frame': {'x': 97, 'y': 176, 'width': 208, 'height': 48}}]}


class DeleteCancellationTests(unittest.TestCase):
    def test_observed_native_popover_dismisses_outside_its_actions_without_following_the_breadcrumb(self):
        frame = delete_cancellation_frame(native_delete_popover(), '整理と回復')
        self.assertEqual((frame['x'] + frame['width'] / 2, frame['y'] + frame['height'] / 2), (201, 563.5))
        run = Mock()
        run.wait_ui.side_effect = [{}, native_delete_popover()]
        delete_named(run, 'card-id', '整理と回復', cancel=True)
        run.tap_frame.assert_called_once_with(frame)
        # This first action opens confirmation; cancellation must not invoke it again.
        run.tap_workspace_label.assert_called_once_with('ごみ箱へ移す')
        self.assertEqual(run.tap.call_args.args, ('workspace.manage.card-id',))

    def test_an_observed_cancel_button_is_preferred(self):
        data = native_delete_popover()
        cancel = {'x': 97, 'y': 240, 'width': 208, 'height': 48}
        data['entries'].append({'role': 'Button', 'label': 'キャンセル', 'frame': cancel})
        self.assertEqual(delete_cancellation_frame(data, '整理と回復'), cancel)

    def test_missing_semantics_ambiguous_popup_wrong_target_or_no_free_area_are_rejected(self):
        missing_marker = native_delete_popover()
        missing_marker['entries'][2]['region']['label'] = '別の領域'
        ambiguous = native_delete_popover()
        ambiguous['entries'].append(copy.deepcopy(ambiguous['entries'][2]))
        wrong_target = native_delete_popover()
        wrong_target['entries'][1]['label'] = '「別の文章」をごみ箱へ移しますか？ 後から戻せます。'
        missing_action = native_delete_popover()
        missing_action['entries'].pop()
        no_free_area = native_delete_popover()
        no_free_area['entries'][2]['frame'] = dict(no_free_area['screen'])
        unavailable_cancel = native_delete_popover()
        unavailable_cancel['entries'].append({'role': 'Button', 'label': 'キャンセル', 'states': ['disabled'],
                                               'frame': {'x': 97, 'y': 240, 'width': 208, 'height': 48}})
        for data in (missing_marker, ambiguous, wrong_target, missing_action, no_free_area, unavailable_cancel):
            with self.subTest(data=data), self.assertRaises(VerificationError):
                delete_cancellation_frame(data, '整理と回復')


class RecoveredUseTests(unittest.TestCase):
    def make_run(self, body, *, preview_body=None, copied_body=None, offer_copy_again=False):
        preview = {'entries': [{'uniqueId': 'workspace.use.preview', 'value': body if preview_body is None else preview_body},
                               {'uniqueId': 'workspace.use.copy'}]}
        receipt = {'entries': [{'uniqueId': 'workspace.use.receipt',
                                'label': 'コピーしました。入力先に戻ってペーストしてください。'}]}
        run = Mock()
        run.args.device = 'dedicated-device'
        run.wait_ui.side_effect = [preview, receipt]
        run.command.return_value = body if copied_body is None else copied_body
        run.ui.return_value = copy.deepcopy(receipt)
        if offer_copy_again:
            run.ui.return_value['entries'].append({'uniqueId': 'workspace.use.copy'})
        return run

    def test_restored_identity_is_opened_and_the_original_bytes_are_copied_once(self):
        body = ' 失わない原文 か\u3099\r\n👩🏽‍💻  '
        run = self.make_run(body)
        use_recovered_card(run, 'workspace.card.same-id', body)
        self.assertEqual(run.tap.call_args_list, [call('workspace.card.same-id'), call('workspace.use.copy')])
        run.reveal_workspace.assert_called_once_with('workspace.card.same-id')
        self.assertEqual(run.command.call_args.args[1], 'recovered-exact-completed-copy')
        run.ui.assert_called_once_with('recovered-copy-still-completed')

    def test_another_preview_changed_bytes_or_a_reoffered_copy_cannot_certify_recovery(self):
        body = ' か\u3099\r\n👩🏽‍💻 '
        for changes in ({'preview_body': '別の原文'}, {'copied_body': body.strip()}, {'offer_copy_again': True}):
            with self.subTest(changes=changes), self.assertRaises(VerificationError):
                use_recovered_card(self.make_run(body, **changes), 'workspace.card.same-id', body)


class CompletedEffectTests(unittest.TestCase):
    def test_named_delete_requires_target_and_completed_effect(self):
        good = {'entries': [{'uniqueId': 'workspace.notice.text', 'label': '「用件 A」をごみ箱へ移しました'}]}
        assert_completed_notice(good, '用件 A', 'ごみ箱へ移しました')
        for label in ('「用件 B」をごみ箱へ移しました', '「用件 A」を移しますか？', '保存しました'):
            with self.subTest(label=label), self.assertRaises(VerificationError):
                assert_completed_notice({'entries': [{'uniqueId': 'workspace.notice.text', 'label': label}]}, '用件 A', 'ごみ箱へ移しました')

    def test_identity_read_rejects_missing_and_duplicated_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / 'workspace.sqlite'
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute('CREATE TABLE cards(id TEXT,title TEXT,body TEXT,version INTEGER,deleted_at REAL)')
            with self.assertRaises(VerificationError):
                stored_card(database, 'target')
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute('INSERT INTO cards VALUES(?,?,?,?,?)', ('target', '用件', 'か\u3099', 1, None))
            self.assertEqual(stored_card(database, 'target')[2], 'か\u3099')
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute('INSERT INTO cards VALUES(?,?,?,?,?)', ('target', '用件', '別の本文', 2, None))
            with self.assertRaises(VerificationError):
                stored_card(database, 'target')


if __name__ == '__main__':
    unittest.main()
