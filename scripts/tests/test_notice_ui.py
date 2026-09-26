from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
from check_notice_ui import trash_back_button
from ios import VerificationError


class TrashNavigationTests(unittest.TestCase):
    def test_unlabelled_visible_back_button_is_selected_over_hidden_settings_button(self):
        visible = {'uniqueId': 'BackButton', 'label': '', 'aliases': {'at': 5},
                   'frame': {'x': 16, 'y': 62, 'width': 44, 'height': 44}}
        hidden = {'uniqueId': 'BackButton', 'label': '設定', 'aliases': {'at': 20},
                  'frame': {'x': -120, 'y': 62, 'width': 44, 'height': 44}}
        data = {'screen': {'width': 402, 'height': 874}, 'entries': [hidden, visible]}
        self.assertIs(trash_back_button(data), visible)
        data['entries'].append({**visible, 'aliases': {'at': 30}})
        with self.assertRaises(VerificationError):
            trash_back_button(data)


if __name__ == '__main__':
    unittest.main()
