"""Failure handling for the local driver; these tests also run on Ubuntu."""

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import signal
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("ios", Path(__file__).parents[1] / "ios.py")
ios = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ios)


class DeviceSelectionTests(unittest.TestCase):
    def setUp(self):
        self.runtime = {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
                        "version": "26.0.1", "isAvailable": True}
        self.row = {"udid": "selected", "isAvailable": True, "state": "Shutdown"}
        self.devices = {self.runtime["identifier"]: [self.row]}

    def select(self, identifier="selected"):
        return ios.select_device(self.devices, [self.runtime], identifier, "26.0")

    def test_requires_explicit_target_even_with_one_device(self):
        with self.assertRaises(ios.VerificationError):
            self.select(None)

    def test_unknown_target_does_not_fall_back_to_another(self):
        with self.assertRaises(ios.VerificationError):
            self.select("another")

    def test_selected_patch_runtime_is_retained_in_evidence(self):
        self.assertEqual(self.select()["runtime"]["version"], "26.0.1")

    def test_unavailable_runtime_rejected(self):
        self.runtime["isAvailable"] = False
        with self.assertRaises(ios.VerificationError):
            self.select()

    def test_older_os_rejected(self):
        self.runtime["version"] = "18.6"
        with self.assertRaises(ios.VerificationError):
            self.select()


class ResultTests(unittest.TestCase):
    def test_simulator_signing_never_uses_a_developer_identity(self):
        self.assertEqual(ios.simulator_signing_arguments({}), ["CODE_SIGNING_ALLOWED=NO"])
        self.assertEqual(ios.simulator_signing_arguments({"simulator_signing": "ad-hoc"}),
                         ["CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "DEVELOPMENT_TEAM="])
        with self.assertRaises(ios.VerificationError):
            ios.simulator_signing_arguments({"simulator_signing": "distribution"})

    def test_executed_passing_tests_accepted(self):
        ios.validate_summary({"result": "Passed", "passedTests": 2, "failedTests": 0, "totalTestCount": 2})

    def test_zero_failed_skipped_or_malformed_results_are_not_success(self):
        for summary in [
            {},
            {"result": "Passed", "passedTests": 0, "failedTests": 0, "totalTestCount": 0},
            {"result": "Skipped", "passedTests": 0, "failedTests": 0, "totalTestCount": 2},
            {"result": "Failed", "passedTests": 1, "failedTests": 1, "totalTestCount": 2},
        ]:
            with self.subTest(summary=summary), self.assertRaises(ios.VerificationError):
                ios.validate_summary(summary)

    def test_ui_assertion_requires_unique_matching_element_and_exact_text(self):
        expected = {"uniqueId": "fixture.output", "label": "反映した内容", "value": "日本語\n code "}
        ios.expect_text({"entries": [expected]}, "fixture.output", "日本語\n code ")
        for entries in [[], [expected, expected], [{**expected, "value": "日本語 code"}]]:
            with self.subTest(entries=entries), self.assertRaises(ios.VerificationError):
                ios.expect_text({"entries": entries}, "fixture.output", "日本語\n code ")


class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.run = ios.Run.__new__(ios.Run)
        self.run.path = Path(self.temp.name)
        self.run.manifest = {"commands": []}
        self.run.args = Mock(device="explicit-udid")

    def test_missing_project_config_leaves_a_failed_manifest(self):
        with patch.object(ios, "ARTIFACTS", self.run.path), patch.object(ios.platform, "system", return_value="Darwin"):
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                code = ios.main(["doctor", "--project-config", str(self.run.path / "missing.json")])
        self.assertEqual(code, 1)
        manifests = list(self.run.path.glob("*/manifest.json"))
        self.assertEqual(len(manifests), 1)
        self.assertEqual(json.loads(manifests[0].read_text())["status"], "failed")

    def test_failed_command_preserves_logs_and_nonzero_exit(self):
        with redirect_stdout(io.StringIO()), self.assertRaises(ios.VerificationError):
            self.run.command([sys.executable, "-c", "print('failure evidence'); raise SystemExit(23)"], "failure")
        self.assertEqual(self.run.manifest["commands"][0]["exit_code"], 23)
        self.assertIn("failure evidence", (self.run.path / "failure.log").read_text())

    def test_recording_is_finalized_when_ui_action_fails(self):
        process = Mock()
        process.stderr = io.StringIO("Recording started\n")
        process.poll.return_value = None
        process.wait.return_value = 0
        with patch.object(ios.subprocess, "Popen", return_value=process), redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ios.VerificationError, "UI action failed"):
                with self.run.recording():
                    raise ios.VerificationError("UI action failed")
        process.send_signal.assert_called_once_with(signal.SIGINT)
        process.wait.assert_called_once_with(timeout=30)

    def test_recorder_success_without_media_is_rejected(self):
        process = Mock()
        process.stderr = io.StringIO("Recording started\n")
        process.poll.return_value = None
        process.wait.return_value = 0
        with patch.object(ios.subprocess, "Popen", return_value=process), redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ios.VerificationError, "Recording did not complete"):
                with self.run.recording():
                    pass


if __name__ == "__main__":
    unittest.main()
