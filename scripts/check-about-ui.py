#!/usr/bin/env python3
"""Verify About's Rive playback and reading on an explicit iOS 26.5 Simulator.

The Simulator's Settings app must be on Accessibility > Motion when this starts.
The driver observes Reduce Motion, selects the requested mode and restores it.
"""
import argparse
from contextlib import ExitStack
import time
from types import SimpleNamespace
from ios import Run, XCRUN, VerificationError


def element(data, identifier):
    return next((e for e in data["entries"] if e.get("uniqueId") == identifier), None)


class AboutCheck:
    def __init__(self, run):
        self.run = run
        self.device = run.args.device
        self.observations = {}

    def option(self, name, value):
        self.run.command([XCRUN, "simctl", "ui", self.device, name, value])
        time.sleep(0.4)

    def motion(self, requested=None):
        self.run.command([XCRUN, "simctl", "launch", self.device, "com.apple.Preferences"])
        data = self.run.ui()
        switch = element(data, "REDUCE_MOTION")
        if switch is None or switch.get("value") not in ("0", "1"):
            raise VerificationError("Open Simulator Settings > Accessibility > Motion before running")
        current = switch["value"] == "1"
        if requested is not None and requested != current:
            # Settings exposes the whole row as the checkbox; its center is the label.
            # The observed iOS 26.5 switch sits in the trailing 60 pt of that frame.
            frame = switch["frame"]
            point = f"{frame['x'] + frame['width'] - 30},{frame['y'] + frame['height'] / 2}"
            self.run.command(["sim-use", "tap", "--point", point, "--duration", "0.05", "--device", self.device])
            time.sleep(0.3)
            data = self.run.ui()
            switch = element(data, "REDUCE_MOTION")
            if switch is None or switch.get("value") != str(int(requested)):
                raise VerificationError("Reduce Motion change did not take effect")
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
            if element(data, "settings.about"):
                self.run.tap("settings.about")
                time.sleep(0.7)
                return
            self.scroll(data)
        raise VerificationError("About entry unavailable")

    def wait_playback(self, label, name):
        for index in range(8):
            data = self.run.ui(f"{name}-{index}")
            button = element(data, "about.story.playback")
            if button and button.get("label") == label:
                if button["frame"]["height"] < 44:
                    raise VerificationError("Playback target must be at least 44 pt tall")
                return data
            time.sleep(0.6)
        raise VerificationError(f"Playback did not become {label}")

    def playback(self):
        self.wait_playback("もう一度見る", "completed")
        self.run.screenshot("completed")
        self.run.tap("about.story.playback")
        self.wait_playback("一時停止", "playing")
        self.run.tap("about.story.playback")
        self.wait_playback("再生", "paused")
        time.sleep(0.3)
        self.run.screenshot("paused")
        time.sleep(1)
        self.run.screenshot("paused-later")
        self.option("appearance", "dark")
        self.wait_playback("再生", "paused-dark")
        self.run.screenshot("paused-dark")
        self.option("increase_contrast", "enabled")
        self.wait_playback("再生", "paused-dark-contrast")
        self.run.screenshot("paused-dark-contrast")
        self.option("appearance", "light")
        self.option("increase_contrast", "disabled")
        self.wait_playback("再生", "paused-restored")
        self.run.screenshot("paused-restored")
        self.run.tap("about.story.playback")
        self.wait_playback("もう一度見る", "resumed-completed")
        self.run.screenshot("resumed-completed")
        self.run.tap("about.story.playback")
        self.wait_playback("一時停止", "before-background")
        self.run.command([XCRUN, "simctl", "launch", self.device, "com.apple.Preferences"])
        time.sleep(5)
        self.run.command([XCRUN, "simctl", "launch", self.device, self.run.config["bundle_id"]])
        self.wait_playback("一時停止", "after-background")
        self.run.screenshot("after-background")
        self.wait_playback("もう一度見る", "background-completed")

    def read_page(self, name):
        data = self.run.ui(name + "-top")
        self.run.screenshot(name + "-top")
        for index in range(30):
            paragraph = element(data, "about.privacy")
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
    args = parser.parse_args()
    reduced = args.reduce_motion == "enabled"
    run = Run(SimpleNamespace(command="rive-about-reduced" if reduced else "rive-about",
                              device=args.device, configuration="Release", project_config="app/project.json"))
    flow = AboutCheck(run)
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
            flow.open_about()
            if reduced:
                data = run.ui("reduced-first")
                run.screenshot("reduced-first")
                time.sleep(2)
                run.screenshot("reduced-still")
                if element(data, "about.story.playback"):
                    raise VerificationError("Reduce Motion must hide playback")
            else:
                flow.playback()
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
        run.manifest["assertions"] = {"paragraphs_reachable": True, "playback_matches_motion_preference": True}
    except Exception as caught:
        error = repr(caught)
        raise
    finally:
        try:
            for name, value in original.items():
                flow.option(name, value)
            if original_motion is not None:
                flow.motion(original_motion)
        except Exception as caught:
            cleanup_error = caught
            error = (error + "; " if error else "") + "restore: " + repr(caught)
        contexts.close()
        run.finish(error)
        if cleanup_error is not None:
            raise cleanup_error


if __name__ == "__main__":
    main()
