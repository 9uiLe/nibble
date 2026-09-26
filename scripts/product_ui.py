"""Observed native navigation and editor operations for product UI scenarios."""
from ios import Run, VerificationError


EDITOR_MODES = ('入力', 'プレビュー')


def unique_entry(entries, description):
    if len(entries) > 1:
        raise VerificationError('Ambiguous ' + description)
    return next(iter(entries), None)


def identifiers(data):
    return {entry.get('uniqueId', '') for entry in data['entries']}


def editor_viewport(data):
    entries = data['entries']
    top = max((entry['frame']['y'] + entry['frame']['height'] for entry in entries
               if entry.get('uniqueId') == 'editor.exitGuidance' or (entry.get('role') == 'Group'
               and entry.get('uniqueId') in ('新規作成', '項目を編集', '共有から保存'))), default=0)
    # SwiftUI exposes the guidance's text, not its containing group's identifier.
    # Include its bottom padding so a partially clipped field is revealed first.
    top = max(top, max((entry['frame']['y'] + entry['frame']['height'] + 10 for entry in entries
                        if entry.get('label', '').startswith('閉じると下書き')), default=0))
    bottom = min((entry['frame']['y'] for entry in entries
                  if entry.get('uniqueId') in ('editor.keyboard.help', 'editor.help')), default=data['screen']['height'])
    return top, bottom


def input_point(data, identifier):
    entry = unique_entry([e for e in data['entries'] if e.get('uniqueId') == identifier], identifier)
    if entry is None:
        raise VerificationError('Input is missing: ' + identifier)
    frame = entry['frame']
    top, bottom = editor_viewport(data)
    top, bottom = max(top, frame['y']), min(bottom, frame['y'] + frame['height'])
    if bottom - top < 12:
        raise VerificationError('Input is covered by fixed controls: ' + identifier)
    return frame['x'] + frame['width'] * .5, (top + bottom) / 2


def editor_mode_target(data, label):
    if label not in EDITOR_MODES:
        raise ValueError('Unknown editor mode: ' + label)
    entries = data['entries']
    # The app exposes a TabGroup; the shared editor can expose individual radio buttons.
    entry = unique_entry([e for e in entries if e.get('label') == label
                          and e.get('role') in ('RadioButton', 'Tab')], 'editor mode: ' + label)
    if entry is not None:
        return entry, .5
    entry = unique_entry([e for e in entries if e.get('uniqueId') == 'editor.mode'
                          and e.get('role') == 'TabGroup'], 'editor mode control')
    if entry is None:
        raise VerificationError('Editor mode is missing: ' + label)
    return entry, .25 if label == '入力' else .75


class ProductRun(Run):
    def workspace(self, *, clear_query=False):
        data = self.ui('workspace-route')
        for _ in range(3):
            if 'navigation.settings' in identifiers(data):
                break
            if 'BackButton' not in identifiers(data):
                raise VerificationError('No visible route back to the workspace')
            self.tap('BackButton')
            data = self.wait_ui('workspace-back', lambda d: 'navigation.settings' in identifiers(d)
                                or 'settings.about' in identifiers(d))
        else:
            raise VerificationError('Workspace route did not finish')
        if clear_query and 'search.clear' in identifiers(data):
            self.tap('search.clear')
            self.wait_ui('workspace-query-cleared', lambda d: 'search.clear' not in identifiers(d))

    def open_settings(self):
        self.workspace()
        self.tap('navigation.settings')
        self.wait_ui('settings-route', lambda d: 'settings.about' in identifiers(d))

    def tap_frame(self, frame, fraction=.5):
        self.command(['sim-use', 'tap', '-x', str(frame['x'] + frame['width'] * fraction),
                      '-y', str(frame['y'] + frame['height'] / 2), '--device', self.args.device])

    def select_editor_mode(self, label):
        data = self.ui('mode-' + label)
        for attempt in range(5):
            entry, fraction = editor_mode_target(data, label)
            frame = entry['frame']
            top, bottom = editor_viewport(data)
            if min(bottom, frame['y'] + frame['height']) - max(top, frame['y']) >= 12:
                self.tap_frame(frame, fraction)
                return
            if attempt == 4 or bottom <= top:
                raise VerificationError('Cannot reveal editor mode: ' + label)
            start, end = top + (bottom - top) * .35, top + (bottom - top) * .75
            if frame['y'] >= bottom:
                start, end = end, start
            x = data['screen']['width'] * .35
            self.command(['sim-use', 'swipe', '--from', f'{x},{start}', '--to', f'{x},{end}',
                          '--duration', '.4', '--post-delay', '.5', '--device', self.args.device])
            data = self.ui('mode-' + label + f'-revealed-{attempt}')

    def _reveal_input(self, identifier):
        data = self.wait_ui(identifier + '-present', lambda d: identifier in identifiers(d))
        for attempt in range(5):
            frame = next(e['frame'] for e in data['entries'] if e.get('uniqueId') == identifier)
            top, bottom = editor_viewport(data)
            if min(bottom, frame['y'] + frame['height']) - max(top, frame['y']) >= 12:
                return data
            if attempt == 4 or bottom <= top:
                raise VerificationError('Cannot reveal input: ' + identifier)
            start, end = top + (bottom - top) * .35, top + (bottom - top) * .75
            if frame['y'] >= bottom:
                start, end = end, start
            x = data['screen']['width'] * .35
            self.command(['sim-use', 'swipe', '--from', f'{x},{start}', '--to', f'{x},{end}',
                          '--duration', '.4', '--post-delay', '.5', '--device', self.args.device])
            data = self.ui(identifier + f'-revealed-{attempt}')

    def _focus_input(self, identifier):
        x, y = input_point(self._reveal_input(identifier), identifier)
        self.command(['sim-use', 'tap', '-x', str(x), '-y', str(y), '--duration', '.05',
                      '--post-delay', '.5', '--device', self.args.device])
        self.wait_ui(identifier + '-keyboard', lambda d: 'editor.keyboard.dismiss' in identifiers(d))
        # Focus can resize the viewport and move the field. Observe and reveal again.
        return input_point(self._reveal_input(identifier), identifier)

    def paste_editor(self, identifier, text, *, replace=False):
        def reflected(data):
            value = next((e.get('value', '') for e in data['entries'] if e.get('uniqueId') == identifier), '')
            # Accessibility may collapse whitespace. Scenarios also check saved/copied bytes.
            return ''.join(value.split()) == ''.join(text.split())

        x, y = self._focus_input(identifier)
        if replace:
            self.command(['sim-use', 'ios', 'key-combo', '--modifiers', '227', '--key', '4',
                          '--device', self.args.device])
            self.command(['sim-use', 'ios', 'key-combo', '--modifiers', '227', '--key', '27',
                          '--device', self.args.device])
            x, y = self._focus_input(identifier)
        self.paste_text(text, ['--target-x', str(x), '--target-y', str(y)], reflected, name=identifier + '-paste')
