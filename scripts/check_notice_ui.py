#!/usr/bin/env python3
"""Verify named deletion, cancellation, undo and trash recovery through actual controls."""
from contextlib import closing
import argparse
import sqlite3
from types import SimpleNamespace
from uuid import uuid4

from ios import XCRUN, VerificationError, simulator_lock
from product_ui import WorkspaceRun as Run, identifiers, workspace_entry, workspace_text
from check_library_ui import workspace_database, assert_copy_receipt


def assert_completed_notice(data, *fragments):
    text = workspace_text(data, 'workspace.notice.text')
    if not all(fragment in text for fragment in fragments):
        raise VerificationError('Notice does not identify the actual completed effect: ' + text)
    return text


def stored_card(database, card_id):
    with closing(sqlite3.connect(database.as_uri() + '?mode=ro', uri=True, timeout=2)) as connection, connection:
        rows = connection.execute('SELECT id,title,body,version,deleted_at FROM cards WHERE id=?', (card_id,)).fetchall()
    if len(rows) != 1:
        raise VerificationError('A repeated command duplicated or lost the named card')
    return rows[0]


def delete_cancellation_frame(data, title):
    """Use an observed Cancel button or the native popover's dismiss region."""
    def contains(outer, inner):
        return (all(key in outer and key in inner for key in ('x', 'y', 'width', 'height'))
                and outer['width'] > 0 and outer['height'] > 0 and inner['width'] > 0 and inner['height'] > 0
                and outer['x'] <= inner['x'] and outer['y'] <= inner['y']
                and inner['x'] + inner['width'] <= outer['x'] + outer['width']
                and inner['y'] + inner['height'] <= outer['y'] + outer['height'])

    def unique_frame(matches, description):
        if len(matches) != 1 or not contains(data.get('screen', {}), matches[0].get('frame', {})):
            raise VerificationError('No unique visible ' + description)
        if any(state.lower() in ('hidden', 'disabled') for state in matches[0].get('states', [])):
            raise VerificationError('Unavailable ' + description)
        return matches[0]['frame']

    entries = data.get('entries', [])
    named = unique_frame([entry for entry in entries if entry.get('role') == 'StaticText'
                          and entry.get('label') == f'「{title}」をごみ箱へ移しますか？ 後から戻せます。'],
                         'named delete confirmation')
    destructive = unique_frame([entry for entry in entries if entry.get('role') == 'Button'
                                and entry.get('label') == 'ごみ箱へ移す'], 'delete action')
    cancel = [entry for entry in entries if entry.get('role') == 'Button'
              and entry.get('label') in ('キャンセル', 'Cancel')]
    if cancel:
        return unique_frame(cancel, 'Cancel action')
    popup = unique_frame([entry for entry in entries if entry.get('role') == 'Group'
                          and entry.get('region') == {'kind': 'Group', 'label': 'ポップアップを閉じる'}
                          and contains(entry.get('frame', {}), named)
                          and contains(entry.get('frame', {}), destructive)], 'native dismiss popover')
    screen = data['screen']
    x, y, width, height = (screen[key] for key in ('x', 'y', 'width', 'height'))
    right, bottom = popup['x'] + popup['width'], popup['y'] + popup['height']
    bands = [dict(x=x, y=bottom, width=width, height=y + height - bottom),
             dict(x=x, y=y, width=width, height=popup['y'] - y),
             dict(x=x, y=y, width=popup['x'] - x, height=height),
             dict(x=right, y=y, width=x + width - right, height=height)]
    for band in sorted(bands, key=lambda frame: frame['width'] * frame['height'], reverse=True):
        if band['width'] < 44 or band['height'] < 44:
            continue
        point = dict(x=band['x'] + band['width'] / 2, y=band['y'] + band['height'] / 2,
                     width=1, height=1)
        if not any(contains(entry.get('frame', {}), point) for entry in entries):
            return band
    raise VerificationError('No observed popup-free area for native dismissal')


def delete_named(run, card, title, *, cancel=False):
    run.reveal_workspace('workspace.manage.' + card)
    run.tap('workspace.manage.' + card)
    run.wait_ui('management-menu', lambda d: any(e.get('label') == 'ごみ箱へ移す' for e in d['entries']))
    run.tap_workspace_label('ごみ箱へ移す')
    confirmation = run.wait_ui('named-delete-confirmation', lambda d: any(title in e.get('label', '') and '後から戻せます' in e.get('label', '') for e in d['entries']))
    if cancel:
        run.tap_frame(delete_cancellation_frame(confirmation, title))
    else:
        run.tap_workspace_label('ごみ箱へ移す')


def use_recovered_card(run, identifier, body):
    run.reveal_workspace(identifier)
    run.tap(identifier)
    preview = run.wait_ui('recovered-full-preview', lambda data:
                          {'workspace.use.preview', 'workspace.use.copy'} <= identifiers(data))
    # AX can trim whitespace; the actual copy bytes below remain authoritative.
    if ''.join(workspace_text(preview, 'workspace.use.preview').split()) != ''.join(body.split()):
        raise VerificationError('Recovered confirmation identifies another source')
    run.screenshot('recovered-full-original-preview')
    run.tap('workspace.use.copy')
    receipt = run.wait_ui('recovered-copy-completed', lambda data: 'workspace.use.receipt' in identifiers(data))
    assert_copy_receipt(receipt)
    copied = run.command([XCRUN, 'simctl', 'pbpaste', run.args.device], 'recovered-exact-completed-copy')
    if copied.encode('utf-8') != body.encode('utf-8'):
        raise VerificationError('Recovered copy differs from the original UTF-8')
    run.screenshot('recovered-copy-receipt')
    assert_copy_receipt(run.ui('recovered-copy-still-completed'))


def run_notice_flow(run, title, body):
    identifier = run.create_workspace_card(title, body)
    card = identifier.removeprefix('workspace.card.')
    database = workspace_database(run)
    initial = stored_card(database, card)
    delete_named(run, card, title, cancel=True)
    run.wait_ui('cancelled-delete-target-kept', lambda d: identifier in identifiers(d))
    if stored_card(database, card) != initial:
        raise VerificationError('Cancel changed the saved card')
    delete_named(run, card, title)
    removed = run.wait_ui('named-deletion-completed', lambda d: identifier not in identifiers(d) and 'workspace.undo' in identifiers(d))
    assert_completed_notice(removed, title, 'ごみ箱へ移しました')
    deleted = stored_card(database, card)
    if deleted[4] is None or deleted[3] != initial[3] + 1:
        raise VerificationError('Delete notice did not match exactly one versioned move to trash')
    run.screenshot('named-delete-with-undo')
    run.tap('workspace.undo')
    undone = run.wait_ui('same-card-restored', lambda d: identifier in identifiers(d) and 'workspace.undo' not in identifiers(d))
    assert_completed_notice(undone, 'ごみ箱から戻しました')
    restored = stored_card(database, card)
    if restored[4] is not None or restored[3] != deleted[3] + 1 or restored[2].encode('utf-8') != body.encode('utf-8'):
        raise VerificationError('Undo did not restore the same exact card once')
    run.screenshot('undo-completed-same-card')
    delete_named(run, card, title)
    run.wait_ui('second-delete-completed', lambda d: identifier not in identifiers(d) and 'workspace.undo' in identifiers(d))
    deleted_again = stored_card(database, card)
    run.open_settings()
    run.reveal_workspace('workspace.trash')
    run.tap('workspace.trash')
    restore = 'workspace.restore.' + card
    run.reveal_workspace(restore)
    run.wait_ui('named-trash-target', lambda d: restore in identifiers(d) and 'workspace.trashed.' + card in identifiers(d))
    run.screenshot('trash-target-identifiable')
    run.tap(restore)
    recovered = run.wait_ui('trash-restore-completed', lambda d: restore not in identifiers(d) and 'workspace.notice.text' in identifiers(d))
    assert_completed_notice(recovered, 'ごみ箱から戻しました')
    final = stored_card(database, card)
    if final[4] is not None or final[3] != deleted_again[3] + 1 or final[0:3] != initial[0:3]:
        raise VerificationError('Trash restore duplicated, changed or lost the named source')
    run.screenshot('trash-restore-receipt')
    run.workspace()
    run.paste_editor('workspace.search', title, replace=True)
    if run.matching_workspace_id('workspace.card.', title) != identifier:
        raise VerificationError('Recovered search target changed identity')
    use_recovered_card(run, identifier, body)
    run.manifest['assertions'] = {'card_id': card, 'cancel_left_card_unchanged': True,
        'restored_card_reused_exact_utf8': True, 'completed_copy_not_offered_again': True,
        'delete_receipt_names_target': True, 'undo_same_card_exact_once': True,
        'repeated_named_delete_restore_did_not_duplicate': True, 'trash_restore_same_original_bytes': True,
        'completed_restore_control_removed': True,
        'version_sequence': [initial[3], deleted[3], restored[3], deleted_again[3], final[3]]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--appearance', choices=('light', 'dark'), default='light')
    args = parser.parse_args()
    run = Run(SimpleNamespace(command='notice-ui', device=args.device, configuration='Release', project_config='app/project.json'))
    error, original = None, None
    try:
        run.setup()
        with simulator_lock(args.device):
            run.boot()
            original = run.command([XCRUN, 'simctl', 'ui', args.device, 'appearance']).strip()
            run.command([XCRUN, 'simctl', 'ui', args.device, 'appearance', args.appearance])
            run.launch()
            with run.recording():
                run_notice_flow(run, '整理と回復 ' + uuid4().hex[:8], '失わない原文 か\u3099\r\n👩🏽‍💻  ')
    except (Exception, KeyboardInterrupt) as caught:
        error = caught
    finally:
        if original in ('light', 'dark'):
            try:
                run.command([XCRUN, 'simctl', 'ui', args.device, 'appearance', original])
            except (Exception, KeyboardInterrupt) as caught:
                error = error or caught
        run.finish(error)
    if error is not None:
        raise SystemExit(repr(error))


if __name__ == '__main__':
    main()
