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
