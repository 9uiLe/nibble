"""Adaptive interface checks reject missing controls without demanding fixed frames."""
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
from check_interface_ui import capture_controls, exercise_interface, visible_controls
from ios import VerificationError


def observation(identifier, *, y=100, height=48):
    return {'screen': {'width': 375, 'height': 667}, 'entries': [
        {'uniqueId': identifier, 'frame': {'x': 16, 'y': y, 'width': 343, 'height': height}}]}


class AdaptiveInterfaceTests(unittest.TestCase):
    def test_editor_opens_before_its_lazy_body_is_available_and_then_reveals_the_body(self):
        run = Mock(manifest={})
        initial = {'entries': [{'uniqueId': name} for name in
                               ('workspace.editor.title', 'workspace.editor.close', 'workspace.editor.save')]}
        run.reveal_workspace.side_effect = observation

        def wait_for_editor(name, predicate):
            if not predicate(initial):
                raise VerificationError('Editor readiness rejected the observed toolbar')

        class CapturedEditor(Exception):
            pass

        def capture_until_editor(run, mode, screen, expected):
            frames = capture_controls(run, mode, screen, expected)
            if screen == 'editor':
                raise CapturedEditor
            return frames

        run.wait_ui.side_effect = wait_for_editor
        with patch('check_interface_ui.capture_controls', side_effect=capture_until_editor):
            with self.assertRaises(CapturedEditor):
                exercise_interface(run, Mock())
        self.assertIn('workspace.editor.body', run.manifest['adaptive_layout']['default']['editor'])
        self.assertIn('workspace.editor.body', [call.args[0] for call in run.reveal_workspace.call_args_list])

    def test_editor_readiness_rejects_each_missing_toolbar_action_even_when_body_exists(self):
        for missing in ('workspace.editor.close', 'workspace.editor.save'):
            with self.subTest(missing=missing):
                run = Mock(manifest={})
                initial = {'entries': [{'uniqueId': name} for name in
                                       ('workspace.editor.body', 'workspace.editor.close', 'workspace.editor.save')
                                       if name != missing]}
                run.reveal_workspace.side_effect = observation

                def wait_for_editor(name, predicate):
                    if not predicate(initial):
                        raise VerificationError('Editor toolbar is not ready')

                run.wait_ui.side_effect = wait_for_editor
                with self.assertRaisesRegex(VerificationError, 'toolbar is not ready'):
                    exercise_interface(run, Mock())
                self.assertNotIn('editor', run.manifest['adaptive_layout']['default'])

    def test_controls_may_move_and_grow_with_system_text(self):
        identifier = 'workspace.editor.body'
        standard = visible_controls(observation(identifier), (identifier,))
        enlarged = visible_controls(observation(identifier, y=220, height=240), (identifier,))
        self.assertNotEqual(standard, enlarged)
        self.assertEqual(enlarged[identifier]['height'], 240)

    def test_missing_duplicate_and_clipped_controls_are_failures(self):
        identifier = 'workspace.editor.save'
        duplicate = observation(identifier)
        duplicate['entries'] *= 2
        for data in ({'screen': {'width': 375, 'height': 667}, 'entries': []},
                     observation(identifier, y=650), duplicate):
            with self.subTest(data=data), self.assertRaises(VerificationError):
                visible_controls(data, (identifier,))

    def test_form_fields_are_revealed_and_recorded_at_their_actual_scroll_positions(self):
        run = Mock(manifest={})
        first, second = 'workspace.editor.title', 'workspace.editor.body'
        run.reveal_workspace.side_effect = [observation(first), observation(second, y=200, height=240)]
        frames = capture_controls(run, 'accessibility', 'editor', (first, second))
        self.assertEqual(set(frames), {first, second})
        self.assertEqual([call.args[0] for call in run.reveal_workspace.call_args_list], [first, second])
        self.assertEqual(run.manifest['adaptive_layout']['accessibility']['editor'], frames)
        self.assertEqual(run.screenshot.call_count, 2)


if __name__ == '__main__':
    unittest.main()
