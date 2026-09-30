"""Help verification must work below the fold and fail on missing content."""
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parents[1]))
from check_controls_ui import reveal_help_limit
from ios import VerificationError


def help_screen(visible=False, height=667):
    entries = [{'uniqueId': 'editor.help.close',
                'frame': {'x': 319, 'y': 340, 'width': 36, 'height': 36}}]
    if visible:
        entries.append({'uniqueId': 'editor.lengthLimit'})
    return {'screen': {'x': 0, 'y': 0, 'width': 375, 'height': height},
            'entries': entries}


class HelpScrollTests(unittest.TestCase):
    def run_fixture(self, initial, following=()):
        return SimpleNamespace(args=SimpleNamespace(device='dedicated'),
                               wait_ui=Mock(return_value=initial),
                               ui=Mock(side_effect=following), command=Mock())

    def test_visible_content_needs_no_scroll(self):
        data = help_screen(True)
        run = self.run_fixture(data)
        self.assertIs(reveal_help_limit(run), data)
        run.command.assert_not_called()

    def test_below_fold_content_is_scrolled_into_view(self):
        visible = help_screen(True)
        run = self.run_fixture(help_screen(), [visible])
        self.assertIs(reveal_help_limit(run), visible)
        argv = run.command.call_args.args[0]
        self.assertEqual(argv[0:2], ['sim-use', 'swipe'])
        self.assertEqual(argv[-2:], ['--device', 'dedicated'])
        self.assertEqual(argv[argv.index('--from') + 1], '187.5,635')
        self.assertEqual(argv[argv.index('--to') + 1], '187.5,400')

    def test_missing_content_fails_after_bounded_scrolling(self):
        run = self.run_fixture(help_screen(), [help_screen()] * 6)
        with self.assertRaisesRegex(VerificationError, 'not reachable'):
            reveal_help_limit(run)
        self.assertEqual(run.command.call_count, 6)

    def test_invalid_viewport_is_not_swiped(self):
        run = self.run_fixture(help_screen(height=410))
        with self.assertRaisesRegex(VerificationError, 'viewport'):
            reveal_help_limit(run)
        run.command.assert_not_called()

    def test_departed_help_is_not_swiped_again(self):
        run = self.run_fixture(help_screen(), [{'entries': []}])
        with self.assertRaisesRegex(VerificationError, 'disappeared'):
            reveal_help_limit(run)
        self.assertEqual(run.command.call_count, 1)
