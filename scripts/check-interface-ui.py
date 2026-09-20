#!/usr/bin/env python3
"""Compare app layout under default and accessibility text/contrast settings."""
import argparse
from contextlib import ExitStack
import time
from types import SimpleNamespace

from ios import Run, XCRUN, VerificationError


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    args = parser.parse_args()
    run = Run(SimpleNamespace(command="fixed-interface", device=args.device,
                              configuration="Release", project_config="app/project.json"))
    original, frames = {}, {}
    error = None
    contexts = ExitStack()

    def option(name, value):
        run.command([XCRUN, "simctl", "ui", args.device, name, value])
        observed = run.command([XCRUN, "simctl", "ui", args.device, name]).strip()
        if observed.casefold() != value.casefold():
            raise VerificationError(f"{name}: requested {value}, observed {observed}")
        time.sleep(0.5)

    def tab(label):
        run.ui()
        run.command(["sim-use", "tap", "--label", label, "--element-type", "RadioButton",
                     "--wait-timeout", "5", "--device", args.device])
        time.sleep(0.5)

    def capture(mode, screen, identifiers):
        found = {}
        for attempt in range(10):
            data = run.ui(f"{mode}-{screen}-{attempt}")
            if any(e.get("label") == "“nibble”で開きますか?" for e in data["entries"]):
                run.command(["sim-use", "tap", "--label", "開く", "--element-type", "Button",
                             "--device", args.device])
                time.sleep(0.5)
                continue
            found = {e["uniqueId"]: e["frame"] for e in data["entries"]
                     if e.get("uniqueId") in identifiers}
            if set(found) == set(identifiers):
                break
            time.sleep(0.3)
        else:
            raise VerificationError(f"Missing controls on {screen}: {set(identifiers) - set(found)}")
        frames.setdefault(mode, {})[screen] = found
        if mode != "default" and found != frames["default"][screen]:
            raise VerificationError(f"Accessibility settings changed {screen} layout: {found}")
        run.screenshot(f"{mode}-{screen}")

    try:
        run.setup()
        contexts.enter_context(run.device_lock())
        run.boot()
        for name in ("appearance", "content_size", "increase_contrast"):
            original[name] = run.command([XCRUN, "simctl", "ui", args.device, name]).strip()
        option("appearance", "light")
        option("content_size", "large")
        option("increase_contrast", "disabled")
        run.launch()
        with run.recording():
            for mode, size, contrast in (("default", "large", "disabled"),
                                         ("accessibility", "accessibility-extra-extra-extra-large", "enabled")):
                option("content_size", size)
                option("increase_contrast", contrast)
                run.command([XCRUN, "simctl", "openurl", args.device, "nibble://library"])
                time.sleep(0.5)
                capture(mode, "library", ["navigation.title", "library.filter.all", "library.filter.pinned", "library.filter.drafts"])
                run.command([XCRUN, "simctl", "openurl", args.device, "nibble://new"])
                time.sleep(0.7)
                capture(mode, "editor", ["editor.title", "editor.body", "editor.save", "editor.close"])
                run.tap("editor.close")
                time.sleep(0.5)
                tab("設定")
                capture(mode, "settings", ["navigation.title", "settings.actionButtonSide", "settings.about"])
                run.tap("settings.about")
                time.sleep(0.8)
                capture(mode, "about", ["about.story.caption"])
                run.tap("BackButton")
                time.sleep(0.5)
        run.manifest["layout_frames"] = frames
        run.manifest["assertions"] = {"library_editor_settings_about_frames_unchanged": True}
    except (Exception, KeyboardInterrupt) as caught:
        error = repr(caught)
        raise
    finally:
        try:
            for name, value in original.items():
                option(name, value)
        except (Exception, KeyboardInterrupt) as caught:
            error = (error + "; " if error else "") + "restore: " + repr(caught)
            raise
        finally:
            contexts.close()
            run.finish(error)


if __name__ == "__main__":
    main()
