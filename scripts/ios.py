#!/usr/bin/env python3
"""Local iOS verification using Xcode CLI tools and pinned sim-use. Python stdlib only."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "artifacts" / "ios"
XCRUN = "/usr/bin/xcrun"
XCODEBUILD = "/usr/bin/xcodebuild"


class VerificationError(Exception):
    pass


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def validate_summary(summary):
    """A successful command with zero executed tests is not a passing test run."""
    if (summary.get("result") != "Passed" or summary.get("failedTests") != 0
            or summary.get("passedTests", 0) < 1 or summary.get("totalTestCount", 0) < 1):
        raise VerificationError("Tests did not pass, or no tests executed; inspect test-summary.json")


def select_device(devices, runtimes, udid, minimum):
    if not udid:
        raise VerificationError("Specify --device UDID explicitly; use the devices/create commands")
    runtime_map = {r["identifier"]: r for r in runtimes}
    for runtime_id, rows in devices.items():
        for row in rows:
            if row["udid"] == udid:
                runtime = runtime_map.get(runtime_id, {})
                if not row.get("isAvailable") or not runtime.get("isAvailable"):
                    raise VerificationError("The selected Simulator/runtime is unavailable")
                if not runtime_id.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
                    raise VerificationError("Select an iOS Simulator")
                version = lambda value: tuple(int(n) for n in value.split("."))
                if version(runtime["version"]) < version(minimum):
                    raise VerificationError(f"Requires iOS {minimum} or later")
                runtime = {key: runtime[key] for key in ("identifier", "name", "version", "buildversion", "isAvailable") if key in runtime}
                return {**row, "runtime": runtime}
    raise VerificationError(f"Unknown Simulator UDID: {udid}")


class Run:
    def __init__(self, args):
        self.args = args
        self.path = ARTIFACTS / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                                 + "-" + args.command + "-" + uuid.uuid4().hex[:6])
        self.path.mkdir(parents=True)
        self.manifest = {"status": "running", "command": args.command,
                         "started_at": datetime.now(timezone.utc).isoformat(), "commands": []}
        self.save()

    def save(self):
        write_json(self.path / "manifest.json", self.manifest)

    def command(self, argv, name=None, timeout=60):
        argv = [str(a) for a in argv]
        index = len(self.manifest["commands"])
        name = name or f"command-{index:03}"
        print("+ " + shlex.join(argv), flush=True)
        event = {"argv": argv, "stdout": name + ".log", "stderr": name + ".stderr.log"}
        self.manifest["commands"].append(event)
        self.save()
        start = time.monotonic()
        with (self.path / event["stdout"]).open("w") as out, (self.path / event["stderr"]).open("w") as err:
            try:
                result = subprocess.run(argv, cwd=ROOT, stdout=out, stderr=err, timeout=timeout, check=False)
                event["exit_code"] = result.returncode
            except subprocess.TimeoutExpired:
                event["error"] = "timeout"
                raise VerificationError(f"Command timed out after {timeout}s; see {self.path}")
            finally:
                event["seconds"] = round(time.monotonic() - start, 3)
                self.save()
        if result.returncode:
            detail = ((self.path / event["stdout"]).read_text() + (self.path / event["stderr"]).read_text())
            raise VerificationError(f"Command failed ({result.returncode}): {shlex.join(argv)}\n"
                                    + "\n".join(detail.splitlines()[-25:]))
        return (self.path / event["stdout"]).read_text()

    def setup(self):
        if platform.system() != "Darwin":
            raise VerificationError("iOS verification runs on a local Mac; Linux CI only runs static checks")
        self.config = json.loads((ROOT / self.args.project_config).read_text())
        if not shutil.which("sim-use"):
            raise VerificationError("sim-use is missing. Run through nix develop --command python3 scripts/ios.py")
        if self.command(["sim-use", "--version"], "sim-use-version").strip() != "0.14.0":
            raise VerificationError("Use sim-use 0.14.0 from the repository's Nix environment")
        self.manifest["environment"] = {
            "macos": platform.mac_ver()[0], "architecture": platform.machine(),
            "developer_dir": os.environ.get("DEVELOPER_DIR") or self.command(
                ["/usr/bin/xcode-select", "-p"], "developer-dir").strip(),
            "xcode": self.command([XCODEBUILD, "-version"], "xcode-version").strip(),
            "swift": self.command([XCRUN, "swift", "--version"], "swift-version").strip(),
            "simulator_sdk": self.command([XCRUN, "--sdk", "iphonesimulator", "--show-sdk-version"], "sdk-version").strip(),
            "sim_use": shutil.which("sim-use"), "configuration": self.args.configuration,
        }
        commit = self.command(["git", "rev-parse", "HEAD"], "commit").strip()
        status = self.command(["git", "status", "--porcelain=v1"], "worktree-status")
        # Record the exact relevant working files, including untracked additions.
        tracked = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT)
        hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                  for name in sorted(set(tracked.decode().split("\0"))) if name and (ROOT / name).is_file()}
        self.manifest.update({"commit": commit, "dirty": bool(status), "files_sha256": hashes,
                              "project": self.config, "visual_review": "pending"})
        self.devices = json.loads(self.command([XCRUN, "simctl", "list", "devices", "--json"], "devices"))["devices"]
        self.runtimes = json.loads(self.command([XCRUN, "simctl", "list", "runtimes", "--json"], "runtimes"))["runtimes"]
        if self.args.device:
            self.device = select_device(self.devices, self.runtimes, self.args.device, self.config["minimum_ios"])
            self.manifest["device"] = self.device
        self.save()

    @contextmanager
    def device_lock(self):
        # Shared across worktrees; only this user's nibble CLI invocations take this lock.
        directory = Path(tempfile.gettempdir()) / f"nibble-ios-{os.getuid()}"
        directory.mkdir(mode=0o700, exist_ok=True)
        with (directory / f"{self.args.device}.lock").open("w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise VerificationError("Another nibble verification command is using this Simulator")
            yield

    def boot(self):
        if self.device["state"] != "Booted":
            self.command([XCRUN, "simctl", "boot", self.args.device], "boot")
        self.command([XCRUN, "simctl", "bootstatus", self.args.device, "-b"], "bootstatus", timeout=180)
        self.device["state"] = "Booted"

    def build(self, test=False):
        self.boot()
        derived = ARTIFACTS / "DerivedData" / self.args.device
        self.derived = derived
        action = "test" if test else "build"
        result_path = self.path / f"{action}.xcresult"
        summary = {}
        command = [XCODEBUILD, "-project", ROOT / self.config["project"], "-scheme", self.config["scheme"],
                   "-configuration", self.args.configuration, "-destination", f"platform=iOS Simulator,id={self.args.device}",
                   "-derivedDataPath", derived, "-resultBundlePath", result_path,
                   "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO", action]
        try:
            self.command(command, "xcodebuild-" + action, timeout=900)
        finally:
            if test and result_path.is_dir():
                summary = json.loads(self.command([XCRUN, "xcresulttool", "get", "test-results", "summary",
                                                    "--path", result_path], "test-summary"))
                write_json(self.path / "test-summary.json", summary)
                self.command([XCRUN, "xcresulttool", "export", "attachments", "--path", result_path,
                              "--output-path", self.path / "attachments"], "test-attachments")
        if test:
            validate_summary(summary)

    def launch(self):
        self.build()
        app = self.derived / "Build" / "Products" / (self.args.configuration + "-iphonesimulator") / (self.config["app_name"] + ".app")
        self.command([XCRUN, "simctl", "install", self.args.device, app], "install")
        self.command([XCRUN, "simctl", "launch", "--terminate-running-process", self.args.device,
                      self.config["bundle_id"]], "launch")
        self.command(["sim-use", "app-state", "--reset", "--device", self.args.device], "app-state-reset")

    def ui(self, name="ui"):
        result = json.loads(self.command(["sim-use", "ui", "--device", self.args.device, "--json", "--no-raw"], name))
        if not result.get("ok") or not result.get("data", {}).get("entries"):
            raise VerificationError(f"Cannot observe UI: {result}")
        write_json(self.path / (name + ".json"), result)
        print(result["data"].get("outline", ""), flush=True)
        return result["data"]

    def tap(self, identifier):
        self.command(["sim-use", "tap", "--id", identifier, "--wait-timeout", "5", "--device", self.args.device])

    def screenshot(self, name="screenshot"):
        path = self.path / (name + ".png")
        self.command([XCRUN, "simctl", "io", self.args.device, "screenshot", "--type=png", path], name)
        if not path.is_file() or path.stat().st_size == 0:
            raise VerificationError("Screenshot was not written")

    @contextmanager
    def recording(self):
        path = self.path / "recording.mp4"
        argv = [XCRUN, "simctl", "io", self.args.device, "recordVideo", "--codec=h264", str(path)]
        print("+ " + shlex.join(argv), flush=True)
        event = {"argv": argv, "stderr": "recording.log"}
        self.manifest["commands"].append(event)
        self.save()
        ready = threading.Event()
        with (self.path / "recording.log").open("w") as log:
            process = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            def read():
                for line in process.stderr:
                    log.write(line)
                    log.flush()
                    if "Recording started" in line:
                        ready.set()
            reader = threading.Thread(target=read, daemon=True)
            reader.start()
            try:
                deadline = time.monotonic() + 30
                while not ready.wait(0.1):
                    if process.poll() is not None or time.monotonic() >= deadline:
                        raise VerificationError("Recording failed to start; inspect recording.log")
                yield
            finally:
                if process.poll() is None:
                    process.send_signal(signal.SIGINT)
                try:
                    event["exit_code"] = process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=10)
                    event["error"] = "Recording did not finalize after SIGINT"
                reader.join(timeout=5)
                self.save()
        if event.get("exit_code") != 0 or not path.is_file() or path.stat().st_size == 0:
            raise VerificationError("Recording did not complete; inspect recording.log")
        self.command([XCRUN, "swift", ROOT / "scripts/video_frames.swift", path, self.path / "video-frames"],
                     "video-inspection", timeout=120)

    def smoke(self):
        if self.config["bundle_id"] != "dev.nibble.VerificationApp":
            raise VerificationError("smoke is specific to the verification fixture; add a product-specific flow later")
        self.launch()
        self.command(["sim-use", "devices", "--no-physical-ios"], "sim-use-devices")
        self.ui("before")
        self.screenshot("before")
        with self.recording():
            self.tap("fixture.reset")
            self.ui("reset")
            self.tap("fixture.input")
            self.ui("focused")
            # Menu paste works even when Simulator's hardware keyboard is disconnected.
            self.command(["sim-use", "paste", "--via-menu", "--target-id", "fixture.input",
                          "--device", self.args.device, self.args.text], "paste", timeout=30)
            self.ui("pasted")
            self.tap("fixture.apply")
            result = self.ui("after")
            expect_text(result, "fixture.output", self.args.text)
            # Keep transition timing in the video; take the still after the tap animation.
            time.sleep(1)
        # Keep still capture separate from simctl's active recording session.
        self.screenshot("after")
        self.manifest["assertions"] = ["fixture.output accessibility value exactly matches the supplied text"]

    def finish(self, error=None):
        self.manifest.update(status="failed" if error else "passed",
                             finished_at=datetime.now(timezone.utc).isoformat())
        if error:
            self.manifest["error"] = str(error)
        self.save()
        media = sorted(p.name for p in self.path.glob("*.png")) + sorted(p.name for p in self.path.glob("*.mp4"))
        (self.path / "REVIEW.md").write_text(
            "# ローカル検証の証跡\n\n"
            f"- コマンド: `{self.args.command}`\n- 実行結果: {self.manifest['status']}\n"
            f"- コミット: `{self.manifest.get('commit', 'unavailable')}`\n"
            f"- 未コミット変更: {self.manifest.get('dirty', 'unknown')}（manifest のファイル hash も参照）\n"
            "- 実行条件・コマンド・終了コード: [manifest.json](manifest.json)\n"
            "- 人による画像・動画の確認: **未記入**\n"
            "- PR の添付先: **未記入**（ローカルパスだけでは添付完了にならない）\n\n"
            + "\n".join(f"- [{name}]({name})" for name in media) + "\n")
        print(f"Artifacts: {self.path}", flush=True)


def expect_text(data, identifier, text):
    matches = [e for e in data.get("entries", []) if e.get("uniqueId") == identifier]
    if len(matches) != 1 or matches[0].get("value") != text:
        raise VerificationError(f"Expected exact output for {identifier}; inspect after.json")


def parser():
    cli = argparse.ArgumentParser(description=__doc__)
    subs = cli.add_subparsers(dest="command", required=True)
    for name in ("doctor", "devices", "create", "boot", "build", "test", "run", "ui", "tap", "paste", "screenshot", "record", "smoke"):
        sub = subs.add_parser(name)
        sub.add_argument("--project-config", default="validation/project.json")
        sub.add_argument("--device", help="Explicit Simulator UDID; no implicit 'booted' target")
        sub.add_argument("--configuration", choices=("Debug", "Release"), default="Debug")
        if name == "create":
            sub.add_argument("--runtime", required=True, help="Runtime identifier from devices")
            sub.add_argument("--device-type", default="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro")
            sub.add_argument("--name", default="nibble Verification")
        if name == "tap":
            sub.add_argument("identifier")
        if name in ("paste", "smoke"):
            sub.add_argument("--text", default="日本語 👩🏽‍💻\nHello, nibble!")
        if name == "paste":
            sub.add_argument("--target-id", required=True)
        if name == "record":
            sub.add_argument("--seconds", type=float, default=10)
    return cli


def main(argv=None):
    args = parser().parse_args(argv)
    if args.device:
        try:
            uuid.UUID(args.device)
        except ValueError:
            raise SystemExit("--device must be a Simulator UDID")
    if args.command == "record" and not 0 < args.seconds <= 60:
        raise SystemExit("--seconds must be greater than 0 and at most 60")
    run = Run(args)
    try:
        run.setup()
        if args.command in ("doctor", "devices"):
            runtimes = [{key: r[key] for key in ("identifier", "version", "buildversion", "isAvailable")}
                        for r in run.runtimes if r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
            devices = [{"runtime": runtime, **{key: d[key] for key in ("name", "udid", "state")}}
                       for runtime, rows in run.devices.items()
                       if runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
                       for d in rows if d.get("isAvailable")]
            print(json.dumps({"environment": run.manifest["environment"], "runtimes": runtimes,
                              "devices": devices}, ensure_ascii=False, indent=2))
            if args.command == "doctor":
                run.command([XCODEBUILD, "-list", "-json", "-project", ROOT / run.config["project"]], "schemes")
        elif args.command == "create":
            print(run.command([XCRUN, "simctl", "create", args.name, args.device_type, args.runtime], "created-device").strip())
        else:
            if not args.device:
                raise VerificationError("Specify --device UDID explicitly")
            with run.device_lock():
                if args.command == "boot":
                    run.boot()
                elif args.command == "build":
                    run.build()
                elif args.command == "test":
                    run.build(test=True)
                elif args.command == "run":
                    run.launch()
                    run.ui()
                elif args.command == "smoke":
                    run.smoke()
                else:
                    if run.device["state"] != "Booted":
                        raise VerificationError("Boot the explicitly selected Simulator first")
                    if args.command == "ui":
                        run.ui()
                    elif args.command == "tap":
                        run.ui("before")
                        run.tap(args.identifier)
                        run.ui("after")
                    elif args.command == "paste":
                        run.ui("before")
                        run.command(["sim-use", "paste", "--via-menu", "--target-id", args.target_id,
                                     "--device", args.device, args.text], "paste")
                        run.ui("after")
                    elif args.command == "screenshot":
                        run.screenshot()
                    elif args.command == "record":
                        with run.recording():
                            time.sleep(args.seconds)
        run.finish()
        return 0
    except (VerificationError, OSError, ValueError, subprocess.SubprocessError, KeyboardInterrupt) as error:
        run.finish(error or "Interrupted")
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
