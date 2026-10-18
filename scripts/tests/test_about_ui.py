"""Fault injection restores the dedicated installation even if observation fails."""
import hashlib
import importlib.util
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
SPEC = importlib.util.spec_from_file_location("about_ui", Path(__file__).parents[1] / "check_about_ui.py")
about_ui = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(about_ui)


class MotionNavigationTests(unittest.TestCase):
    def test_empty_settings_observation_with_zero_screen_is_retried(self):
        empty = {'appPackage': 'com.apple.Preferences', 'screen': {'width': 0, 'height': 0},
                 'entries': [{'label': 'status bar'}]}
        root = {'appPackage': 'com.apple.Preferences',
                'entries': [{'uniqueId': 'com.apple.settings.accessibility'}]}
        destination = {'appPackage': 'com.apple.Preferences',
                       'entries': [{'uniqueId': 'REDUCE_MOTION', 'value': '0'}]}
        run = SimpleNamespace(args=SimpleNamespace(device='dedicated'), manifest={},
                              ui=Mock(side_effect=[empty, root, destination]),
                              tap=Mock(), command=Mock(), save=Mock())
        with patch.object(about_ui.time, 'sleep'):
            self.assertFalse(about_ui.AboutCheck(run).motion())
        self.assertEqual([call.args[0] for call in run.tap.call_args_list],
                         ['com.apple.settings.accessibility'])
        self.assertEqual(run.command.call_count, 1)

    def test_transition_prefers_motion_and_does_not_repeat_the_departing_row(self):
        def screen(*identifiers):
            return {'appPackage': 'com.apple.Preferences',
                    'entries': [{'uniqueId': value} for value in identifiers]}
        root = screen('com.apple.settings.accessibility')
        mixed = screen('com.apple.settings.accessibility', 'MOTION_TITLE', 'BackButton')
        destination = {'appPackage': 'com.apple.Preferences',
                       'entries': [{'uniqueId': 'REDUCE_MOTION', 'value': '0'}]}
        run = SimpleNamespace(args=SimpleNamespace(device='dedicated'), manifest={},
                              ui=Mock(side_effect=[root, root, mixed, mixed, destination]),
                              tap=Mock(), command=Mock(), save=Mock())
        with patch.object(about_ui.time, 'sleep'):
            self.assertFalse(about_ui.AboutCheck(run).motion())
        self.assertEqual([call.args[0] for call in run.tap.call_args_list],
                         ['com.apple.settings.accessibility', 'MOTION_TITLE'])

    def test_navigates_observed_settings_controls_without_changing_motion(self):
        screens = [
            {'entries': [{'uniqueId': identifier}], 'appPackage': 'com.apple.Preferences'}
            for identifier in ['BackButton', 'com.apple.settings.accessibility', 'MOTION_TITLE']
        ]
        screens.append({'entries': [{'uniqueId': 'REDUCE_MOTION', 'value': '1'}],
                        'appPackage': 'com.apple.Preferences'})
        run = SimpleNamespace(args=SimpleNamespace(device='dedicated'), manifest={},
                              ui=Mock(side_effect=screens), tap=Mock(), command=Mock(), save=Mock())
        with patch.object(about_ui.time, 'sleep'):
            self.assertTrue(about_ui.AboutCheck(run).motion())
        self.assertEqual([call.args[0] for call in run.tap.call_args_list],
                         ['BackButton', 'com.apple.settings.accessibility', 'MOTION_TITLE'])
        self.assertEqual(run.command.call_count, 1)
        self.assertEqual(run.manifest['motion_observations'],
                         [{'before': True, 'requested': None, 'observed': True}])

    def test_does_not_tap_stale_controls_from_another_app_and_fails_bounded(self):
        run = SimpleNamespace(args=SimpleNamespace(device='dedicated'), manifest={},
                              ui=Mock(return_value={'appPackage': 'nibble.9uiLe.com',
                                  'entries': [{'uniqueId': 'BackButton'}]}),
                              tap=Mock(), command=Mock(), save=Mock())
        with patch.object(about_ui.time, 'sleep'), self.assertRaises(about_ui.VerificationError):
            about_ui.AboutCheck(run).motion()
        run.tap.assert_not_called()
        self.assertLessEqual(run.ui.call_count, 24)
        self.assertNotIn('motion_observations', run.manifest)


class ReadingBoundaryTests(unittest.TestCase):
    def flow(self, identifier, screens, story='about'):
        run = SimpleNamespace(args=SimpleNamespace(device='dedicated'),
                              manifest={'device': {'deviceTypeIdentifier': identifier}},
                              ui=Mock(side_effect=screens), screenshot=Mock())
        flow = about_ui.AboutCheck(run, story)
        flow.scroll = Mock()
        flow.option = Mock()
        flow.check_illustration = Mock()
        return flow

    def test_physical_home_device_can_read_the_observed_final_link_above_its_actual_bottom(self):
        # SE3 run light-scroll-27..29: 375x667, link y625..643, 24pt remaining.
        data = {'screen': {'width': 375, 'height': 667}, 'orientation': 'portrait', 'entries': [
            {'uniqueId': 'about.privacyPolicy', 'frame': {'x': 24, 'y': 625, 'width': 206, 'height': 18}},
        ]}
        flow = self.flow('com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation', [data])
        flow.read_page('light')
        self.assertTrue(flow.observations['light']['final_content_reachable'])
        self.assertEqual(flow.observations['light']['viewport']['bottom_exclusion'], 0)
        self.assertEqual(flow.observations['light']['final_content_frame'], data['entries'][0]['frame'])
        flow.scroll.assert_not_called()
        flow.run.screenshot.assert_any_call('light-bottom')

    def test_notched_device_must_scroll_content_clear_of_the_indicator_and_reading_margin(self):
        def screen(y):
            return {'screen': {'width': 402, 'height': 874}, 'orientation': 'portrait', 'entries': [
                {'uniqueId': 'keyboard.guide.limits', 'frame': {'x': 24, 'y': y, 'width': 350, 'height': 18}},
            ]}

        covered, readable = screen(830), screen(798)
        flow = self.flow('com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro', [covered, readable], 'keyboard')
        flow.read_page('light')
        self.assertEqual(flow.observations['light']['swipes'], 1)
        self.assertEqual(flow.observations['light']['viewport']['bottom_exclusion'], 34)
        self.assertEqual(flow.observations['light']['final_content_frame'], readable['entries'][0]['frame'])
        self.assertEqual(flow.scroll.call_args_list[0].args, (covered,))
        self.assertEqual(flow.scroll.call_args_list[1].kwargs, {'up': True})

    def test_content_left_under_the_home_indicator_fails_after_the_bounded_scroll_attempts(self):
        data = {'screen': {'width': 402, 'height': 874}, 'orientation': 'portrait', 'entries': [
            {'uniqueId': 'about.privacyPolicy', 'frame': {'x': 24, 'y': 830, 'width': 206, 'height': 18}},
        ]}
        flow = self.flow('com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro', [data] * 31)
        with self.assertRaisesRegex(about_ui.VerificationError, 'not reachable'):
            flow.read_page('light')
        self.assertEqual(flow.scroll.call_count, 30)
        self.assertNotIn('light', flow.observations)
        self.assertNotIn('light-bottom', [call.args[0] for call in flow.run.screenshot.call_args_list])

    def test_unobserved_device_or_geometry_cannot_claim_a_readable_viewport(self):
        for identifier, orientation, width, height in [
            ('com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max', 'portrait', 440, 956),
            ('com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro', 'landscape', 874, 402),
            ('com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation', 'portrait', 375, 800),
        ]:
            with self.subTest(identifier=identifier, orientation=orientation, width=width, height=height):
                data = {'screen': {'width': width, 'height': height}, 'orientation': orientation, 'entries': [
                    {'uniqueId': 'about.privacyPolicy', 'frame': {'x': 24, 'y': 400, 'width': 206, 'height': 18}},
                ]}
                flow = self.flow(identifier, [data])
                with self.assertRaisesRegex(about_ui.VerificationError, 'viewport'):
                    flow.read_page('light')
                flow.scroll.assert_not_called()
                self.assertFalse(flow.observations)


class FaultRetryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "app/Nibble/Animations/about-story.riv"
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(b"valid fixture")
        self.installed = self.root / "installed"
        self.installed.mkdir()
        self.asset = self.installed / self.source.name
        self.asset.write_bytes(self.source.read_bytes())
        self.run = SimpleNamespace(args=SimpleNamespace(device="dedicated"), config={"bundle_id": "fixture"},
                                   path=self.root, manifest={}, save=Mock(),
                                   command=Mock(return_value=str(self.installed)))
        self.flow = about_ui.AboutCheck(self.run)
        self.flow.option = Mock()
        self.flow.open_about = Mock(side_effect=RuntimeError("observation failed"))
        self.root_patch = patch.object(about_ui, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def test_failure_during_observation_restores_original_asset(self):
        with self.assertRaisesRegex(RuntimeError, "observation failed"):
            self.flow.failure_retry()
        self.assertEqual(self.asset.read_bytes(), self.source.read_bytes())
        record = self.run.manifest["fault_injection"]
        self.assertEqual(record["events"], ["decode_failure_injected", "asset_restored"])
        self.assertEqual(record["restored_sha256"], hashlib.sha256(self.source.read_bytes()).hexdigest())

    def test_unknown_installation_is_never_modified(self):
        self.asset.write_bytes(b"another build")
        with self.assertRaisesRegex(about_ui.VerificationError, "does not match"):
            self.flow.failure_retry()
        self.assertEqual(self.asset.read_bytes(), b"another build")
        self.flow.open_about.assert_not_called()
        self.assertNotIn("fault_injection", self.run.manifest)
