#!/usr/bin/env python3
"""Exercise create, recover, failed-save retry, find, confirm, copy and external native Paste."""
import argparse
from contextlib import closing, contextmanager
import hashlib
from pathlib import Path
import sqlite3
from types import SimpleNamespace
from uuid import uuid4

from ios import XCRUN, VerificationError, expect_text, simulator_lock
from product_ui import WorkspaceRun as Run, identifiers, workspace_entry, workspace_text

GROUP = 'group.nibble.9uiLe.com'
FIXTURE = 'dev.nibble.VerificationApp'
SAVE_FAILURE_TITLE = '操作を完了できませんでした'
SAVE_FAILURE_MESSAGE = '保存できませんでした。入力は残っています。空き容量を確認して、もう一度お試しください。'


def assert_copy_receipt(data):
    text = workspace_text(data, 'workspace.use.receipt')
    if 'コピーしました' not in text or 'ペースト' not in text or 'workspace.use.copy' in identifiers(data):
        raise VerificationError('Copy receipt must state the completed copy and next Paste step without offering repetition')


def save_failure_alert(data):
    # UIKit's native alert bridge exposes these semantic labels and frames,
    # not the identifier assigned to its SwiftUI message Text.
    screen = data.get('screen', {})
    observed = []
    for role, label in (('StaticText', SAVE_FAILURE_TITLE), ('StaticText', SAVE_FAILURE_MESSAGE),
                        ('Button', '入力に戻る')):
        matches = [entry for entry in data.get('entries', [])
                   if entry.get('role') == role and entry.get('label') == label]
        if len(matches) != 1:
            return False
        frame = matches[0].get('frame', {})
        if (frame.get('width', 0) <= 0 or frame.get('height', 0) <= 0
                or frame.get('x', -1) < 0 or frame.get('y', -1) < 0
                or frame['x'] + frame['width'] > screen.get('width', 0)
                or frame['y'] + frame['height'] > screen.get('height', 0)
                or any(state.lower() in ('hidden', 'disabled') for state in matches[0].get('states', []))):
            return False
        observed.append(frame)
    title, message, button = observed
    return (title['y'] + title['height'] <= message['y']
            and message['y'] + message['height'] <= button['y']
            and max(frame['x'] for frame in observed)
            < min(frame['x'] + frame['width'] for frame in observed))


def assert_save_failure_alert(data):
    if not save_failure_alert(data):
        raise VerificationError('Expected the visible native save-failure alert, retained-input message and unique return action')
    return SAVE_FAILURE_MESSAGE


def dismiss_save_failure(run):
    data = run.ui('save-failure-alert-before-return')
    assert_save_failure_alert(data)
    # The native modal is foreground content; an underlying keyboard's frame
    # must not disqualify this actually observed alert button.
    run.command(['sim-use', 'tap', '--label', '入力に戻る', '--element-type', 'Button',
                 '--wait-timeout', '5', '--device', run.args.device], 'save-failure-return-to-input')
    return run.wait_ui('failure-alert-dismissed-input-retained', lambda d:
                       not save_failure_alert(d)
                       and {'workspace.editor.body', 'workspace.editor.save'} <= identifiers(d))


def assert_external_result(data, expected, neighbor):
    # The native fixture exposes both readable text and its actual UTF-8.
    # AX can trim a label's surrounding whitespace; only the byte receipt is
    # authoritative for those characters. Never normalize that receipt.
    for identifier, text in (('fixture.output', expected), ('fixture.output.second', neighbor)):
        entry = workspace_entry(data, identifier)
        if entry is None or (entry.get('value') or '').strip() != text.strip():
            raise VerificationError('External readable text differs: ' + identifier)
    expect_text(data, 'fixture.output.bytes', '[' + ','.join(str(byte) for byte in expected.encode('utf-8')) + ']')
    expect_text(data, 'fixture.output.second.bytes', '[' + ','.join(str(byte) for byte in neighbor.encode('utf-8')) + ']')


def declared_group_container(output, identifier):
    matches = []
    for line in output.splitlines():
        fields = line.split('\t')
        if fields[0].strip() != identifier:
            continue
        if len(fields) != 2 or not fields[1].strip():
            raise VerificationError('Malformed container record for the exact declared App Group')
        matches.append(Path(fields[1].strip()))
    if len(matches) != 1:
        raise VerificationError('Expected exactly one container for the declared App Group')
    group = matches[0]
    if not group.is_absolute() or not group.is_dir() or group.is_symlink() or group.resolve() != group:
        raise VerificationError('The declared App Group container is not an absolute existing non-symlink directory')
    return group


def workspace_database(run):
    # On this host `groups` returns exact identifier<TAB>path records, while a
    # direct group-ID request fails despite the CLI help advertising that form.
    # Resolve only the declared identifier; never scan other Simulator data.
    output = run.command([XCRUN, 'simctl', 'get_app_container', run.args.device,
                          run.config['bundle_id'], 'groups'], 'declared-app-groups')
    group = declared_group_container(output, GROUP)
    database = group / 'Library/workspace.sqlite'
    if not database.is_file() or database.is_symlink() or database.resolve() != database:
        raise VerificationError('The declared App Group has no existing non-symlink workspace database')
    run.manifest['workspace_group_container'] = {'identifier': GROUP, 'container': str(group),
                                               'resolution': 'exact groups TSV record'}
    run.save()
    return database


def database_rows(database, title, table):
    if table not in ('cards', 'work_drafts'):
        raise ValueError('Unsupported workspace table')
    with closing(sqlite3.connect(database.as_uri() + '?mode=ro', uri=True, timeout=2)) as connection, connection:
        return connection.execute(f'SELECT id,title,body FROM {table} WHERE title=?', (title,)).fetchall()


@contextmanager
def publication_failure(run, database, title):
    """Inject one scoped SQLite failure; always remove it, including failed UI observations."""
    if database_rows(database, title, 'cards'):
        raise VerificationError('Fault target must be this run\'s unpublished unique title')
    if len(database_rows(database, title, 'work_drafts')) != 1:
        raise VerificationError('Fault target must have exactly one durable dummy draft')
    trigger = 'nibble_gui_save_failure_' + uuid4().hex
    record = {'database': str(database), 'title': title, 'trigger': trigger, 'events': []}
    run.manifest.setdefault('fault_injections', []).append(record)
    escaped = title.replace("'", "''")
    try:
        with closing(sqlite3.connect(database.as_uri() + '?mode=rw', uri=True, timeout=2)) as connection, connection:
            connection.execute(f"CREATE TRIGGER {trigger} BEFORE INSERT ON cards WHEN NEW.title='{escaped}' "
                               "BEGIN SELECT RAISE(ABORT,'dedicated dummy publication failure'); END")
        record['events'].append('scoped_sqlite_abort_installed')
        run.save()
        yield record
    finally:
        with closing(sqlite3.connect(database.as_uri() + '?mode=rw', uri=True, timeout=2)) as connection, connection:
            connection.execute(f'DROP TRIGGER IF EXISTS {trigger}')
            if connection.execute('SELECT COUNT(*) FROM sqlite_master WHERE name=?', (trigger,)).fetchone()[0]:
                raise VerificationError('Save-failure trigger was not removed')
        record['events'].append('trigger_removed')
        run.save()


def prepare_external_fixture(run, neighbor):
    run.command([XCRUN, 'simctl', 'launch', run.args.device, FIXTURE], 'external-fixture-launch')
    run.wait_ui('external-fixture-ready', lambda d: d.get('appPackage') == FIXTURE and 'fixture.reset' in identifiers(d))
    run.tap('fixture.reset')
    run.paste_text(neighbor, ['--target-id', 'fixture.input.second'], lambda d: workspace_entry(d, 'fixture.input.second') is not None
                   and workspace_text(d, 'fixture.input.second') == neighbor, name='external-neighbor-setup')
    run.tap('fixture.apply.second')
    data = run.wait_ui('external-neighbor-applied', lambda d: workspace_entry(d, 'fixture.output.second') is not None)
    expect_text(data, 'fixture.output.second', neighbor)
    run.command([XCRUN, 'simctl', 'launch', run.args.device, run.config['bundle_id']], 'return-to-source')
    run.wait_ui('source-returned', lambda d: d.get('appPackage') == run.config['bundle_id'])


def run_library_flow(run):
    body = '  日本語 か\u3099\r\n\t👩🏽‍💻 <code> 原文  '
    title = '原文再利用 ' + uuid4().hex[:8]
    neighbor = '変更しない隣の入力 ' + uuid4().hex[:8]
    (run.path / 'expected-source.txt').write_bytes(body.encode('utf-8'))
    run.workspace()
    run.tap('workspace.create')
    run.wait_ui('editor-open', lambda d: 'workspace.editor.body' in identifiers(d))
    run.paste_editor('workspace.editor.title', title)
    run.paste_editor('workspace.editor.body', body)
    run.tap('workspace.editor.close')
    run.wait_ui('editor-closed', lambda d: 'workspace.create' in identifiers(d))
    draft = run.matching_workspace_id('workspace.draft.', title, name='durable-work-visible')
    run.tap(draft)
    run.wait_ui('work-resumed', lambda d: 'workspace.editor.body' in identifiers(d))
    database = workspace_database(run)
    with publication_failure(run, database, title) as fault:
        run.tap('workspace.editor.save')
        failed = run.wait_ui('save-failed-input-kept', save_failure_alert)
        assert_save_failure_alert(failed)
        rows = database_rows(database, title, 'work_drafts')
        if len(rows) != 1 or rows[0][2].encode('utf-8') != body.encode('utf-8') or database_rows(database, title, 'cards'):
            raise VerificationError('Failed save lost exact work or published a card')
        fault['events'].append('failed_ui_and_exact_durable_input_observed')
        run.screenshot('save-failed-input-retained')
    dismiss_save_failure(run)
    run.tap('workspace.editor.save')
    run.wait_ui('retry-saved', lambda d: 'workspace.create' in identifiers(d) and 'workspace.editor.body' not in identifiers(d))
    cards = database_rows(database, title, 'cards')
    if len(cards) != 1 or cards[0][2].encode('utf-8') != body.encode('utf-8') or database_rows(database, title, 'work_drafts'):
        raise VerificationError('Retry must publish exactly one exact card and retire its work session')
    run.paste_editor('workspace.search', title, replace=True)
    card = run.matching_workspace_id('workspace.card.', title, name='saved-card-found-by-search')
    if card.removeprefix('workspace.card.').lower() != cards[0][0].lower():
        raise VerificationError('Search selected another stored card')
    prepare_external_fixture(run, neighbor)
    run.reveal_workspace(card)
    run.tap(card)
    preview = run.wait_ui('full-preview', lambda d: {'workspace.use.preview', 'workspace.use.copy'} <= identifiers(d))
    # AX may normalize surrounding whitespace; exact final bytes are proved by
    # the clipboard and actual external host below, never this display alone.
    if ''.join(workspace_text(preview, 'workspace.use.preview').split()) != ''.join(body.split()):
        raise VerificationError('Confirmation preview does not identify the complete source text')
    run.screenshot('full-original-preview')
    run.tap('workspace.use.copy')
    receipt = run.wait_ui('copy-completed-once', lambda d: 'workspace.use.receipt' in identifiers(d))
    assert_copy_receipt(receipt)
    copied = run.command([XCRUN, 'simctl', 'pbpaste', run.args.device], 'exact-completed-copy')
    if copied.encode('utf-8') != body.encode('utf-8'):
        raise VerificationError('Completed copy differs from the original UTF-8 bytes')
    run.screenshot('copy-receipt')
    run.command([XCRUN, 'simctl', 'launch', run.args.device, FIXTURE], 'external-input-return')
    run.wait_ui('external-input-current', lambda d: d.get('appPackage') == FIXTURE and 'fixture.input' in identifiers(d))
    run.paste_existing_clipboard('fixture.input', body)
    run.tap('fixture.apply')
    run.tap('fixture.apply.second')
    observed = run.wait_ui('external-native-result', lambda d: workspace_entry(d, 'fixture.output') is not None)
    assert_external_result(observed, body, neighbor)
    run.screenshot('external-target-exact-neighbor-unchanged')
    run.manifest['assertions'] = {'card_id': cards[0][0], 'draft_id': draft, 'created_recovered_found_confirmed': True,
        'save_failure_retained_exact_input_and_retry_once': True, 'copy_receipt_matches_completed_effect': True,
        'external_native_paste_exact_utf8': True, 'external_neighbor_unchanged': True,
        'source_sha256': hashlib.sha256(body.encode('utf-8')).hexdigest(),
        'japanese_ime_operation': 'not established by native paste'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    run = Run(SimpleNamespace(command='library-ui', device=args.device, configuration='Release', project_config='app/project.json'))
    error = None
    try:
        run.setup()
        with simulator_lock(args.device):
            run.launch()
            with run.recording():
                run_library_flow(run)
    except (Exception, KeyboardInterrupt) as caught:
        error = caught
    finally:
        run.finish(error)
    if error is not None:
        raise SystemExit(repr(error))


if __name__ == '__main__':
    main()
