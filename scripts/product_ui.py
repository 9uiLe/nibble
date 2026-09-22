"""Observed native navigation and editor operations for product UI scenarios."""
from ios import Run, VerificationError


TAB_LABELS = {'navigation.tab.library': '一覧', 'navigation.tab.search': '検索', 'navigation.tab.settings': '設定'}
EDITOR_MODES = ('入力', 'プレビュー')


def native_tabs(data):
    """Resolve logical selectors without altering the raw accessibility observation."""
    if data.get('appPackage') != 'nibble.9uiLe.com':
        return {}
    resolved = {}
    for selector, label in TAB_LABELS.items():
        matches = [entry for entry in data['entries']
                   if entry.get('label') == label
                   and (entry.get('uniqueId') == selector or entry.get('role') == 'RadioButton')]
        entry = unique_entry(matches, 'native tab: ' + label)
        if entry is not None:
            resolved[selector] = entry
    return resolved


def unique_entry(entries, description):
    if len(entries) > 1:
        raise VerificationError('Ambiguous ' + description)
    return next(iter(entries), None)


def identifiers(data):
    return {entry.get('uniqueId', '') for entry in data['entries']} | native_tabs(data).keys()


def editor_viewport(data):
    entries = data['entries']
    top = max((entry['frame']['y'] + entry['frame']['height'] for entry in entries
               if entry.get('role') == 'Group' and entry.get('uniqueId') in
               ('新規作成', '項目を編集', '共有から保存')), default=0)
    bottom = min((entry['frame']['y'] for entry in entries
                  if entry.get('uniqueId') in ('editor.keyboard.help', 'editor.help')), default=data['screen']['height'])
    return top, bottom


def input_point(data, identifier, *, trailing=False):
    entry = unique_entry([e for e in data['entries'] if e.get('uniqueId') == identifier], identifier)
    if entry is None:
        raise VerificationError('Input is missing: ' + identifier)
    frame = entry['frame']
    top, bottom = editor_viewport(data)
    top, bottom = max(top, frame['y']), min(bottom, frame['y'] + frame['height'])
    if bottom - top < 12:
        raise VerificationError('Input is covered by fixed controls: ' + identifier)
    return frame['x'] + frame['width'] * (.95 if trailing else .5), (top + bottom) / 2


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
    def tap(self, identifier):
        if identifier not in TAB_LABELS:
            return super().tap(identifier)
        entry = native_tabs(self.ui('resolve-' + identifier)).get(identifier)
        if entry is None:
            raise VerificationError('Native tab is not visible: ' + identifier)
        self._tap_frame(entry['frame'])

    def _tap_frame(self, frame, fraction=.5):
        self.command(['sim-use', 'tap', '-x', str(frame['x'] + frame['width'] * fraction),
                      '-y', str(frame['y'] + frame['height'] / 2), '--device', self.args.device])

    def select_editor_mode(self, label):
        data = self.ui('mode-' + label)
        entry, fraction = editor_mode_target(data, label)
        self._tap_frame(entry['frame'], fraction)

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

    def _focus_input(self, identifier, *, trailing=False):
        x, y = input_point(self._reveal_input(identifier), identifier, trailing=trailing)
        self.command(['sim-use', 'tap', '-x', str(x), '-y', str(y), '--duration', '.05',
                      '--post-delay', '.5', '--device', self.args.device])
        self.wait_ui(identifier + '-keyboard', lambda d: 'editor.keyboard.dismiss' in identifiers(d))
        # Focus can resize the viewport and move the field. Observe and reveal again.
        return input_point(self._reveal_input(identifier), identifier, trailing=trailing)

    def _menu_item(self, labels, *, allow_next=False):
        candidates = (*labels, '進む', 'Next') if allow_next else labels
        data = self.wait_ui('edit-menu-' + labels[0], lambda d: any(e.get('label') in candidates for e in d['entries']))
        entry = unique_entry([e for e in data['entries'] if e.get('label') in labels], 'edit menu: ' + labels[0])
        if entry is None:
            disclosure = unique_entry([e for e in data['entries'] if e.get('label') in ('進む', 'Next')
                                       and e.get('role') == 'Button'], 'edit menu disclosure')
            if disclosure is None:
                raise VerificationError('Edit menu item is missing: ' + labels[0])
            self._tap_frame(disclosure['frame'])
            return self._menu_item(labels)
        self._tap_frame(entry['frame'])

    def paste_editor(self, identifier, text, *, replace=False):
        def reflected(data):
            value = next((e.get('value', '') for e in data['entries'] if e.get('uniqueId') == identifier), '')
            # Accessibility may collapse whitespace. Scenarios also check saved/copied bytes.
            return ''.join(value.split()) == ''.join(text.split())

        x, y = self._focus_input(identifier, trailing=replace)
        if replace:
            self.command(['sim-use', 'tap', '-x', str(x), '-y', str(y), '--duration', '.7',
                          '--post-delay', '.4', '--device', self.args.device])
            self._menu_item(('すべてを選択', 'Select All'), allow_next=True)
            self._menu_item(('カット', 'Cut'))
            x, y = self._focus_input(identifier)
        self.paste_text(text, ['--target-x', str(x), '--target-y', str(y)], reflected, name=identifier + '-paste')
