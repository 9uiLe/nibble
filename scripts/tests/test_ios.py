"""Failure handling for the local driver; these tests also run on Ubuntu."""

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
from script_ui import Reporter

spec = importlib.util.spec_from_file_location("ios", Path(__file__).parents[1] / "ios.py")
ios = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ios)


class DeviceSelectionTests(unittest.TestCase):
    def setUp(self):
        self.runtime = {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                        "version": "26.5", "buildversion": "23F77", "isAvailable": True}
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

    def test_selected_runtime_and_build_are_retained_in_evidence(self):
        self.assertEqual(self.select()["runtime"]["version"], "26.5")
        self.assertEqual(self.select()["runtime"]["buildversion"], "23F77")

    def test_every_other_execution_version_is_rejected(self):
        for version in ['26.4', '26.5.1', '27.0']:
            with self.subTest(version=version), self.assertRaises(ios.VerificationError):
                self.runtime['version'] = version
                self.select()

    def test_unavailable_runtime_rejected(self):
        self.runtime["isAvailable"] = False
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
        display = patch.object(ios, "ui")
        display.start()
        self.addCleanup(display.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.run = ios.Run.__new__(ios.Run)
        self.run.path = Path(self.temp.name)
        self.run.manifest = {"commands": []}
        self.run.args = Mock(device="explicit-udid")

    def test_testability_override_is_limited_to_test_actions(self):
        self.run.config = {"project": "app/Nibble.xcodeproj", "scheme": "Nibble"}
        self.run.args.configuration = "Release"
        for test in [False, True]:
            with self.subTest(test=test), patch.object(self.run, "boot"), patch.object(self.run, "command") as command, patch.object(ios, "validate_summary"):
                self.run.build(test=test)
                arguments = command.call_args_list[0].args[0]
                self.assertEqual("ENABLE_TESTABILITY=YES" in arguments, test)
                self.assertEqual(arguments[-1], "test" if test else "build")

    def test_launch_waits_for_native_target_process(self):
        self.run.config = {"bundle_id": "nibble.9uiLe.com"}
        states = ["PID Status Label\n- 0 UIKitApplication:another.app[x]",
                  "42 0 UIKitApplication:nibble.9uiLe.com[x][rb-legacy]",
                  "Wed Sep 16 10:00:00 2026 /device/Nibble.app/Nibble\n"]
        with patch.object(self.run, "command", side_effect=states) as command, patch.object(ios.time, "sleep"):
            self.run.wait_for_launch()
        self.assertEqual(self.run.launched_pid, 42)
        self.assertEqual(self.run.launched_identity, states[-1].strip())
        self.assertEqual(self.run.manifest["process_monitor"]["pid"], 42)

    def test_missing_process_is_bounded_and_never_certified(self):
        self.run.config = {"bundle_id": "nibble.9uiLe.com"}
        attempts = iter(["- 9 UIKitApplication:nibble.9uiLe.com[x]"] * 20)
        def absent(*args, **kwargs):
            # A missing finite retry bound fails promptly instead of hanging this suite.
            try:
                return next(attempts)
            except StopIteration:
                self.fail("Launch polling exceeded the bounded failure budget")
        with patch.object(self.run, "command", side_effect=absent), patch.object(ios.time, "sleep"):
            with self.assertRaises(ios.VerificationError):
                self.run.wait_for_launch()
        self.assertNotIn("process_monitor", self.run.manifest)

    def test_native_lookup_matches_only_the_exact_live_bundle(self):
        self.run.config = {"bundle_id": "nibble.9uiLe.com"}
        for state in ["- 9 UIKitApplication:nibble.9uiLe.com[x]", "43 0 UIKitApplication:nibble.9uiLe.com[x]",
                      "42 0 UIKitApplication:nibble.9uiLe.com.share[x]"]:
            with self.subTest(state=state), patch.object(self.run, "command", return_value=state):
                self.assertEqual(self.run.process_id(), 43 if state.startswith("43 ") else None)
        with patch.object(self.run, "command", return_value="42 0 UIKitApplication:nibble.9uiLe.com[x]\n43 0 UIKitApplication:nibble.9uiLe.com[y]"):
            with self.assertRaises(ios.VerificationError):
                self.run.process_id()
        with patch.object(self.run, "command", return_value="42 0 UIKitApplication:nibble.9uiLe.com[x]"):
            self.assertEqual(self.run.process_id(), 42)

    def test_host_monitor_rejects_exit_and_reused_pid(self):
        self.run.launched_pid = 42
        self.run.launched_identity = "Wed Sep 16 10:00:00 2026 /device/Nibble.app/Nibble"
        for identity in ["", "Wed Sep 16 10:00:01 2026 /device/Nibble.app/Nibble",
                         "Wed Sep 16 10:00:00 2026 /device/Other.app/Other"]:
            with self.subTest(identity=identity), patch.object(self.run, "command", return_value=identity):
                with self.assertRaises(ios.VerificationError):
                    self.run.check_process()
        with patch.object(self.run, "command", side_effect=ios.VerificationError("Process exited")):
            with self.assertRaises(ios.VerificationError):
                self.run.check_process()
        with patch.object(self.run, "command", return_value=self.run.launched_identity + "\n") as command:
            self.run.check_process()
        command.assert_called_once_with(["/bin/ps", "-p", "42", "-o", "lstart=,comm="], display=False)

    def test_native_probe_command_failure_is_not_ignored(self):
        self.run.config = {"bundle_id": "nibble.9uiLe.com"}
        with patch.object(self.run, "command", side_effect=ios.VerificationError("Unavailable")) as command:
            with self.assertRaises(ios.VerificationError):
                self.run.wait_for_launch()
        self.assertEqual(command.call_count, 1)

    def test_sim_use_command_checks_pid_before_and_after_and_uses_local_ax(self):
        self.run.launched_pid = 42
        with patch.object(self.run, "check_process") as monitor, patch.object(ios.subprocess, "run", return_value=Mock(returncode=0)) as process, redirect_stdout(io.StringIO()):
            self.run.command(["sim-use", "tap", "@17"])
        self.assertEqual(monitor.call_count, 2)
        environment = process.call_args.kwargs["env"]
        self.assertEqual(environment["SIM_USE_NO_DAEMON"], "1")
        self.assertEqual(environment["SIM_USE_NO_CRASH_DETECT"], "1")

    def test_nested_monitor_commands_retain_distinct_logs(self):
        self.run.launched_pid = 42
        def monitor():
            self.run.command([sys.executable, '-c', 'pass'])
        with patch.object(self.run, 'check_process', side_effect=monitor), \
                patch.object(ios.subprocess, 'run', return_value=Mock(returncode=0)):
            self.run.command(['sim-use', 'tap', '@17'])
        commands = self.run.manifest['commands']
        self.assertEqual(sum(event['argv'][0] == 'sim-use' for event in commands), 1)
        logs = [event['stdout'] for event in commands]
        self.assertEqual(len(logs), len(set(logs)))

    def test_repeated_observation_names_preserve_each_result(self):
        for value in ['first', 'second']:
            self.run.command([sys.executable, '-c', f'print({value!r})'], 'poll')
            with patch.object(self.run, 'command', return_value=json.dumps(
                    {'ok': True, 'data': {'entries': [{'value': value}]}})):
                self.run.ui('poll')
        commands = self.run.manifest['commands']
        self.assertEqual([(self.run.path / event['stdout']).read_text().strip()
                          for event in commands], ['first', 'second'])
        observations = sorted(self.run.path.glob('poll*.json'))
        self.assertEqual(len(observations), 2)
        self.assertEqual({json.loads(path.read_text())['data']['entries'][0]['value']
                          for path in observations}, {'first', 'second'})

    def test_empty_ui_is_only_allowed_for_explicit_transition_polling(self):
        payload = {"ok": True, "data": {"entries": []}}
        with patch.object(self.run, "command", return_value=json.dumps(payload)):
            with self.assertRaises(ios.VerificationError):
                self.run.ui()
            self.assertEqual(self.run.ui(allow_empty=True), {"entries": []})
        payload["ok"] = False
        with patch.object(self.run, "command", return_value=json.dumps(payload)):
            with self.assertRaises(ios.VerificationError):
                self.run.ui(allow_empty=True)
        with patch.object(self.run, "command", side_effect=ios.VerificationError("Process exited")):
            with self.assertRaises(ios.VerificationError):
                self.run.ui(allow_empty=True)

    def test_explicit_ui_command_returns_snapshot_json_without_progress_on_stdout(self):
        run = MagicMock()
        run.device = {'state': 'Booted'}
        run.ui.return_value = {'entries': [{'uniqueId': 'fixture.input', 'value': '日本語'}]}
        with patch.object(ios, 'Run', return_value=run), redirect_stdout(io.StringIO()) as out:
            code = ios.main(['ui', '--device', 'D099A849-386F-4EAE-AE12-02D8DC623AF2'])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out.getvalue()), run.ui.return_value)
        run.finish.assert_called_once_with()

    def test_missing_project_config_leaves_a_failed_manifest(self):
        with patch.object(ios, "ARTIFACTS", self.run.path), patch.object(ios.platform, "system", return_value="Darwin"):
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                code = ios.main(["doctor", "--project-config", str(self.run.path / "missing.json")])
        self.assertEqual(code, 1)
        manifests = list(self.run.path.glob("*/manifest.json"))
        self.assertEqual(len(manifests), 1)
        self.assertEqual(json.loads(manifests[0].read_text())["status"], "failed")

    def test_malformed_project_config_fails_before_running_apple_tools(self):
        config = self.run.path / 'invalid.json'
        config.write_text('{"scheme": "Nibble"}')
        with patch.object(ios, 'ARTIFACTS', self.run.path), \
                patch.object(ios.platform, 'system', return_value='Darwin'), \
                patch.object(ios.subprocess, 'run') as command, \
                redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(ios.main(['doctor', '--project-config', str(config)]), 1)
        command.assert_not_called()
        manifest = json.loads(next(self.run.path.glob('*/manifest.json')).read_text())
        self.assertEqual(manifest['status'], 'failed')

    def test_product_is_default_and_fixture_smoke_selects_its_own_target(self):
        for action, expected in [('build', 'app/project.json'),
                                 ('fixture-smoke', 'validation/project.json')]:
            run = MagicMock()
            with self.subTest(action=action), patch.object(ios, 'Run', return_value=run) as factory, \
                    redirect_stdout(io.StringIO()):
                self.assertEqual(ios.main([action, '--device', 'D099A849-386F-4EAE-AE12-02D8DC623AF2']), 0)
                self.assertEqual(factory.call_args.args[0].project_config, expected)

    def test_native_command_retains_logs_exit_code_and_separates_display(self):
        import ios
        with tempfile.TemporaryDirectory() as directory, patch.object(ios, 'ui', Reporter()), \
                patch.dict(os.environ, {'NIBBLE_UI_FORMAT': 'json'}), \
                redirect_stderr(io.StringIO()) as err, redirect_stdout(io.StringIO()) as out:
            run = ios.Run.__new__(ios.Run)
            run.path = Path(directory)
            run.manifest = {'commands': []}
            value = run.command([sys.executable, '-c', 'print("native payload")'], 'success')
            with self.assertRaises(ios.VerificationError):
                run.command([sys.executable, '-c', 'import sys; print("native failure"); print("native stderr", file=sys.stderr); raise SystemExit(23)'], 'failure')
            self.assertEqual(value, 'native payload\n')
            self.assertEqual(out.getvalue(), '')
            self.assertEqual([event['exit_code'] for event in run.manifest['commands']], [0, 23])
            self.assertEqual((run.path / 'failure.log').read_text(), 'native failure\n')
            self.assertEqual((run.path / 'failure.stderr.log').read_text(), 'native stderr\n')
            self.assertNotIn('native payload', err.getvalue())
            self.assertNotIn('native failure', err.getvalue())
            self.assertNotIn('native stderr', err.getvalue())

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
        process.wait.assert_called_once()
        self.assertTrue(0 < process.wait.call_args.kwargs["timeout"] < float("inf"))

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


class ProductDriverFailureTests(unittest.TestCase):
    def test_empty_exception_message_cannot_report_a_passed_run(self):
        spec = importlib.util.spec_from_file_location("library_ui", Path(__file__).parents[1] / "check_library_ui.py")
        driver = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(driver)
        run = Mock()
        run.setup.side_effect = StopIteration()
        with patch.object(driver, "Run", return_value=run), patch.object(
                sys, "argv", ["check_library_ui.py", "--device", "selected"]):
            with self.assertRaises(SystemExit) as stopped:
                driver.main()
        self.assertTrue(str(stopped.exception))
        run.finish.assert_called_once()
        self.assertTrue(run.finish.call_args.args[0])


class DriverCancellationTests(unittest.TestCase):
    def test_interrupt_is_recorded_as_failure_in_every_product_driver(self):
        for filename in ['check_library_ui.py', 'check_notice_ui.py', 'check_interface_ui.py', 'check_about_ui.py']:
            with self.subTest(filename=filename):
                spec = importlib.util.spec_from_file_location('cancel_driver', Path(__file__).parents[1] / filename)
                driver = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(driver)
                run = Mock()
                run.setup.side_effect = KeyboardInterrupt()
                with patch.object(driver, 'Run', return_value=run), patch.object(
                        sys, 'argv', [filename, '--device', 'selected']):
                    with self.assertRaises((KeyboardInterrupt, SystemExit)):
                        driver.main()
                run.finish.assert_called_once()
                self.assertTrue(run.finish.call_args.args[0])
