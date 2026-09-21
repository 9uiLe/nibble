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
