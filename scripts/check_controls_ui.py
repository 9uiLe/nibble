#!/usr/bin/env python3
"""Verify settings, search entry and editor controls on an explicit iOS Simulator."""
import argparse
import plistlib
from pathlib import Path
import time
from types import SimpleNamespace

from ios import simulator_lock, VerificationError


from product_ui import ProductRun as Run, identifiers


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    run = Run(SimpleNamespace(command='controls-ui', device=args.device,
                              configuration='Release', project_config='app/project.json'))
    error = None

    def controls(data, expected, absent=()):
        present = identifiers(data)
        if not set(expected) <= present or set(absent) & present:
            raise VerificationError('Unexpected controls: ' + str(present))
        entries = {entry.get('uniqueId'): entry for entry in data['entries'] if entry.get('uniqueId')}
        for identifier, entry in entries.items():
            if identifier in expected:
                frame = entry['frame']
                # Native navigation items expose their 36pt visual bounds in AX;
                # UIKit owns the surrounding hit area. Exercise each actual action.
                native = identifier in ('editor.close', 'editor.save', 'editor.help.close', 'library.trash.close')
                minimum = 36 if native else 44
                if frame['width'] < minimum or frame['height'] < minimum:
                    raise VerificationError('Control is smaller than its touch target: ' + str(entry))


    try:
        run.setup()
        with simulator_lock(args.device):
            run.launch()
            root = run.wait_ui('root', lambda d: 'navigation.settings' in identifiers(d))
            with run.recording():
                # Observe beyond presentation completion to catch delayed auto-focus.
                time.sleep(.5)
                data = run.ui('search-idle')
                controls(data, ('navigation.settings', 'library.add'),
                         ('search.done', 'Search'))
                idle_search = next(entry['frame'] for entry in data['entries'] if entry.get('uniqueId') == 'search.field')
                run.screenshot('search-without-keyboard')
                run.tap('search.field')
                focused = run.wait_ui('search-focused', lambda d: 'search.done' in identifiers(d))
                focused_search = next(entry['frame'] for entry in focused['entries'] if entry.get('uniqueId') == 'search.field')
                if any(abs(idle_search[key] - focused_search[key]) > 1 for key in ('x', 'width')):
                    raise VerificationError('Search input width changes when keyboard dismissal appears')
                run.tap('search.done')
                run.wait_ui('search-unfocused', lambda d: 'search.done' not in identifiers(d))
                run.open_settings()
                data = run.wait_ui('settings', lambda d: 'settings.version' in identifiers(d))
                if 'library.add' in identifiers(data):
                    raise VerificationError('Settings must not show the creation button')
                info = plistlib.loads((run.derived / 'Build/Products/Release-iphonesimulator/Nibble.app/Info.plist').read_bytes())
                if info['UISupportedInterfaceOrientations'] != ['UIInterfaceOrientationPortrait']:
                    raise VerificationError('The application must support portrait only')
                expected = f"バージョン {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})"
                version = next(e for e in data['entries'] if e.get('uniqueId') == 'settings.version')
                if version['label'] != expected:
                    raise VerificationError('Settings version differs from the installed bundle')
                run.screenshot('settings-version-disclosures')
                run.tap('library.trash')
                data = run.wait_ui('deleted', lambda d: 'library.trash.close' in identifiers(d))
                controls(data, ('library.trash.close',))
                run.screenshot('deleted-close')
                run.tap('library.trash.close')
                run.wait_ui('settings-returned', lambda d: 'settings.version' in identifiers(d) and 'library.trash.close' not in identifiers(d))
                run.workspace()
                run.tap('library.add')
                data = run.wait_ui('editor-focused', lambda d: 'editor.keyboard.dismiss' in identifiers(d))
                controls(data, ('editor.close', 'editor.save', 'editor.keyboard.help', 'editor.keyboard.dismiss'),
                         ('editor.help', 'editor.more'))
                input_values = {'editor.title': '入力保持の確認', 'editor.body': (Path(__file__).resolve().parents[1] / 'validation/EditorMarkdown.txt').read_text()}
                for identifier, value in input_values.items():
                    run.paste_editor(identifier, value)
                run.screenshot('editor-keyboard-controls')
                run.select_editor_mode('プレビュー')
                preview = run.wait_ui('markdown-preview', lambda d: 'editor.body' not in identifiers(d)
                                      and 'editor.keyboard.dismiss' not in identifiers(d)
                                      and any(e.get('role') == 'Heading' and e.get('label') == '見出し' for e in d['entries']))
                labels = {entry.get('label') for entry in preview['entries']}
                if not {'見出し', '太字と本文 👩🏽‍💻'} <= labels or 'editor.body' in identifiers(preview):
                    raise VerificationError('Markdown preview must show rendered text and hide source input')
                run.screenshot('editor-markdown-preview')
                run.select_editor_mode('入力')
                editing = run.wait_ui('markdown-input-restored', lambda d: 'editor.keyboard.dismiss' in identifiers(d)
                                      and 'editor.body' in identifiers(d))
                actual = {e['uniqueId']: e.get('value') for e in editing['entries'] if e.get('uniqueId') in input_values}
                if actual != input_values:
                    raise VerificationError('Preview changed the editor source')
                run.tap('editor.keyboard.help')
                run.wait_ui('help', lambda d: 'editor.lengthLimit' in identifiers(d))
                run.screenshot('editor-help')
                run.tap('editor.help.close')
                restored = run.wait_ui('focus-restored', lambda d: 'editor.keyboard.dismiss' in identifiers(d) and 'editor.lengthLimit' not in identifiers(d))
                actual = {e['uniqueId']: e.get('value') for e in restored['entries'] if e.get('uniqueId') in input_values}
                if actual != input_values:
                    raise VerificationError('Help changed the populated editor title or body')
                run.tap('editor.keyboard.dismiss')
                data = run.wait_ui('editor-unfocused', lambda d: 'editor.help' in identifiers(d) and 'editor.keyboard.dismiss' not in identifiers(d))
                controls(data, ('editor.close', 'editor.save', 'editor.help', 'editor.more'),
                         ('editor.keyboard.help', 'editor.keyboard.dismiss'))
                if not any(e.get('label', '').startswith('閉じると下書き') for e in data['entries']):
                    raise VerificationError('Preservation guidance must explain save and close')
                run.screenshot('editor-guidance')
                run.tap('editor.close')
                run.wait_ui('caller-preserved', lambda d: 'library.add' in identifiers(d) and 'editor.body' not in identifiers(d))
                run.wait_ui('library-returned', lambda d: 'library.filter.pinned' in identifiers(d))
                for collection, headings in (
                    ('pinned', {'ピン留めした項目', 'ピン留めした項目はありません'}),
                    ('drafts', {'編集中の項目', '下書きはありません'}),
                ):
                    def collection_visible(data):
                        return ('editor.body' not in identifiers(data)
                                and any(e.get('label') in headings for e in data['entries']))
                    run.tap('library.filter.' + collection)
                    run.wait_ui(collection + '-selected', collection_visible)
                    run.tap('library.add')
                    run.wait_ui(collection + '-new-editor', lambda d: 'editor.body' in identifiers(d))
                    run.tap('editor.close')
                    run.wait_ui(collection + '-creation-returned', collection_visible)
                    run.screenshot('creation-returns-to-' + collection)
                run.tap('library.filter.all')
                run.manifest['assertions'] = {
                    'search_does_not_focus_on_entry': True,
                    'search_input_width_stable_across_focus': True,
                    'settings_version_matches_bundle': expected,
                    'settings_has_no_create_action': True,
                    'settings_deleted_returns': True,
                    'workspace_controls_at_least_44pt': True,
                    'settings_hierarchical_navigation': True,
                    'native_toolbar_and_custom_action_bounds': True,
                    'keyboard_and_screen_actions_exclusive': True,
                    'help_restores_focus': True,
                    'editor_returns_to_caller': True,
                    'help_preserves_title_and_body': True,
                    'markdown_preview_hides_syntax_and_restores_source': True,
                    'creation_preserves_collection': True,
                    'portrait_only_bundle': True,
                }
    except (Exception, KeyboardInterrupt) as exc:
        error = exc
    finally:
        run.finish(error)
    if error is not None:
        raise SystemExit(repr(error))


if __name__ == '__main__':
    main()
