#!/usr/bin/env python3
"""Compatibility entrypoint for the replacement product's usage, keyboard and privacy guidance."""
import argparse
from types import SimpleNamespace

from ios import VerificationError, simulator_lock
from product_ui import WorkspaceRun as Run, identifiers, workspace_entry, workspace_text

TOPICS = {
    'workspace.settings.copyGuide': ('コピー', '入力欄', 'ペースト'),
    'workspace.settings.keyboardGuide': ('ピン留め', '差し替え', 'キーボード'),
    'workspace.settings.privacy': ('端末内', '通信せず', 'クリップボード'),
}


def explanation_text(data, identifier):
    text = workspace_text(data, identifier)
    if not all(word in text for word in TOPICS[identifier]):
        raise VerificationError('Guidance is missing a necessary action or data explanation: ' + identifier)
    return text


def reading_intersection(data, identifier):
    entry = workspace_entry(data, identifier)
    if entry is None:
        return None
    frame, screen = entry['frame'], data['screen']
    top = max((e['frame']['y'] + e['frame']['height'] + 8 for e in data['entries']
               if e.get('uniqueId') in ('workspace.settings.close', 'BackButton')), default=90)
    bottom = screen['height'] - 16
    if frame['width'] <= 0 or frame['height'] <= 0 or frame['x'] < 0 or frame['x'] + frame['width'] > screen['width'] + 1:
        raise VerificationError('Guidance has invalid horizontal reading bounds')
    start, end = max(0, top - frame['y']), min(frame['height'], bottom - frame['y'])
    if end - start < 16:
        return None
    return start, end, frame['height']


def coverage_complete(intervals, height):
    edge = 0
    for start, end in sorted(intervals):
        if start > edge + 2:
            return False
        edge = max(edge, end)
    return edge >= height - 2


def read_setting_topic(run, identifier):
    intervals, first_height = [], None
    last_scroll_up = False
    for attempt in range(30):
        data = run.ui(identifier + f'-reading-{attempt}')
        if 'workspace.settings.close' not in identifiers(data):
            raise VerificationError('Settings left while reading guidance')
        visible = reading_intersection(data, identifier)
        if visible:
            explanation_text(data, identifier)
            start, end, height = visible
            if first_height is not None and abs(first_height - height) > 2:
                raise VerificationError('Guidance geometry changed during one reading pass')
            first_height = height
            intervals.append((start, end))
            run.screenshot(identifier + f'-reading-{attempt}')
            if coverage_complete(intervals, height):
                return {'height': height, 'visible_intervals': intervals, 'snapshots': attempt + 1}
        if attempt < 29:
            entry = workspace_entry(data, identifier)
            if entry is not None and first_height is not None:
                edge = 0
                for start, end in sorted(intervals):
                    if start > edge + 2:
                        break
                    edge = max(edge, end)
                top = max((e['frame']['y'] + e['frame']['height'] + 8 for e in data['entries']
                           if e.get('uniqueId') in ('workspace.settings.close', 'BackButton')), default=90)
                up = entry['frame']['y'] + edge < top + 2
            elif first_height is not None:
                # The target disappeared after a measured step: reverse toward
                # its last observed location instead of skipping the remaining gap.
                up = not last_scroll_up
            else:
                up = entry is not None and entry['frame']['y'] < 0
            run.scroll_workspace(data, up=up, reading=True)
            last_scroll_up = up
    raise VerificationError('The complete guidance was not reachable by bounded scrolling: ' + identifier)


class AboutCheck:
    def __init__(self, run, story='about'):
        self.run, self.story = run, story

    def exercise(self):
        self.run.open_settings()
        observations = {}
        # Reopen each time so each topic starts from the same actual route.
        for identifier in TOPICS:
            self.run.workspace()
            self.run.open_settings()
            observations[identifier] = read_setting_topic(self.run, identifier)
        self.run.reveal_workspace('workspace.trash')
        self.run.tap('workspace.trash')
        self.run.wait_ui('settings-reached-trash', lambda d: 'BackButton' in identifiers(d)
                         and any('ごみ箱' == e.get('label') for e in d['entries']))
        self.run.screenshot('settings-trash-management-reachable')
        self.run.workspace()
        self.run.manifest['guidance_observations'] = observations
        self.run.manifest['assertions'] = {'native_copy_and_paste_steps_explained': True,
            'optional_pinned_fixed_keyboard_explained': True, 'local_data_and_clipboard_scope_explained': True,
            'all_guidance_readable_by_scroll': True, 'trash_management_route_executed': True,
            'scope': 'Guidance and management navigation; actual OS keyboard, Japanese IME and Share Sheet require separate operations.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--story', choices=('about', 'keyboard'), default='about')
    args = parser.parse_args()
    # Preserve the catalog/evidence command identity; there is no Rive assertion.
    run = Run(SimpleNamespace(command='rive-' + args.story, device=args.device, configuration='Release', project_config='app/project.json'))
    error = None
    try:
        run.setup()
        with simulator_lock(args.device):
            run.launch()
            with run.recording():
                AboutCheck(run, args.story).exercise()
    except (Exception, KeyboardInterrupt) as caught:
        error = caught
    finally:
        run.finish(error)
    if error is not None:
        raise SystemExit(repr(error))


if __name__ == '__main__':
    main()
