"""Guidance coverage cannot pass with missing text, gaps or an abandoned route."""
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parents[1]))
from check_about_ui import coverage_complete, explanation_text, read_setting_topic, reading_intersection
from ios import VerificationError

TOPIC = 'workspace.settings.copyGuide'


def screen(y=100, height=100):
    return {'screen': {'width': 375, 'height': 667}, 'entries': [
        {'uniqueId': 'workspace.settings.close', 'frame': {'x': 300, 'y': 50, 'width': 60, 'height': 36}},
        {'uniqueId': TOPIC, 'label': 'コピーして、入力欄を選びペーストしてください。',
         'frame': {'x': 16, 'y': y, 'width': 343, 'height': height}},
    ]}


class GuidanceReadingTests(unittest.TestCase):
    def test_complete_coverage_requires_the_beginning_end_and_no_gap(self):
        self.assertTrue(coverage_complete([(0, 120), (100, 230), (220, 300)], 300))
        for intervals in ([(10, 300)], [(0, 120), (130, 300)], [(0, 299 - 2)]):
            self.assertFalse(coverage_complete(intervals, 300))

    def test_explanation_requires_actual_copy_input_selection_and_paste(self):
        explanation_text(screen(), TOPIC)
        data = screen()
        data['entries'][1]['label'] = 'コピーできます。'
        with self.assertRaises(VerificationError):
            explanation_text(data, TOPIC)

    def test_visible_topic_finishes_without_swiping(self):
        run = SimpleNamespace(ui=Mock(return_value=screen()), screenshot=Mock(), scroll_workspace=Mock())
        result = read_setting_topic(run, TOPIC)
        self.assertEqual(result['height'], 100)
        run.scroll_workspace.assert_not_called()
        run.screenshot.assert_called_once()

    def test_long_topic_collects_overlapping_scroll_intervals(self):
        run = SimpleNamespace(ui=Mock(side_effect=[screen(100, 800), screen(-200, 800), screen(-400, 800)]),
                              screenshot=Mock(), scroll_workspace=Mock())
        result = read_setting_topic(run, TOPIC)
        self.assertEqual(result['height'], 800)
        self.assertEqual(run.scroll_workspace.call_count, 1)

    def test_inertial_overshoot_returns_to_the_first_unread_gap(self):
        run = SimpleNamespace(ui=Mock(side_effect=[screen(246, 838), screen(-448, 838), screen(-200, 838)]),
                              screenshot=Mock(), scroll_workspace=Mock())
        result = read_setting_topic(run, TOPIC)
        self.assertEqual(result['height'], 838)
        self.assertEqual([call.kwargs for call in run.scroll_workspace.call_args_list],
                         [{'up': False, 'reading': True}, {'up': True, 'reading': True}])

    def test_missing_topic_fails_bounded_and_departure_fails_immediately(self):
        missing = {'screen': {'width': 375, 'height': 667}, 'entries': [screen()['entries'][0]]}
        run = SimpleNamespace(ui=Mock(return_value=missing), screenshot=Mock(), scroll_workspace=Mock())
        with self.assertRaisesRegex(VerificationError, 'not reachable'):
            read_setting_topic(run, TOPIC)
        self.assertEqual(run.scroll_workspace.call_count, 29)
        run.ui.return_value = {'entries': []}
        with self.assertRaisesRegex(VerificationError, 'left'):
            read_setting_topic(run, TOPIC)

    def test_horizontal_clipping_cannot_count_as_readable(self):
        data = screen()
        data['entries'][1]['frame']['x'] = -1
        with self.assertRaises(VerificationError):
            reading_intersection(data, TOPIC)


if __name__ == '__main__':
    unittest.main()
