#!/usr/bin/env python3
"""Verify the prompt library, native editing, named deletion and adaptive interface."""
import argparse
from contextlib import closing
import sqlite3
from types import SimpleNamespace
from uuid import uuid4

from ios import XCRUN, VerificationError, simulator_lock
from product_ui import WorkspaceRun as Run, identifiers, workspace_entry, workspace_text, workspace_input_point
from check_library_ui import workspace_database, publication_failure, assert_external_result, database_rows


class PromptRun(Run):
    def wait_for(self, identifier, name=None):
        return self.wait_ui(name or identifier, lambda d: identifier in identifiers(d))

    def label(self, text):
        data = self.ui('label-' + text)
        matches = [e for e in data['entries'] if e.get('role') == 'Button' and e.get('label') == text]
        if len(matches) != 1:
            raise VerificationError('Expected one observed native action: ' + text)
        self.command(['sim-use', 'tap', '--label', text, '--element-type', 'Button', '--device', self.args.device])

    def enter(self, identifier, text, *, replace=False):
        data = self.ui('input-before-' + identifier)
        x, y = workspace_input_point(data, identifier)
        self.command(['sim-use', 'tap', '-x', str(x), '-y', str(y), '--device', self.args.device])
        data = self.ui('input-focused-' + identifier)
        if replace:
            self.command(['sim-use', 'ios', 'key-combo', '--modifiers', '227', '--key', '4', '--device', self.args.device])
            self.command(['sim-use', 'ios', 'key', '42', '--device', self.args.device])
            data = self.ui('input-cleared-' + identifier)
        if text:
            x, y = workspace_input_point(data, identifier)
            # AX may trim surrounding whitespace; only the DB and clipboard prove exact bytes.
            self.paste_text(text, ['--target-x', str(x), '--target-y', str(y)],
                            lambda d: workspace_entry(d, identifier) is not None
                            and workspace_text(d, identifier).strip() == text.strip(), name='input-' + identifier)

    def home(self):
        data = self.ui('home-route')
        if 'prompt.back' in identifiers(data):
            self.tap('prompt.back')
        return self.wait_for('workspace.create', 'home')

    def dismiss_notice(self):
        data = self.ui('notice')
        if 'workspace.notice.text' in identifiers(data):
            self.label('通知を閉じる')
            self.wait_ui('notice-dismissed', lambda d: 'workspace.notice.text' not in identifiers(d))

    def paste_clipboard(self, identifier, expected):
        self.tap(identifier)
        data = self.ui('external-input-focused')
        x, y = workspace_input_point(data, identifier)
        self.command(['sim-use', 'tap', '-x', str(x), '-y', str(y), '--duration', '.8',
                      '--device', self.args.device], 'external-native-menu')
        menu = self.wait_ui('external-paste-menu', lambda d: any(e.get('label') in ('ペースト', 'Paste') for e in d['entries']))
        action = next(e for e in menu['entries'] if e.get('label') in ('ペースト', 'Paste'))
        self.command(['sim-use', 'tap', '@'+str(action['aliases']['at']), '--device', self.args.device])
        data = self.ui('external-paste-result')
        permission = next((e for e in data['entries'] if e.get('label') in ('ペーストを許可', 'Allow Paste')), None)
        if permission:
            self.command(['sim-use', 'tap', '@'+str(permission['aliases']['at']), '--device', self.args.device])
        return self.wait_ui('external-input-applied', lambda d: workspace_entry(d, identifier) is not None
                            and workspace_text(d, identifier).strip() == expected.strip())

    def create(self, title, body):
        self.home()
        self.dismiss_notice()
        self.tap('workspace.create')
        self.wait_for('workspace.editor.title')
        self.enter('workspace.editor.title', title)
        self.enter('workspace.editor.body', body)
        self.tap('workspace.editor.save')
        self.wait_ui('saved-home', lambda d: 'workspace.create' in identifiers(d) and 'workspace.editor.body' not in identifiers(d))
        self.dismiss_notice()
        return self.row(title)

    def row(self, title):
        data = self.wait_ui('named-prompt', lambda d: any(e.get('uniqueId', '').startswith('workspace.card.')
                            and title in e.get('label', '') for e in d['entries']))
        matches = [e['uniqueId'] for e in data['entries'] if e.get('uniqueId', '').startswith('workspace.card.') and title in e.get('label', '')]
        if len(matches) != 1:
            raise VerificationError('Ambiguous named prompt')
        return matches[0]

    def open(self, row):
        self.tap(row)
        return self.wait_for('prompt.body')

    def menu(self, action):
        self.tap('prompt.more')
        self.wait_for('prompt.' + action)
        self.tap('prompt.' + action)
        return self.ui('dialog-' + action)

    def delete(self, row):
        self.home()
        self.dismiss_notice()
        self.open(row)
        self.menu('delete')
        self.label('削除')
        self.wait_ui('deleted-home', lambda d: 'workspace.undo' in identifiers(d) and row not in identifiers(d))


def stored(database, row):
    with closing(sqlite3.connect(database.as_uri() + '?mode=ro', uri=True)) as connection:
        values = connection.execute('SELECT id,title,body,version,deleted_at FROM cards WHERE id=?', (row.removeprefix('workspace.card.'),)).fetchone()
    if values is None:
        raise VerificationError('Expected one persisted prompt')
    return values


def exact_copy(run, expected, identifier='prompt.copy'):
    run.tap(identifier)
    if identifier == 'prompt.copy':
        run.wait_ui('copy-completed', lambda d: workspace_entry(d, identifier) is not None
                    and workspace_entry(d, identifier).get('label') == 'コピーしました')
    else:
        run.wait_for('workspace.notice.text', 'row-copy-completed')
    actual = run.command([XCRUN, 'simctl', 'pbpaste', run.args.device], 'exact-copy')
    if actual.encode('utf-8') != expected.encode('utf-8'):
        raise VerificationError('Copied UTF-8 differs from the saved original')


def library(run):
    title = '保存と原文 ' + uuid4().hex[:8]
    body = '  日本語 か\u3099\r\n\t👩🏽‍💻 {{literal}} <code> 原文  '
    run.home()
    run.dismiss_notice()
    run.tap('workspace.create')
    run.wait_for('workspace.editor.title')
    data = run.ui('empty-required-fields')
    if 'disabled' not in workspace_entry(data, 'workspace.editor.save').get('states', []):
        raise VerificationError('Empty prompt must not be saveable')
    run.enter('workspace.editor.body', body)
    data = run.ui('title-required')
    if 'disabled' not in workspace_entry(data, 'workspace.editor.save').get('states', []):
        raise VerificationError('A title is required')
    run.enter('workspace.editor.title', title)
    database = workspace_database(run)
    run.wait_ui('checkpointed-dummy', lambda d: len(database_rows(database, title, 'work_drafts')) == 1)
    with publication_failure(run, database, title):
        run.tap('workspace.editor.save')
        run.wait_ui('save-failed', lambda d: any(e.get('label') == '保存できませんでした' for e in d['entries']))
        run.screenshot('save-failure')
        run.label('入力に戻る')
        data = run.wait_for('workspace.editor.body', 'failed-input-retained')
        if workspace_text(data, 'workspace.editor.body').strip() != body.strip():
            raise VerificationError('Failed save lost current input')
    run.tap('workspace.editor.save')
    run.wait_for('workspace.create', 'retry-saved')
    run.dismiss_notice()
    row = run.row(title)
    if stored(database, row)[2].encode('utf-8') != body.encode('utf-8'):
        raise VerificationError('Persistence changed the input bytes')
    run.enter('workspace.search', title)
    data = run.wait_ui('search-result', lambda d: row in identifiers(d))
    if 'Search' in identifiers(data):
        run.tap('Search')
        run.wait_ui('search-committed', lambda d: 'Search' not in identifiers(d))
    exact_copy(run, body, row.replace('workspace.card.', 'workspace.copy.'))
    run.screenshot('search-copy')
    run.dismiss_notice()
    run.tap('workspace.search.clear')
    run.wait_for(row, 'query-cleared')
    run.open(row)
    exact_copy(run, body)
    run.screenshot('detail-copy')
    # This native Paste is the external-use assertion, separate from pbpaste.
    fixture = 'dev.nibble.VerificationApp'
    run.command([XCRUN, 'simctl', 'launch', run.args.device, fixture], 'paste-target')
    run.wait_for('fixture.reset')
    run.tap('fixture.reset')
    neighbor = '変更しない隣の入力 ' + uuid4().hex[:8]
    run.paste_text(neighbor, ['--target-id', 'fixture.input.second'],
                   lambda d: workspace_entry(d, 'fixture.input.second') is not None
                   and workspace_text(d, 'fixture.input.second') == neighbor, name='neighbor')
    run.tap('fixture.apply.second')
    # Restore the actual source clipboard after fixture setup.
    run.command([XCRUN, 'simctl', 'launch', run.args.device, run.config['bundle_id']], 'source-for-copy')
    run.wait_for('prompt.copy')
    exact_copy(run, body)
    run.command([XCRUN, 'simctl', 'launch', run.args.device, fixture], 'external-paste')
    run.wait_for('fixture.input')
    run.paste_clipboard('fixture.input', body)
    run.tap('fixture.apply')
    data = run.wait_for('fixture.output.bytes', 'external-applied')
    observed = dict(data)
    observed['entries'] = list(data['entries'])
    for attempt in range(4):
        if 'fixture.output.second.bytes' in identifiers(data):
            break
        run.scroll_workspace(data, reading=True)
        data = run.ui('external-neighbor-result-' + str(attempt))
        current_ids = identifiers(data)
        observed['entries'] = [entry for entry in observed['entries'] if entry.get('uniqueId') not in current_ids] + data['entries']
    assert_external_result(observed, body, neighbor)
    run.command([XCRUN, 'simctl', 'launch', run.args.device, run.config['bundle_id']], 'return-source')
    run.wait_for('prompt.back')
    run.delete(row)
    run.manifest['assertions'] = {'required_title_and_body': True, 'failed_save_retry_retains_input': True,
                                  'exact_saved_and_copied_utf8': True, 'external_native_paste': True, 'neighbor_unchanged': True}


def notice(run):
    title = '削除と取消 ' + uuid4().hex[:8]
    body = ' \t取り消す原文\r\nか\u3099👩🏽‍💻  '
    row = run.create(title, body)
    database = workspace_database(run)
    original = stored(database, row)
    run.open(row)
    run.menu('delete')
    run.screenshot('delete-confirmation')
    run.label('キャンセル')
    run.wait_for('prompt.back')
    if stored(database, row) != original:
        raise VerificationError('Cancelling deletion changed the prompt')
    run.home()
    run.delete(row)
    run.screenshot('deleted-with-undo')
    run.tap('workspace.undo')
    run.wait_for(row, 'same-prompt-restored')
    restored = stored(database, row)
    if restored[:3] != original[:3] or restored[4] is not None:
        raise VerificationError('Undo did not restore the same identity and bytes')
    run.dismiss_notice()
    run.open(row)
    exact_copy(run, body)
    run.delete(row)
    run.manifest['assertions'] = {'named_delete_cancel_has_no_effect': True, 'delete_removes_row': True,
                                  'undo_restores_same_identity_and_original': True, 'restored_exact_copy': True}


def controls(run):
    title = '本文と名前 ' + uuid4().hex[:8]
    body = '原文 {{literal}}\r\nか\u3099 👩🏽‍💻'
    replacement = ' \t訂正した本文\r\n👩🏽‍💻 {{そのまま}}  '
    row = run.create(title, body)
    database = workspace_database(run)
    original = stored(database, row)
    run.open(row)
    run.tap('prompt.edit')
    data = run.wait_for('workspace.editor.title.readonly')
    if 'workspace.editor.title' in identifiers(data):
        raise VerificationError('Body editing exposes title input')
    run.enter('workspace.editor.body', replacement, replace=True)
    run.tap('workspace.editor.close')
    run.wait_ui('discard-confirmation', lambda d: any(e.get('label') == '変更を破棄しますか？' for e in d['entries']))
    run.screenshot('discard-confirmation')
    run.label('編集を続ける')
    data = run.wait_for('workspace.editor.body')
    if workspace_text(data, 'workspace.editor.body').strip() != replacement.strip():
        raise VerificationError('Continue editing lost input')
    run.tap('workspace.editor.close')
    run.label('変更を破棄')
    run.wait_for('prompt.body')
    if stored(database, row) != original:
        raise VerificationError('Discarding body changes altered the saved prompt')
    run.tap('prompt.edit')
    run.wait_for('workspace.editor.body')
    run.enter('workspace.editor.body', replacement, replace=True)
    run.tap('workspace.editor.save')
    run.wait_ui('body-saved-detail', lambda d: 'prompt.body' in identifiers(d) and 'workspace.editor.body' not in identifiers(d))
    edited = stored(database, row)
    if edited[1] != title or edited[2].encode('utf-8') != replacement.encode('utf-8'):
        raise VerificationError('Body save changed title or original input')
    run.menu('rename')
    data = run.ui('rename-input')
    fields = [e for e in data['entries'] if e.get('role') == 'TextField']
    if len(fields) != 1:
        raise VerificationError('Expected one native title field')
    field = fields[0]
    x, y = field['frame']['x'] + field['frame']['width']/2, field['frame']['y'] + field['frame']['height']/2
    run.command(['sim-use', 'tap', '-x', str(x), '-y', str(y), '--device', run.args.device])
    run.command(['sim-use', 'ios', 'key-combo', '--modifiers', '227', '--key', '4', '--device', run.args.device])
    run.command(['sim-use', 'ios', 'key', '42', '--device', run.args.device])
    renamed = '変更した用途 ' + uuid4().hex[:8]
    run.paste_text(renamed, ['--target-x', str(x), '--target-y', str(y)],
                   lambda d: any(e.get('role') == 'TextField' and e.get('value') == renamed for e in d['entries']), name='rename-value')
    run.label('保存')
    run.wait_ui('renamed-detail', lambda d: workspace_entry(d, 'prompt.title') is not None
                and renamed in workspace_text(d, 'prompt.title'))
    after = stored(database, row)
    if after[1] != renamed or after[2].encode('utf-8') != replacement.encode('utf-8'):
        raise VerificationError('Title-only save changed the body')
    exact_copy(run, replacement)
    run.screenshot('edited-renamed-detail')
    run.delete(row)
    run.manifest['assertions'] = {'body_title_is_readonly': True, 'discard_confirmation_and_continue': True,
                                  'discard_preserves_saved_original': True, 'body_only_save': True, 'title_only_save': True,
                                  'exact_unicode_copy_after_edits': True}


def interface(run):
    title = '表示と長文 ' + uuid4().hex[:8]
    body = ('# 記号も残す\nか\u3099 👩🏽‍💻 {{literal}}\n\n' * 60) + '本文の終端'
    row = run.create(title, body)
    run.open(row)
    standard_title_height = None
    measurements = {}
    for name, appearance, size in [('light', 'light', 'large'), ('dark', 'dark', 'large'),
                                   ('largest', 'light', 'accessibility-extra-extra-extra-large')]:
        run.command([XCRUN, 'simctl', 'ui', run.args.device, 'appearance', appearance], name+'-appearance')
        run.command([XCRUN, 'simctl', 'ui', run.args.device, 'content_size', size], name+'-size')
        data = run.wait_ui(name+'-detail', lambda d: 'prompt.body' in identifiers(d)
                           and (size == 'large' or workspace_entry(d, 'prompt.title')['frame']['height'] > standard_title_height))
        measurements[name] = workspace_entry(data, 'prompt.title')['frame']['height']
        if name == 'light':
            standard_title_height = measurements[name]
        for identifier in ('prompt.back', 'prompt.edit', 'prompt.more', 'prompt.copy'):
            frame = workspace_entry(data, identifier)['frame']
            screen = data['screen']
            if min(frame['width'], frame['height']) < 44 or frame['x'] < 0 or frame['y'] < 0 or frame['x']+frame['width'] > screen['width'] or frame['y']+frame['height'] > screen['height']:
                raise VerificationError('Persistent control is clipped: '+identifier)
        run.screenshot(name+'-detail')
        exact_copy(run, body)
    run.command([XCRUN, 'simctl', 'ui', run.args.device, 'content_size', 'large'], 'restore-text')
    run.command([XCRUN, 'simctl', 'ui', run.args.device, 'appearance', 'light'], 'restore-appearance')
    run.delete(row)
    run.manifest['title_heights'] = measurements
    run.manifest['assertions'] = {'light_and_dark_controls': True, 'largest_text_controls_remain_44pt_and_visible': True,
                                  'long_literal_utf8_copy_all_modes': True}


SCENARIOS = {'library': library, 'notice': notice, 'controls': controls, 'interface': interface}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--scenario', choices=SCENARIOS, required=True)
    args = parser.parse_args()
    run = PromptRun(SimpleNamespace(command=args.scenario+'-ui', device=args.device, configuration='Release', project_config='app/project.json'))
    error = None
    originals = {}
    try:
        run.setup()
        with simulator_lock(args.device):
            if args.scenario == 'interface':
                for option in ('appearance', 'content_size'):
                    originals[option] = run.command([XCRUN, 'simctl', 'ui', args.device, option], 'original-'+option).strip()
            run.launch()
            with run.recording():
                SCENARIOS[args.scenario](run)
    except (Exception, KeyboardInterrupt) as caught:
        error = caught
    finally:
        for option, value in originals.items():
            try:
                run.command([XCRUN, 'simctl', 'ui', args.device, option, value], 'finally-restore-'+option)
            except (Exception, KeyboardInterrupt) as caught:
                error = error or caught
        run.finish(error)
    if error is not None:
        raise SystemExit(repr(error))
    print(run.path)


if __name__ == '__main__':
    main()
