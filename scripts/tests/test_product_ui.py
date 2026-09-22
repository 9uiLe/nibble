import copy
from pathlib import Path
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parents[1]))
from ios import VerificationError
from product_ui import ProductRun, editor_mode_target, editor_viewport, identifiers, input_point, native_tabs


class NativeTabTests(unittest.TestCase):
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

    def test_native_menu_failure_is_not_reclassified_as_success(self):
        run = object.__new__(ProductRun)
        run.wait_ui = Mock(side_effect=VerificationError('missing menu'))
        run.command = Mock()
        with self.assertRaises(VerificationError):
            run._menu_item(('すべてを選択', 'Select All'), allow_next=True)
        run.command.assert_not_called()

    def test_editor_viewport_excludes_the_navigation_bar_and_keyboard_accessory(self):
        data = {'screen': {'height': 667}, 'entries': [
            {'role': 'Group', 'uniqueId': '新規作成', 'frame': {'y': 46, 'height': 54}},
            {'uniqueId': 'editor.title', 'frame': {'y': 65, 'height': 20}},
            {'uniqueId': 'editor.keyboard.help', 'frame': {'y': 355, 'height': 44}},
        ]}
        self.assertEqual(editor_viewport(data), (100, 355))

    def screen(self):
        return {'appPackage': 'nibble.9uiLe.com', 'entries': [
            {'role': 'Heading', 'label': '一覧'},
            {'role': 'RadioButton', 'label': '一覧', 'states': ['selected'],
             'frame': {'x': 20, 'y': 600, 'width': 100, 'height': 54}},
            {'role': 'RadioButton', 'label': '検索', 'frame': {'x': 120, 'y': 600, 'width': 100, 'height': 54}},
        ]}

    def test_missing_native_ids_resolve_without_rewriting_raw_observation(self):
        data = self.screen()
        original = copy.deepcopy(data)
        self.assertEqual(set(native_tabs(data)), {'navigation.tab.library', 'navigation.tab.search'})
        self.assertIn('navigation.tab.search', identifiers(data))
        self.assertNotIn('navigation.tab.settings', identifiers(data))
        run = object.__new__(ProductRun)
        run.args = SimpleNamespace(device='selected')
        run.ui = Mock(return_value=data)
        run.command = Mock()
        run.tap('navigation.tab.search')
        run.command.assert_called_once_with(['sim-use', 'tap', '-x', '170.0', '-y', '627.0', '--device', 'selected'])
        self.assertEqual(data, original)

    def test_hidden_ambiguous_and_other_app_tabs_are_not_actionable(self):
        data = self.screen()
        data['appPackage'] = 'com.apple.Preferences'
        self.assertEqual(native_tabs(data), {})
        data = self.screen()
        data['entries'].append(copy.deepcopy(data['entries'][1]))
        with self.assertRaises(VerificationError):
            native_tabs(data)
        run = object.__new__(ProductRun)
        run.ui = Mock(return_value=self.screen())
        run.command = Mock()
        with self.assertRaises(VerificationError):
            run.tap('navigation.tab.settings')
        run.command.assert_not_called()
