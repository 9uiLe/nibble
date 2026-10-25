"""Adaptive verification checks real change rather than preserving old fixed frames."""
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parents[1]))
from check_controls_ui import assert_adaptive_text
from ios import VerificationError
from product_ui import WorkspaceRun, workspace_visible


class AdaptiveControlTests(unittest.TestCase):
    def test_larger_standard_text_must_change_its_measured_height(self):
        assert_adaptive_text({'height': 80}, {'height': 200})
        for height in (0, 79, 80, 81):
            with self.subTest(height=height), self.assertRaises(VerificationError):
                assert_adaptive_text({'height': 80}, {'height': height})

    def test_visibility_rejects_clipped_or_unobserved_controls(self):
        data = {'screen': {'width': 375, 'height': 667}}
        self.assertTrue(workspace_visible(data, {'frame': {'x': 16, 'y': 100, 'width': 343, 'height': 44}}))
        for frame in ({'x': -1, 'y': 100, 'width': 343, 'height': 44},
                      {'x': 16, 'y': 650, 'width': 343, 'height': 44},
                      {'x': 16, 'y': 100, 'width': 0, 'height': 44}):
            self.assertFalse(workspace_visible(data, {'frame': frame}))
        self.assertFalse(workspace_visible(data, None))

    def test_unreachable_control_fails_after_finite_observed_swipes(self):
        run = object.__new__(WorkspaceRun)
        run.args = SimpleNamespace(device='owned')
        run.ui = Mock(return_value={'screen': {'width': 375, 'height': 667}, 'entries': [
            {'uniqueId': 'workspace.editor.title', 'role': 'TextArea',
             'frame': {'x': 32, 'y': 200, 'width': 311, 'height': 48}}]})
        run.command = Mock()
        with self.assertRaisesRegex(VerificationError, 'not reachable'):
            run.reveal_workspace('workspace.editor.body', attempts=3)
        self.assertEqual(run.ui.call_count, 3)
        self.assertEqual(run.command.call_count, 2)
        self.assertTrue(all(call.args[0][-2:] == ['--device', 'owned'] for call in run.command.call_args_list))


if __name__ == '__main__':
    unittest.main()
