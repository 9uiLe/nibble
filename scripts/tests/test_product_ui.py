import copy
from pathlib import Path
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parents[1]))
from ios import VerificationError
from product_ui import ProductRun, editor_viewport, identifiers, native_tabs


class NativeTabTests(unittest.TestCase):
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
