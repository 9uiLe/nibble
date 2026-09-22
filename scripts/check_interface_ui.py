#!/usr/bin/env python3
"""Compare app layout under default and accessibility text/contrast settings."""
import argparse
from contextlib import ExitStack
import time
from types import SimpleNamespace

from ios import simulator_lock, Run, XCRUN, VerificationError


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
        run.tap("navigation.tab." + {"一覧": "library", "検索": "search", "設定": "settings"}[label])
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

    def check_tab_scrolling(mode):
        def tabs(data):
            return {e["label"]: e["frame"] for e in data["entries"] if e.get("uniqueId", "").startswith("navigation.tab.")}

        data = run.ui(f"{mode}-tabs-initial")
        initial = tabs(data)
        width, height = data["screen"]["width"], data["screen"]["height"]
        high, low = f"{width * 0.45:.0f},{height * 0.32:.0f}", f"{width * 0.45:.0f},{height * 0.78:.0f}"
        if set(initial) != {"一覧", "設定", "検索"}:
            raise VerificationError("Native tabs must retain their accessible names")
        if any(min(frame["width"], frame["height"]) < 44 for frame in initial.values()):
            raise VerificationError("Native tabs must retain at least 44pt targets")
        run.command(["sim-use", "swipe", "--from", low, "--to", high,
                     "--duration", "0.4", "--post-delay", "0.8", "--device", args.device])
        scrolled = tabs(run.ui(f"{mode}-tabs-scrolled"))
        if scrolled != initial:
            raise VerificationError("Scrolling must preserve all standard tabs without shrinking")
        time.sleep(0.5)
        if tabs(run.ui(f"{mode}-tabs-settled")) != initial:
            raise VerificationError("Settling must preserve the standard tab bar")
        run.screenshot(f"{mode}-tabs-scrolled")
        run.command(["sim-use", "swipe", "--from", high, "--to", low,
                     "--duration", "0.4", "--post-delay", "0.8", "--device", args.device])
        restored = tabs(run.ui(f"{mode}-tabs-returned"))
        if restored != initial:
            raise VerificationError("Scrolling back must preserve all standard tabs")
        run.screenshot(f"{mode}-tabs-returned")
        run.manifest.setdefault("tab_scroll_frames", {})[mode] = {
            "before": initial, "scrolled": scrolled, "returned": restored,
        }

    try:
        run.setup()
        contexts.enter_context(simulator_lock(args.device))
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
                capture(mode, "settings", ["navigation.title", "library.trash", "settings.keyboard", "settings.about"])
                run.tap("settings.about")
                time.sleep(0.8)
                capture(mode, "about", ["about.story.caption"])
                check_tab_scrolling(mode)
                run.tap("BackButton")
                time.sleep(0.5)
                run.tap("settings.keyboard")
                time.sleep(0.8)
                capture(mode, "keyboard-guide", ["keyboard.story.caption"])
                run.tap("BackButton")
                time.sleep(0.5)
        run.manifest["layout_frames"] = frames
        run.manifest["assertions"] = {"library_editor_settings_guides_frames_unchanged": True,
                                      "all_three_native_tabs_remain_visible_without_shrinking": True}
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
