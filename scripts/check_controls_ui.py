#!/usr/bin/env python3
"""Exercise long literal input and adaptive standard text on the selected Simulator."""
import argparse
from types import SimpleNamespace
from uuid import uuid4

from ios import XCRUN, VerificationError, simulator_lock
from product_ui import WorkspaceRun as Run, identifiers, workspace_entry, workspace_text
from check_about_ui import read_setting_topic
from check_library_ui import assert_copy_receipt


def assert_adaptive_text(standard, enlarged):
    if enlarged['height'] <= standard['height'] + 1:
        raise VerificationError('Standard body text did not adapt to the larger system text size')


def exercise_controls(run):
    title = '長文と文字サイズ ' + uuid4().hex[:8]
    body = ('  # 記号を残す\r\n**か\u3099** 👩🏽‍💻 {{ literal }}\n' * 90) + '\t終端  '
    card = run.create_workspace_card(title, body)
    run.reveal_workspace(card)
    run.tap(card)
    run.wait_ui('long-literal-confirmation', lambda d: {'workspace.use.preview', 'workspace.use.copy'} <= identifiers(d))
    run.screenshot('long-literal-preview-top')
    run.tap('workspace.use.copy')
    copied = run.wait_ui('long-literal-copy-receipt', lambda d: 'workspace.use.receipt' in identifiers(d))
    assert_copy_receipt(copied)
    if run.command([XCRUN, 'simctl', 'pbpaste', run.args.device], 'long-literal-exact-copy').encode('utf-8') != body.encode('utf-8'):
        raise VerificationError('Long literal text changed during native input, save, preview or copy')
    run.workspace()
    run.open_settings()
    standard = read_setting_topic(run, 'workspace.settings.copyGuide')
    run.command([XCRUN, 'simctl', 'ui', run.args.device, 'content_size', 'accessibility-extra-extra-extra-large'])
    run.workspace()
    run.open_settings()
    enlarged = read_setting_topic(run, 'workspace.settings.copyGuide')
    assert_adaptive_text(standard, enlarged)
    run.reveal_workspace('workspace.trash')
    run.tap('workspace.trash')
    run.wait_ui('large-text-trash-route', lambda d: 'BackButton' in identifiers(d))
    run.screenshot('large-text-management-usable')
    data = run.workspace()
    if workspace_entry(data, 'workspace.create') is None:
        raise VerificationError('Adaptive navigation did not return to an operable workspace')
    run.manifest['assertions'] = {'native_input_saved_and_copied_exact_long_literal': True,
        'body_utf8_bytes': len(body.encode('utf-8')), 'system_text_size_changes_layout': True,
        'standard_guidance': standard, 'enlarged_guidance': enlarged,
        'observed_screen_width': data['screen']['width'],
        'narrow_screen_exercised': data['screen']['width'] <= 375,
        'large_text_management_operable': True,
        'japanese_ime': 'not established by paste; separately exercise OS conversion, correction and commit'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    run = Run(SimpleNamespace(command='controls-ui', device=args.device, configuration='Release', project_config='app/project.json'))
    error, original = None, None
    try:
        run.setup()
        with simulator_lock(args.device):
            run.boot()
            original = run.command([XCRUN, 'simctl', 'ui', args.device, 'content_size']).strip()
            run.command([XCRUN, 'simctl', 'ui', args.device, 'content_size', 'large'])
            run.launch()
            with run.recording():
                exercise_controls(run)
    except (Exception, KeyboardInterrupt) as caught:
        error = caught
    finally:
        if original is not None:
            try:
                run.command([XCRUN, 'simctl', 'ui', args.device, 'content_size', original])
            except (Exception, KeyboardInterrupt) as caught:
                error = error or caught
        run.finish(error)
    if error is not None:
        raise SystemExit(repr(error))


if __name__ == '__main__':
    main()
