from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
from check_notice_ui import trash_back_frame
from ios import VerificationError


class TrashNavigationTests(unittest.TestCase):
    def test_back_frame_accepts_duplicate_ax_entries_at_the_same_visible_position(self):
        visible = {'uniqueId': 'BackButton', 'label': '', 'aliases': {'at': 5},
                   'frame': {'x': 16, 'y': 62, 'width': 44, 'height': 44}}
        hidden = {'uniqueId': 'BackButton', 'label': '設定', 'aliases': {'at': 20},
                  'frame': {'x': -120, 'y': 62, 'width': 44, 'height': 44}}
        data = {'screen': {'width': 402, 'height': 874}, 'entries': [hidden, visible]}
        self.assertEqual(trash_back_frame(data), visible['frame'])
        data['entries'].append({**visible, 'label': '設定', 'aliases': {'at': 30}})
        self.assertEqual(trash_back_frame(data), visible['frame'])
        data['entries'][-1]['frame'] = {**visible['frame'], 'y': 200}
        with self.assertRaises(VerificationError):
            trash_back_frame(data)


if __name__ == '__main__':
    unittest.main()
