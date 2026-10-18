"""Result notices avoid search controls while retaining their bottom placement."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
from check_library_ui import restoration_notice_geometry
from ios import VerificationError


class RestorationNoticeGeometryTests(unittest.TestCase):
    def setUp(self):
        # library04 trash-restored-0.json, iPhone 17 Pro, iOS 26.5.
        self.data = {"screen": {"width": 402, "height": 874}, "entries": [
            {"uniqueId": "library.notice", "frame": {"x": 16, "y": 776, "width": 370, "height": 56}},
            {"uniqueId": "search.field", "frame": {"x": 62, "y": 129, "width": 212, "height": 22}},
        ]}

    def test_observed_notice_below_search_passes(self):
        result = restoration_notice_geometry(self.data)
        self.assertEqual(result["notice"]["y"] - result["search"]["y"] - result["search"]["height"], 625)
        self.assertIn("not measured", result["bottom_guard_method"])

    def test_eight_point_gap_is_accepted_in_either_order(self):
        for search_y in (746, 840):
            with self.subTest(search_y=search_y):
                self.data["entries"][1]["frame"]["y"] = search_y
                restoration_notice_geometry(self.data)

    def test_overlap_and_less_than_eight_point_gap_fail_in_either_order(self):
        for search_y in (747, 775, 780, 831, 839):
            with self.subTest(search_y=search_y):
                self.data["entries"][1]["frame"]["y"] = search_y
                with self.assertRaisesRegex(VerificationError, "search controls"):
                    restoration_notice_geometry(self.data)

    def test_bottom_area_width_and_screen_containment_remain_required(self):
        for change in ({"y": 500}, {"y": 811}, {"width": 331}, {"x": -1},
                       {"x": 33}, {"height": 0}, {"width": 0}):
            with self.subTest(change=change):
                data = deepcopy(self.data)
                data["entries"][0]["frame"].update(change)
                with self.assertRaises(VerificationError):
                    restoration_notice_geometry(data)


if __name__ == "__main__":
    unittest.main()
