#!/usr/bin/env python3
"""Verify settings, search entry and editor controls on an explicit iOS Simulator."""
import argparse
import plistlib
import time
from types import SimpleNamespace

from ios import Run, VerificationError


def identifiers(data):
    return {entry.get('uniqueId') for entry in data['entries']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    run = Run(SimpleNamespace(command='controls-ui', device=args.device,
                              configuration='Release', project_config='app/project.json'))
    error = None

    def wait(name, predicate):
        for attempt in range(20):
            data = run.ui(f'{name}-{attempt}', allow_empty=True)
            if predicate(data):
                return data
            time.sleep(.2)
        raise VerificationError('UI did not reach expected state: ' + name)

    def controls(data, expected, absent=()):
        present = identifiers(data)
        if not set(expected) <= present or set(absent) & present:
            raise VerificationError('Unexpected controls: ' + str(present))
        for entry in data['entries']:
            if entry.get('uniqueId') in expected:
                frame = entry['frame']
                # Native navigation items expose their 36pt visual bounds in AX;
                # UIKit owns the surrounding hit area. Exercise each actual action.
                native = entry['uniqueId'] in ('editor.close', 'editor.save', 'editor.help.close', 'library.trash.close')
                creation = entry['uniqueId'] == 'library.add'
                minimum = 36 if native or creation else 44
                if frame['width'] < minimum or frame['height'] < minimum:
                    raise VerificationError('Control is smaller than its touch target: ' + str(entry))
                if creation and any(abs(frame[axis] - 36) > .5 for axis in ('width', 'height')):
                    raise VerificationError('Creation button must be 36 by 36 points: ' + str(entry))

    try:
        run.setup()
        with run.device_lock():
            run.launch()
            root = wait('root', lambda d: 'navigation.tab.search' in identifiers(d))
            with run.recording():
                tabs = {e.get('uniqueId'): e['frame'] for e in root['entries']
                        if e.get('uniqueId', '').startswith('navigation.tab.')}
                start, end = tabs['navigation.tab.library'], tabs['navigation.tab.settings']
                run.command(['sim-use', 'swipe', '--from', f"{start['x'] + start['width']/2},{start['y'] + start['height']/2}",
                             '--to', f"{end['x'] + end['width']/2},{end['y'] + end['height']/2}",
                             '--duration', '0.6', '--device', args.device])
                wait('native-tab-drag', lambda d: 'settings.version' in identifiers(d))
                run.tap('navigation.tab.search')
                wait('search', lambda d: any(e.get('uniqueId') == 'navigation.title' and e.get('label') == '検索'
                                             for e in d['entries']))
                # Observe beyond presentation completion to catch delayed auto-focus.
                time.sleep(.5)
                data = run.ui('search-idle')
                controls(data, ('navigation.tab.library', 'navigation.tab.search', 'navigation.tab.settings', 'library.add'),
                         ('search.done', 'Search'))
                run.screenshot('search-without-keyboard')
                run.tap('navigation.tab.settings')
                data = wait('settings', lambda d: 'settings.version' in identifiers(d))
                info = plistlib.loads((run.derived / 'Build/Products/Release-iphonesimulator/Nibble.app/Info.plist').read_bytes())
                expected = f"バージョン {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})"
                version = next(e for e in data['entries'] if e.get('uniqueId') == 'settings.version')
                if version['label'] != expected:
                    raise VerificationError('Settings version differs from the installed bundle')
                run.screenshot('settings-version-disclosures')
                run.tap('library.trash')
                data = wait('deleted', lambda d: 'library.trash.close' in identifiers(d))
                controls(data, ('library.trash.close',))
                run.screenshot('deleted-close')
                run.tap('library.trash.close')
                wait('settings-returned', lambda d: 'settings.version' in identifiers(d) and 'library.trash.close' not in identifiers(d))
                run.tap('library.add')
                data = wait('editor-focused', lambda d: 'editor.keyboard.dismiss' in identifiers(d))
                controls(data, ('editor.close', 'editor.save', 'editor.keyboard.help', 'editor.keyboard.dismiss'),
                         ('editor.help', 'editor.more'))
                run.screenshot('editor-keyboard-controls')
                run.tap('editor.keyboard.help')
                wait('help', lambda d: 'editor.lengthLimit' in identifiers(d))
                run.screenshot('editor-help')
                run.tap('editor.help.close')
                wait('focus-restored', lambda d: 'editor.keyboard.dismiss' in identifiers(d) and 'editor.lengthLimit' not in identifiers(d))
                run.tap('editor.keyboard.dismiss')
                data = wait('editor-unfocused', lambda d: 'editor.help' in identifiers(d) and 'editor.keyboard.dismiss' not in identifiers(d))
                controls(data, ('editor.close', 'editor.save', 'editor.help', 'editor.more'),
                         ('editor.keyboard.help', 'editor.keyboard.dismiss'))
                run.screenshot('editor-guidance')
                run.tap('editor.close')
                wait('caller-preserved', lambda d: 'settings.version' in identifiers(d) and 'editor.body' not in identifiers(d))
                run.tap('navigation.tab.library')
                wait('library-returned', lambda d: 'library.filter.pinned' in identifiers(d))
                for collection, headings in (
                    ('pinned', {'ピン留めした項目', 'ピン留めした項目はありません'}),
                    ('drafts', {'タップして、編集を再開', '下書きはありません'}),
                ):
                    def collection_visible(data):
                        return ('editor.body' not in identifiers(data)
                                and any(e.get('label') in headings for e in data['entries']))
                    run.tap('library.filter.' + collection)
                    wait(collection + '-selected', collection_visible)
                    run.tap('library.add')
                    wait(collection + '-new-editor', lambda d: 'editor.body' in identifiers(d))
                    run.tap('editor.close')
                    wait(collection + '-creation-returned', collection_visible)
                    run.screenshot('creation-returns-to-' + collection)
                run.tap('library.filter.all')
                run.manifest['assertions'] = {
                    'search_does_not_focus_on_entry': True,
                    'settings_version_matches_bundle': expected,
                    'settings_deleted_returns': True,
                    'native_tab_targets_at_least_44pt': True,
                    'native_tab_drag_selects_destination': True,
                    'native_toolbar_and_custom_action_bounds': True,
                    'keyboard_and_screen_actions_exclusive': True,
                    'help_restores_focus': True,
                    'empty_editor_returns_to_caller': True,
                    'creation_preserves_collection': True,
                }
    except BaseException as exc:
        error = str(exc)
        raise
    finally:
        run.finish(error)


if __name__ == '__main__':
    main()
