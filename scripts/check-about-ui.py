#!/usr/bin/env python3
"""Verify explanation playback and reading on an explicit iOS 26.5 Simulator.

The Simulator's Settings app must be on Accessibility > Motion when this starts.
The driver observes Reduce Motion, selects the requested mode and restores it.
"""
import argparse
from contextlib import ExitStack
import hashlib
from pathlib import Path
import time
from types import SimpleNamespace
from ios import ROOT, Run, XCRUN, VerificationError


def element(data, identifier):
    return next((e for e in data["entries"] if e.get("uniqueId") == identifier), None)


class AboutCheck:
    def __init__(self, run, story="about"):
        self.run = run
        self.device = run.args.device
        self.observations = {}
        self.story = story

    def option(self, name, value):
        self.run.command([XCRUN, "simctl", "ui", self.device, name, value])
        time.sleep(0.4)

    def motion(self, requested=None):
        def wait_switch(expected=None):
            for index in range(10):
                data = self.run.ui(f"motion-{index}", allow_empty=True)
                switch = element(data, "REDUCE_MOTION")
                if (data.get("appPackage") == "com.apple.Preferences" and switch is not None
                        and switch.get("value") in ("0", "1")
                        and (expected is None or switch["value"] == str(int(expected)))):
                    return switch
                time.sleep(0.3)
            raise VerificationError("Settings > Accessibility > Motion did not reach the expected switch state")

        self.run.command([XCRUN, "simctl", "launch", self.device, "com.apple.Preferences"])
        switch = wait_switch()
        current = switch["value"] == "1"
        if requested is not None and requested != current:
            # Settings exposes the whole row as the checkbox; its center is the label.
            # The observed iOS 26.5 switch sits in the trailing 60 pt of that frame.
            frame = switch["frame"]
            point = f"{frame['x'] + frame['width'] - 30},{frame['y'] + frame['height'] / 2}"
            self.run.command(["sim-use", "tap", "--point", point, "--duration", "0.05", "--device", self.device])
            switch = wait_switch(requested)
        self.run.manifest.setdefault("motion_observations", []).append({
            "before": current, "requested": requested, "observed": switch["value"] == "1"
        })
        self.run.save()
        return current

    def scroll(self, data, up=False):
        width, height = data["screen"]["width"], data["screen"]["height"]
        start, end = (0.31, 0.76) if up else (0.76, 0.31)
        self.run.command(["sim-use", "swipe", "--from", f"{width * .5},{height * start}",
                          "--to", f"{width * .5},{height * end}", "--duration", "0.5", "--device", self.device])
        time.sleep(0.3)

    def open_about(self):
        self.run.ui()
        self.run.command(["sim-use", "tap", "--label", "設定", "--element-type", "RadioButton",
                          "--wait-timeout", "5", "--device", self.device])
        for _ in range(5):
            data = self.run.ui()
            if element(data, "settings." + self.story):
                self.run.tap("settings." + self.story)
                time.sleep(0.7)
                return
            self.scroll(data)
        raise VerificationError("Explanation entry unavailable: " + self.story)

    def check_illustration(self, name):
        # During app switching, Simulator can report a mixed Settings/Nibble tree.
        for index in range(10):
            data = self.run.ui(f"{name}-{index}")
            if data.get("appPackage") == self.run.config["bundle_id"]:
                if element(data, self.story + ".story.playback") or element(data, self.story + ".story.retry"):
                    raise VerificationError("Automatic illustration must load without playback controls")
                caption = element(data, self.story + ".story.caption")
                if caption and "nibble" in caption.get("label", ""):
                    return data
            time.sleep(0.3)
        raise VerificationError("Explanation caption unavailable after app transition")

    def failure_retry(self):
        self.option("appearance", "dark")
        container = Path(self.run.command([XCRUN, "simctl", "get_app_container", self.device,
                                           self.run.config["bundle_id"], "app"]).strip())
        name = self.story + "-story.riv"
        asset = container / name
        original = asset.read_bytes()
        digest = lambda value: hashlib.sha256(value).hexdigest()
        if digest(original) != digest((ROOT / "app/Nibble/Animations" / name).read_bytes()):
            raise VerificationError("Installed asset does not match the recorded source")
        corrupt = b"NIBBLE_RIVE_DECODE_FAILURE"
        record = {"target": str(asset), "original_sha256": digest(original),
                  "injected_sha256": digest(corrupt), "events": []}
        self.run.manifest["fault_injection"] = record
        (self.run.path / (name + ".backup")).write_bytes(original)
        try:
            asset.write_bytes(corrupt)
            record["events"].append("decode_failure_injected")
            self.run.save()
            self.open_about()
            for index in range(10):
                data = self.run.ui(f"load-failed-{index}")
                if (element(data, self.story + ".story.retry")
                        and element(data, self.story + ".story.caption")
                        and element(data, "BackButton")):
                    break
                time.sleep(.3)
            else:
                raise VerificationError("Failed illustration must retain caption, retry and navigation")
            self.run.screenshot("load-failed-dark")
            record["events"].append("failure_ui_observed")
        finally:
            asset.write_bytes(original)
            record["restored_sha256"] = digest(asset.read_bytes())
            record["events"].append("asset_restored")
            self.run.save()
        # Keep this exact failed screen alive: exercise Button -> attempt -> task.
        self.run.tap(self.story + ".story.retry")
        record["events"].append("retry_button_tapped")
        time.sleep(.7)
        self.check_illustration("retry-restored")
        self.run.screenshot("retry-restored-dark")
        record["events"].append("recovery_ui_observed")
        self.run.save()
        self.option("appearance", "light")

    def playback(self):
        self.check_illustration("automatic")
        # Capture more than two periods. Actual motion and loop boundaries are reviewed in the video.
        for index in range(7):
            self.run.screenshot(f"loop-{index}")
            time.sleep(2.9)
        self.check_illustration("after-two-periods")
        self.option("appearance", "dark")
        self.run.screenshot("loop-dark")
        self.option("increase_contrast", "enabled")
        self.run.screenshot("loop-dark-contrast")
        self.option("appearance", "light")
        self.option("increase_contrast", "disabled")
        self.run.command([XCRUN, "simctl", "launch", self.device, "com.apple.Preferences"])
        time.sleep(3)
        self.run.command([XCRUN, "simctl", "launch", self.device, self.run.config["bundle_id"]])
        self.check_illustration("after-background")
        self.run.screenshot("after-background")
        self.motion(True)
        self.run.command([XCRUN, "simctl", "launch", self.device, self.run.config["bundle_id"]])
        time.sleep(0.5)
        self.check_illustration("reduce-motion-on")
        self.run.screenshot("reduce-motion-on")
        time.sleep(2)
        self.run.screenshot("reduce-motion-on-later")
        self.motion(False)
        self.run.command([XCRUN, "simctl", "launch", self.device, self.run.config["bundle_id"]])
        self.check_illustration("reduce-motion-off")
        time.sleep(2)
        self.run.screenshot("reduce-motion-off")

    def interruptions(self):
        # Both tabs remain alive. Returning must use the same viewport/session;
        # the mounted tests assert identity, while this recording shows continuity.
        self.run.command(["sim-use", "tap", "--label", "一覧", "--element-type", "RadioButton",
                          "--wait-timeout", "5", "--device", self.device])
        time.sleep(1)
        self.run.command(["sim-use", "tap", "--label", "設定", "--element-type", "RadioButton",
                          "--wait-timeout", "5", "--device", self.device])
        self.check_illustration("after-tab")
        self.run.screenshot("after-tab")
        # Three visible drags with deceleration, then repeated offscreen/return crossings.
        for _ in range(3):
            data = self.run.ui()
            width, height = data["screen"]["width"], data["screen"]["height"]
            for start, end in ((.62, .54), (.54, .62)):
                self.run.command(["sim-use", "swipe", "--from", f"{width * .5},{height * start}",
                                  "--to", f"{width * .5},{height * end}", "--duration", "0.4",
                                  "--device", self.device])
                time.sleep(.3)
        for index in range(3):
            data = self.run.ui()
            self.scroll(data)
            self.scroll(data)
            self.run.screenshot(f"offscreen-{index}")
            if index == 2:
                # Return to the app while still offscreen after a longer background stay.
                self.run.command([XCRUN, "simctl", "launch", self.device, "com.apple.Preferences"])
                time.sleep(30)
                self.run.command([XCRUN, "simctl", "launch", self.device, self.run.config["bundle_id"]])
                self.run.screenshot("background-return-offscreen")
            self.scroll(data, up=True)
            self.scroll(data, up=True)
            self.check_illustration(f"boundary-return-{index}")
            time.sleep(1)
        self.run.screenshot("after-boundaries")

    def read_page(self, name):
        data = self.run.ui(name + "-top")
        self.run.screenshot(name + "-top")
        for index in range(30):
            paragraph = element(data, "about.privacy" if self.story == "about" else "keyboard.guide.limits")
            if paragraph:
                frame = paragraph["frame"]
                if 75 <= frame["y"] and frame["y"] + frame["height"] <= data["screen"]["height"] - 70:
                    break
            self.scroll(data)
            data = self.run.ui(f"{name}-scroll-{index}")
        else:
            raise VerificationError("Final paragraph is not reachable")
        self.run.screenshot(name + "-bottom")
        self.observations[name] = {"final_paragraph_reachable": True, "swipes": index}
        self.run.tap("BackButton")
        time.sleep(0.4)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--reduce-motion", choices=("enabled", "disabled"), default="disabled")
    parser.add_argument("--story", choices=("about", "keyboard"), default="about")
    parser.add_argument("--interruptions", action="store_true", help="Record tab, scroll and 30-second background returns")
    parser.add_argument("--fault-retry", action="store_true", help="Temporarily corrupt the installed asset, restore it and tap retry")
    args = parser.parse_args()
    reduced = args.reduce_motion == "enabled"
    run = Run(SimpleNamespace(command="rive-" + args.story + ("-reduced" if reduced else ""),
                              device=args.device, configuration="Release", project_config="app/project.json"))
    flow = AboutCheck(run, args.story)
    error, original_motion = None, None
    cleanup_error = None
    original = {}
    contexts = ExitStack()
    try:
        run.setup()
        contexts.enter_context(run.device_lock())
        run.boot()
        for name in ("appearance", "content_size", "increase_contrast"):
            original[name] = run.command([XCRUN, "simctl", "ui", args.device, name]).strip()
        flow.option("appearance", "light")
        flow.option("content_size", "large")
        flow.option("increase_contrast", "disabled")
        original_motion = flow.motion()
        flow.motion(reduced)
        run.launch()
        with run.recording():
            if args.fault_retry:
                flow.failure_retry()
            else:
                flow.open_about()
            if reduced:
                flow.check_illustration("reduce-motion-initial")
                run.screenshot("reduce-motion-initial")
            flow.playback()
            if args.interruptions:
                flow.interruptions()
            flow.read_page("light")
            flow.option("appearance", "dark")
            flow.open_about()
            time.sleep(4.5)
            flow.read_page("dark")
            flow.option("appearance", "light")
            flow.option("content_size", "accessibility-extra-extra-extra-large")
            flow.open_about()
            flow.read_page("largest")
        run.manifest["reading_observations"] = flow.observations
        run.manifest["assertions"] = {"paragraphs_reachable": True, "illustration_loaded_without_playback_controls": True}
    except (Exception, KeyboardInterrupt) as caught:
        error = repr(caught)
        raise
    finally:
        try:
            for name, value in original.items():
                flow.option(name, value)
            if original_motion is not None:
                flow.motion(original_motion)
        except (Exception, KeyboardInterrupt) as caught:
            cleanup_error = caught
            error = (error + "; " if error else "") + "restore: " + repr(caught)
        contexts.close()
        run.finish(error)
        if cleanup_error is not None:
            raise cleanup_error


if __name__ == "__main__":
    main()
