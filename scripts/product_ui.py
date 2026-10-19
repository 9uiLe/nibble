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
            data = self.wait_ui('workspace-query-cleared', lambda d: 'search.clear' not in identifiers(d))
        return data

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

    def _settled_input(self, identifier, name):
        previous = None

        def settled(data):
            nonlocal previous
            entry = unique_entry([e for e in data['entries'] if e.get('uniqueId') == identifier], identifier)
            layout = (dict(entry['frame']), editor_viewport(data)) if entry is not None else None
            unchanged = layout is not None and layout == previous
            previous = layout
            return unchanged

        return self.wait_ui(name, settled)

    def _reveal_input(self, identifier):
        data = self._settled_input(identifier, identifier + '-present')
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
            # Interactive keyboard dismissal can move a field after the swipe completes.
            data = self._settled_input(identifier, identifier + f'-revealed-{attempt}')

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


# The old ProductRun/editor-mode helpers above remain compatibility inputs for
# tooling tests. Replacement-product drivers use this observed native route.
def workspace_entry(data, identifier):
    return unique_entry([e for e in data.get('entries', []) if e.get('uniqueId') == identifier], identifier)


def workspace_text(data, identifier):
    entry = workspace_entry(data, identifier)
    if entry is None:
        raise VerificationError('Expected observed element: ' + identifier)
    return entry.get('value') if entry.get('value') is not None else entry.get('label', '')


def workspace_keyboard_top(data):
    """Infer only an observed software keyboard, including its candidate bar."""
    entries, screen = data.get('entries', []), data['screen']
    lower = screen['height'] * .3
    controls = [e for e in entries if e.get('role') in ('Button', 'Key')
                and e.get('frame', {}).get('y', -1) >= lower
                and not e.get('uniqueId', '').startswith(('workspace.', 'fixture.'))]
    names = {e.get('uniqueId') for e in controls}
    if not {'delete', 'Return'} <= names:
        return None
    kana = {'あ', 'か', 'さ', 'た', 'な', 'は', 'ま', 'や', 'ら', 'わ', '、', '。'}
    standard = {'delete', 'Return', 'emoji', 'dictation', 'space', 'shift', 'Shift', '゛'}
    keys = [e for e in controls if e.get('uniqueId') in standard
            or e.get('label') in kana
            or (len(e.get('label', '')) == 1 and e['label'].isascii() and e['label'].isalpha())]
    first_row = min(e['frame']['y'] for e in keys)
    row_height = min(e['frame']['height'] for e in keys if e['frame']['height'] > 0)
    # The normalized AX tree omits the Keyboard container on iOS 26.5. Its
    # candidate Group/buttons directly above the first key row are still observed.
    candidates = [e['frame']['y'] for e in entries
                  if e.get('role') in ('Group', 'Button') and e.get('frame', {}).get('width', 0) > 0
                  and not e.get('uniqueId', '').startswith(('workspace.', 'fixture.'))
                  and first_row - row_height - 16 <= e['frame']['y'] < first_row
                  and 0 < e['frame']['height'] <= row_height * 1.5]
    return min([first_row, *candidates])


WORKSPACE_TOOLBAR_IDS = {'workspace.editor.close', 'workspace.editor.save', 'workspace.use.close',
                         'workspace.settings.close', 'workspace.create', 'workspace.settings', 'BackButton'}


def workspace_viewport(data):
    screen = data['screen']
    bars = [e['frame']['y'] + e['frame']['height'] for e in data.get('entries', [])
            if 'frame' in e and (e.get('uniqueId') in WORKSPACE_TOOLBAR_IDS
            or (e.get('role') in ('Group', 'Heading') and e.get('region', {}).get('kind') == 'Top'))
            and e['frame']['y'] + e['frame']['height'] <= screen['height'] * .3]
    top = max([screen.get('y', 0), *bars])
    keyboard = workspace_keyboard_top(data)
    screen_bottom = screen.get('y', 0) + screen['height']
    bottom = min(screen_bottom, keyboard if keyboard is not None else screen_bottom)
    if screen['width'] <= 0 or bottom - top < 44:
        raise VerificationError('No observed content viewport clear of navigation and keyboard')
    return top, bottom


def workspace_input_point(data, identifier):
    entry = workspace_entry(data, identifier)
    if entry is None or entry.get('role') not in ('TextArea', 'TextField', 'SearchField'):
        raise VerificationError('No observed editable field: ' + identifier)
    frame, screen = entry['frame'], data['screen']
    top, bottom = workspace_viewport(data)
    left, right = max(0, frame['x']), min(screen['width'], frame['x'] + frame['width'])
    high, low = max(top, frame['y']), min(bottom, frame['y'] + frame['height'])
    if entry['role'] == 'TextArea':
        if right - left < 44 or low - high < 44:
            raise VerificationError('Input has less than 44pt exposed clear of navigation and keyboard: ' + identifier)
    else:
        # Native TextField AX bounds are visual bounds (34pt for this product's
        # search on SE3), unlike the larger partial TextArea interaction surface.
        fully_exposed = (left == frame['x'] and right == frame['x'] + frame['width']
                         and high == frame['y'] and low == frame['y'] + frame['height'])
        if not fully_exposed or frame['height'] < 22 or frame['width'] < 44:
            raise VerificationError('Native text field is not fully exposed clear of navigation and keyboard: ' + identifier)
    return (left + right) / 2, (high + low) / 2


def workspace_visible(data, entry):
    if entry is None:
        return False
    if entry.get('role') in ('TextArea', 'TextField', 'SearchField'):
        try:
            workspace_input_point(data, entry.get('uniqueId', ''))
            return True
        except VerificationError:
            return False
    frame, screen = entry.get('frame', {}), data.get('screen', {})
    top, bottom = workspace_viewport(data)
    minimum_y = screen.get('y', 0) if entry.get('uniqueId') in WORKSPACE_TOOLBAR_IDS else top
    return (frame.get('width', 0) > 0 and frame.get('height', 0) > 0
            and frame.get('x', -1) >= screen.get('x', 0) and frame.get('y', -1) >= minimum_y
            and frame['x'] + frame['width'] <= screen.get('x', 0) + screen.get('width', 0)
            and frame['y'] + frame['height'] <= bottom)


def workspace_scroll_gutter(data):
    screen = data['screen']
    fields = [e['frame'] for e in data.get('entries', []) if e.get('role') in ('TextArea', 'TextField', 'SearchField')
              and 'frame' in e and e['frame']['width'] > 0]
    candidates = fields or [e['frame'] for e in data.get('entries', [])
                            if 'frame' in e and e['frame']['width'] > screen['width'] * .5 and e['frame']['x'] > 0]
    if not candidates:
        raise VerificationError('No observed Form gutter for a safe content scroll')
    left = min(frame['x'] for frame in candidates)
    right = max(frame['x'] + frame['width'] for frame in candidates)
    if left >= 8:
        return left / 2
    if screen['width'] - right >= 8:
        return (screen['width'] + right) / 2
    raise VerificationError('No observed Form gutter outside editable content')


def workspace_scroll_position(data):
    top, bottom = workspace_viewport(data)
    content = []
    for entry in data.get('entries', []):
        frame = entry.get('frame', {})
        if (entry.get('uniqueId') in WORKSPACE_TOOLBAR_IDS or not frame
                or frame['y'] + frame['height'] <= top or frame['y'] >= bottom):
            continue
        content.append((entry.get('uniqueId', ''), entry.get('role', ''), entry.get('label', ''),
                        tuple(frame[key] for key in ('x', 'y', 'width', 'height'))))
    return (top, bottom), tuple(sorted(content))


class WorkspaceRun(ProductRun):
    def _settled_workspace_target(self, identifier, name):
        previous = None

        def settled(data):
            nonlocal previous
            entry = workspace_entry(data, identifier)
            current = (dict(entry['frame']), workspace_viewport(data)) if entry is not None else None
            unchanged = current is not None and current == previous
            previous = current
            return unchanged

        return self.wait_ui(name, settled)

    def scroll_workspace(self, data, *, up=False, reading=False):
        top, bottom = workspace_viewport(data)
        x = workspace_scroll_gutter(data)
        height = bottom - top
        start, end = ((.35, .65) if up else (.65, .35)) if reading else ((.2, .8) if up else (.8, .2))
        self.command(['sim-use', 'swipe', '--from', f'{x},{top + height * start}',
                      '--to', f'{x},{top + height * end}', '--duration', '.7' if reading else '.35',
                      '--post-delay', '.25', '--device', self.args.device])

    def reveal_workspace(self, identifier, *, attempts=48):
        # Maximum-text Settings spans more than twelve short reading steps.
        # Budget for reaching an edge and returning past the starting point.
        up, previous_position, blocked = False, None, set()
        for attempt in range(attempts):
            data = self.ui(identifier + f'-reveal-{attempt}')
            entry = workspace_entry(data, identifier)
            if workspace_visible(data, entry):
                data = self._settled_workspace_target(identifier, identifier + f'-reveal-settled-{attempt}')
                entry = workspace_entry(data, identifier)
                if workspace_visible(data, entry):
                    return data
            if attempt + 1 < attempts:
                position = workspace_scroll_position(data)
                if entry is not None:
                    up = entry['frame']['y'] < workspace_viewport(data)[0]
                elif position == previous_position:
                    # Lazy Forms omit offscreen targets from AX. Once the
                    # observed content stops moving, search the other way.
                    blocked.add(up)
                    up = not up
                    if up in blocked:
                        break
                self.scroll_workspace(data, up=up, reading=True)
                previous_position = position
        raise VerificationError('Element is not reachable: ' + identifier)

    def workspace(self, *, clear_query=False):
        data = self.ui('workspace-route')
        for _ in range(8):
            present = identifiers(data)
            modal = {'workspace.editor.close', 'workspace.use.close', 'workspace.settings.close'} & present
            if not modal and {'workspace.create', 'workspace.search', 'workspace.settings'} <= present:
                if clear_query:
                    self.paste_editor('workspace.search', '', replace=True)
                return data
            candidates = [name for name in ('workspace.editor.close', 'workspace.use.close',
                          'workspace.settings.close', 'BackButton') if name in present]
            if not candidates:
                raise VerificationError('No observed route to the workspace')
            self.tap(candidates[0])
            data = self.wait_ui('workspace-return', lambda d: any(name in identifiers(d) for name in
                                ('workspace.create', 'workspace.settings.close', 'BackButton')))
        raise VerificationError('Workspace navigation did not finish')

    def open_settings(self):
        self.workspace()
        self.tap('workspace.settings')
        return self.wait_ui('settings-open', lambda d: 'workspace.settings.close' in identifiers(d))

    def _focus_workspace_input(self, identifier):
        data = self.reveal_workspace(identifier)
        x, y = workspace_input_point(data, identifier)
        self.command(['sim-use', 'tap', '-x', str(x), '-y', str(y), '--duration', '.05',
                      '--post-delay', '.3', '--device', self.args.device])
        self._settled_workspace_target(identifier, identifier + '-focus-layout-settled')
        # Focus can expose the OS keyboard and move the Form. Reveal again using
        # that new viewport before choosing the actual native Paste point.
        return self.reveal_workspace(identifier)

    def paste_text(self, text, target, reflected, *, name='paste'):
        if len(target) == 2 and target[0] == '--target-id':
            data = self._focus_workspace_input(target[1])
            x, y = workspace_input_point(data, target[1])
            target = ['--target-x', str(x), '--target-y', str(y)]
        return super().paste_text(text, target, reflected, name=name)

    def paste_editor(self, identifier, text, *, replace=False):
        data = self._focus_workspace_input(identifier)
        if replace:
            self.command(['sim-use', 'ios', 'key-combo', '--modifiers', '227', '--key', '4',
                          '--device', self.args.device])
            self.command(['sim-use', 'ios', 'key', '42', '--device', self.args.device])
            data = self.reveal_workspace(identifier)
        if not text:
            return self.wait_ui(identifier + '-cleared', lambda d: workspace_entry(d, identifier) is not None
                                and workspace_entry(d, identifier).get('value') in ('', None))
        x, y = workspace_input_point(data, identifier)
        return self.paste_text(text, ['--target-x', str(x), '--target-y', str(y)],
                               lambda d: workspace_entry(d, identifier) is not None
                               and ''.join(workspace_text(d, identifier).split()) == ''.join(text.split()),
                               name=identifier + '-native-paste')

    def matching_workspace_id(self, prefix, title, *, name='matching-row'):
        def matches(data):
            return [e['uniqueId'] for e in data.get('entries', [])
                    if e.get('uniqueId', '').startswith(prefix) and title in e.get('label', '')]
        data = self.wait_ui(name, lambda d: len(matches(d)) == 1)
        found = matches(data)
        if len(found) != 1:
            raise VerificationError('Expected exactly one named target: ' + title)
        return found[0]

    def create_workspace_card(self, title, body):
        self.workspace()
        self.tap('workspace.create')
        self.wait_ui('create-editor', lambda d: 'workspace.editor.body' in identifiers(d))
        self.paste_editor('workspace.editor.title', title)
        self.paste_editor('workspace.editor.body', body)
        self.tap('workspace.editor.save')
        self.wait_ui('save-completed', lambda d: 'workspace.create' in identifiers(d)
                     and 'workspace.editor.body' not in identifiers(d))
        return self.matching_workspace_id('workspace.card.', title)

    def tap_workspace_label(self, text, *, role='Button'):
        data = self.ui('label-target')
        entry = unique_entry([e for e in data.get('entries', []) if e.get('label') == text
                              and e.get('role') == role and workspace_visible(data, e)], text)
        if entry is None:
            raise VerificationError('No unique observed control: ' + text)
        self.tap_frame(entry['frame'])

    def paste_existing_clipboard(self, identifier, expected):
        data = self._focus_workspace_input(identifier)
        x, y = workspace_input_point(data, identifier)
        self.command(['sim-use', 'tap', '-x', str(x),
                      '-y', str(y), '--duration', '.8',
                      '--post-delay', '.3', '--device', self.args.device], 'external-native-edit-menu')
        menu = self.wait_ui('external-paste-menu', lambda d: any(e.get('label') in
                            ('ペースト', 'Paste', 'ペーストを許可', 'Allow Paste') for e in d.get('entries', [])))
        permission = next((e for e in menu['entries'] if e.get('label') in ('ペーストを許可', 'Allow Paste')), None)
        if permission:
            self.tap_frame(permission['frame'])
            menu = self.wait_ui('external-paste-menu-after-permission', lambda d: any(
                e.get('label') in ('ペースト', 'Paste') for e in d.get('entries', [])))
        paste = unique_entry([e for e in menu['entries'] if e.get('label') in ('ペースト', 'Paste')], 'native Paste')
        if paste is None:
            raise VerificationError('Native Paste action was not observed')
        self.tap_frame(paste['frame'])
        permission_ui = self.ui('external-after-paste')
        permission = next((e for e in permission_ui.get('entries', [])
                           if e.get('label') in ('ペーストを許可', 'Allow Paste')), None)
        if permission:
            self.tap_frame(permission['frame'])
        return self.wait_ui('external-native-paste-applied', lambda d: workspace_entry(d, identifier) is not None
                            and ''.join(workspace_text(d, identifier).split()) == ''.join(expected.split()))
