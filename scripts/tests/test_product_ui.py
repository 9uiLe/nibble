import copy
from pathlib import Path
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import Mock

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
            ]}
        run = object.__new__(ProductRun)
        run.args = SimpleNamespace(device='selected')
        run.wait_ui = Mock(side_effect=[screen(140), screen(368), screen(368)])
        run.ui = Mock(return_value=screen(200))
        run.command = Mock()
        self.assertEqual(run._focus_input('editor.body'), (187.5, 220))
        self.assertEqual([call.args[0][1] for call in run.command.call_args_list], ['tap', 'swipe'])

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
