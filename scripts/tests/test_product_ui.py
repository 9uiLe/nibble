import copy
from pathlib import Path
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
from ios import VerificationError
from product_ui import ProductRun, editor_mode_target, editor_viewport, identifiers, input_point


class ProductNavigationTests(unittest.TestCase):
    def test_editor_modes_use_native_roles_and_reject_text_or_ambiguity(self):
        group = {'uniqueId': 'editor.mode', 'role': 'TabGroup'}
        self.assertEqual(editor_mode_target({'entries': [group]}, 'プレビュー'), (group, .75))
        radio = {'label': 'プレビュー', 'role': 'RadioButton'}
        self.assertEqual(editor_mode_target({'entries': [radio]}, 'プレビュー'), (radio, .5))
        with self.assertRaises(VerificationError):
            editor_mode_target({'entries': [{'label': 'プレビュー', 'role': 'Text'}]}, 'プレビュー')
        with self.assertRaises(VerificationError):
            editor_mode_target({'entries': [radio, copy.deepcopy(radio)]}, 'プレビュー')

    def test_input_point_uses_only_the_visible_intersection(self):
        data = {'screen': {'height': 667}, 'entries': [
            {'uniqueId': 'editor.body', 'frame': {'x': 24, 'y': 300, 'width': 327, 'height': 180}},
            {'uniqueId': 'editor.keyboard.help', 'frame': {'y': 355, 'height': 44}},
        ]}
        self.assertEqual(input_point(data, 'editor.body'), (187.5, 327.5))
        data['entries'][0]['frame']['y'] = 368
        with self.assertRaises(VerificationError):
            input_point(data, 'editor.body')

    def test_focus_observes_and_reveals_the_field_after_keyboard_layout(self):
        def screen(y):
            return {'screen': {'width': 375, 'height': 667}, 'entries': [
                {'uniqueId': 'editor.body', 'frame': {'x': 24, 'y': y, 'width': 327, 'height': 40}},
                {'uniqueId': 'editor.keyboard.help', 'frame': {'y': 355, 'height': 44}},
                {'uniqueId': 'editor.keyboard.dismiss'},
            ]}
        run = object.__new__(ProductRun)
        run.args = SimpleNamespace(device='selected')
        run.ui = Mock(side_effect=[screen(140), screen(140), screen(368), screen(368), screen(368),
                                   screen(200), screen(200)])
        run.command = Mock()
        with patch('ios.time.sleep'):
            self.assertEqual(run._focus_input('editor.body'), (187.5, 220))
        self.assertEqual([call.args[0][1] for call in run.command.call_args_list], ['tap', 'swipe'])

    def test_focus_waits_for_interactive_keyboard_dismissal_before_using_the_title_point(self):
        def screen(y, keyboard):
            entries = [
                {'uniqueId': 'editor.title', 'frame': {'x': 20, 'y': y, 'width': 362, 'height': 34}},
                {'uniqueId': 'editor.exitGuidance', 'frame': {'y': 140, 'height': 18}},
                {'uniqueId': 'editor.keyboard.help' if keyboard else 'editor.help',
                 'frame': {'y': 501 if keyboard else 803, 'height': 18}},
            ]
            if keyboard:
                entries.append({'uniqueId': 'editor.keyboard.dismiss'})
            return {'screen': {'width': 402, 'height': 874}, 'entries': entries}

        run = object.__new__(ProductRun)
        run.args = SimpleNamespace(device='selected')
        run.ui = Mock(side_effect=[screen(584, True), screen(584, True), screen(423, True),
                                   screen(584, False), screen(584, False), screen(448, True),
                                   screen(448, True), screen(448, True)])
        run.command = Mock()
        with patch('ios.time.sleep'):
            self.assertEqual(run._focus_input('editor.title'), (201, 465))
        self.assertEqual([call.args[0][1] for call in run.command.call_args_list], ['swipe', 'tap'])
        tap = run.command.call_args_list[1].args[0]
        self.assertEqual(float(tap[tap.index('-y') + 1]), 601)

    def test_reveal_waits_for_changes_to_either_the_frame_or_the_viewport(self):
        def screen(y, bottom):
            return {'screen': {'width': 375, 'height': 667}, 'entries': [
                {'uniqueId': 'editor.body', 'frame': {'x': 24, 'y': y, 'width': 327, 'height': 180}},
                {'uniqueId': 'editor.keyboard.help', 'frame': {'y': bottom, 'height': 44}},
            ]}

        for changed in [screen(280, 355), screen(300, 400)]:
            with self.subTest(changed=changed):
                run = object.__new__(ProductRun)
                run.ui = Mock(side_effect=[screen(300, 355), changed, copy.deepcopy(changed)])
                run.command = Mock()
                with patch('ios.time.sleep'):
                    self.assertEqual(run._reveal_input('editor.body'), changed)
                self.assertEqual(run.ui.call_count, 3)
                run.command.assert_not_called()

    def test_unsettled_input_fails_after_bounded_observations_without_tapping(self):
        run = object.__new__(ProductRun)
        run.ui = Mock(side_effect=[{'screen': {'width': 375, 'height': 667}, 'entries': [
            {'uniqueId': 'editor.title', 'frame': {'x': 20, 'y': 200 + attempt, 'width': 335, 'height': 34}},
        ]} for attempt in range(20)])
        run.command = Mock()
        with patch('ios.time.sleep'), self.assertRaisesRegex(VerificationError, 'editor.title-present'):
            run._focus_input('editor.title')
        self.assertEqual(run.ui.call_count, 20)
        run.command.assert_not_called()

    def test_editor_viewport_excludes_the_navigation_bar_and_keyboard_accessory(self):
        data = {'screen': {'height': 667}, 'entries': [
            {'role': 'Group', 'uniqueId': '新規作成', 'frame': {'y': 46, 'height': 54}},
            {'uniqueId': 'editor.title', 'frame': {'y': 65, 'height': 20}},
            {'uniqueId': 'editor.keyboard.help', 'frame': {'y': 355, 'height': 44}},
        ]}
        self.assertEqual(editor_viewport(data), (100, 355))
        data['entries'].append({'role': 'StaticText', 'label': '閉じると下書きに残り、保存すると使えます。',
                                'frame': {'y': 110, 'height': 16}})
        self.assertEqual(editor_viewport(data), (136, 355))

    def test_workspace_routes_back_and_clears_only_when_requested(self):
        root = {'entries': [{'uniqueId': 'navigation.settings'}, {'uniqueId': 'search.clear'}]}
        run = object.__new__(ProductRun)
        run.ui = Mock(return_value={'entries': [{'uniqueId': 'BackButton'}]})
        run.tap = Mock()
        run.wait_ui = Mock(return_value=root)
        run.workspace(clear_query=True)
        self.assertEqual([call.args[0] for call in run.tap.call_args_list], ['BackButton', 'search.clear'])
        run.tap.reset_mock()
        run.ui.return_value = root
        run.workspace()
        run.tap.assert_not_called()

    def test_missing_workspace_route_fails_without_tapping_an_invented_target(self):
        run = object.__new__(ProductRun)
        run.ui = Mock(return_value={'entries': []})
        run.tap = Mock()
        with self.assertRaises(VerificationError):
            run.workspace()
        run.tap.assert_not_called()

    def test_settings_uses_the_workspace_control_and_waits_for_destination(self):
        run = object.__new__(ProductRun)
        run.workspace = Mock(return_value={'entries': [{'uniqueId': 'navigation.settings'}]})
        run.tap = Mock()
        run.wait_ui = Mock(return_value={'entries': [{'uniqueId': 'settings.about'}]})
        run.open_settings()
        run.workspace.assert_called_once_with()
        run.tap.assert_called_once_with('navigation.settings')
        self.assertEqual(run.wait_ui.call_args.args[0], 'settings-route')
