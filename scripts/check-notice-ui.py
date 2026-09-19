#!/usr/bin/env python3
"""Verify tab result notifications on an explicitly selected iOS 26.5 Simulator."""

import argparse
import time
from types import SimpleNamespace
from uuid import uuid4

from ios import Run, XCRUN, VerificationError


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--geometry-only", action="store_true", help="Check tab and create-button stability during one copy notice")
    parser.add_argument("--scroll", action="store_true", help="Also seed a scrollable list and check its final row")
    parser.add_argument("--appearance", choices=("light", "dark"), default="light")
    args = parser.parse_args()
    run = Run(SimpleNamespace(command="notice-ui", device=args.device, configuration="Release",
                              project_config="app/project.json"))
    term = "通知検証" + uuid4().hex[:8]
    title = term + " 長い対象名でも操作結果と元に戻すを読めることを確認します"
    error = None
    appearance = None

    def ids(data):
        return {entry.get("uniqueId") for entry in data["entries"]}

    def wait(name, predicate):
        for attempt in range(15):
            try:
                data = run.ui(f"{name}-{attempt}")
            except VerificationError as error:
                # A native presentation may briefly expose an empty AX tree.
                if "Cannot observe UI:" not in str(error) or "'entries': []" not in str(error):
                    raise
                run.manifest.setdefault("transient_empty_ax", []).append(f"{name}-{attempt}")
                run.save()
                time.sleep(0.2)
                continue
            if predicate(data):
                return data
            time.sleep(0.2)
        raise VerificationError("UI did not reach expected state: " + name)

    def label(text, role="Button"):
        run.command(["sim-use", "tap", "--label", text, "--element-type", role,
                     "--wait-timeout", "5", "--device", args.device])

    def tab(text):
        label(text, "RadioButton")

    def assert_no_notice(name):
        return wait(name, lambda data: "library.notice" not in ids(data) and "library.undo" not in ids(data))

    def navigation_frames(data):
        frames = {e["label"]: e["frame"] for e in data["entries"] if e.get("role") == "RadioButton"}
        frames.update({"library.add": e["frame"] for e in data["entries"] if e.get("uniqueId") == "library.add"})
        frames.update({e["uniqueId"]: e["frame"] for e in data["entries"]
                       if e.get("uniqueId", "").startswith("library.filter.")})
        if not {"一覧", "設定", "検索", "library.add"}.issubset(frames):
            raise VerificationError("Navigation controls are missing")
        return frames

    def tap_row(identifier):
        for attempt in range(12):
            data = run.ui(f"reveal-{attempt}")
            bottom = min((e["frame"]["y"] for e in data["entries"]
                          if e.get("uniqueId") == "library.add" or e.get("role") == "TextField"), default=490)
            top = max((e["frame"]["y"] + e["frame"]["height"] for e in data["entries"]
                       if e.get("role") == "Heading" and e["frame"]["y"] < 200), default=126) + 8
            entry = next((e for e in data["entries"] if e.get("uniqueId") == identifier), None)
            if entry and entry["frame"]["y"] >= top and entry["frame"]["y"] + entry["frame"]["height"] <= bottom:
                run.tap(identifier)
                return
            high, low = top + 20, min(bottom - 20, 460)
            downward = entry is not None and entry["frame"]["y"] < top
            run.command(["sim-use", "swipe", "--from", f"180,{high if downward else low}",
                         "--to", f"180,{low if downward else high}",
                         "--duration", "0.4", "--post-delay", "0.3", "--device", args.device])
        raise VerificationError("Could not reveal row control: " + identifier)

    def delete(snippet):
        tap_row("more." + snippet)
        wait("delete-menu", lambda data: any(e.get("label") == "削除" for e in data["entries"]))
        label("削除")

    def undo():
        data = wait("undo", lambda data: "library.undo" in ids(data))
        entry = next(e for e in data["entries"] if e.get("uniqueId") == "library.undo")
        if entry["frame"]["height"] < 44:
            raise VerificationError("Undo hit target is shorter than 44 points")
        for field in (e for e in data["entries"] if e.get("role") == "TextField"):
            button, text = entry["frame"], field["frame"]
            if (button["x"] < text["x"] + text["width"] and text["x"] < button["x"] + button["width"]
                    and button["y"] < text["y"] + text["height"] and text["y"] < button["y"] + button["height"]):
                raise VerificationError("Undo overlaps the search field")
        run.command(["sim-use", "tap", "@" + str(entry["aliases"]["at"]), "--device", args.device])
        wait("undo-succeeded", lambda data: any(e.get("uniqueId") == "library.notice"
             and e.get("label", "").endswith("元に戻しました") for e in data["entries"]))

    def create_item(title, data):
        run.tap("library.add" if "library.add" in ids(data) else "library.createFirst")
        wait("editor", lambda data: "editor.body" in ids(data))
        run.command(["sim-use", "paste", "--via-menu", "--target-id", "editor.title",
                     "--device", args.device, title])
        run.command(["python3", "-c", "import subprocess,sys; subprocess.run(['/usr/bin/xcrun','simctl','pbcopy',sys.argv[1]], input=sys.argv[2].encode(), check=True)",
                     args.device, "通知を確認するダミー本文"])
        label("本文の末尾にペースト")
        wait("body-pasted", lambda data: any(e.get("uniqueId") == "editor.body" and e.get("value") == "通知を確認するダミー本文" for e in data["entries"]))
        run.tap("editor.save")
        wait("created-list", lambda data: "library.add" in ids(data) and "editor.body" not in ids(data))
        for attempt in range(15):
            data = run.ui(f"created-row-{attempt}")
            entry = next((e for e in data["entries"] if e.get("uniqueId", "").startswith("snippet.")
                          and title in e.get("label", "")), None)
            if entry:
                return entry["uniqueId"].removeprefix("snippet.")
            run.command(["sim-use", "swipe", "--from", "180,460", "--to", "180,180",
                         "--duration", "0.4", "--post-delay", "0.3", "--device", args.device])
        raise VerificationError("Created row was not found in the list")

    try:
        run.setup()
        with run.device_lock():
            run.boot()
            appearance = run.command([XCRUN, "simctl", "ui", args.device, "appearance"]).strip()
            run.command([XCRUN, "simctl", "ui", args.device, "appearance", args.appearance])
            run.launch()
            data = wait("library", lambda data: "library.add" in ids(data) or "library.createFirst" in ids(data) or "editor.close" in ids(data))
            if "editor.close" in ids(data):
                run.tap("editor.close")
                data = wait("editor-closed", lambda data: "library.add" in ids(data) or "library.createFirst" in ids(data))
            existing_copy = next((e for e in data["entries"] if e.get("uniqueId", "").startswith("copy.")), None)
            if args.geometry_only and existing_copy:
                snippet = existing_copy["uniqueId"].removeprefix("copy.")
            else:
                snippet = create_item(title, data)
                # Reveal the new row before establishing the notification-free baseline.
                tap_row("copy." + snippet)
                time.sleep(2.3)
            data = assert_no_notice("initial-copy-expired")
            before_frames = navigation_frames(data)
            run.screenshot("notice-before")
            with run.recording():
                tap_row("copy." + snippet)
                data = wait("copy-notice-visible", lambda data: "library.notice" in ids(data))
                during_frames = navigation_frames(data)
                run.screenshot("notice-copy")
                time.sleep(2.3)
                data = assert_no_notice("copy-expired")
                after_frames = navigation_frames(data)
                run.screenshot("notice-after")
                if not args.baseline:
                    run.manifest["navigation_frames"] = {"before": before_frames, "during": during_frames, "after": after_frames}
                    movements = {phase: {label: {axis: current[label][axis] - frame[axis]
                                                for axis in ("x", "y", "width", "height")
                                                if abs(current[label][axis] - frame[axis]) > 1}
                                          for label, frame in before_frames.items()}
                                 for phase, current in (("during", during_frames), ("after", after_frames))}
                    run.manifest["navigation_movements"] = movements
                    run.save()
                    if any(delta for phase in movements.values() for delta in phase.values()):
                        raise VerificationError("Navigation controls moved with the notice: " + str(movements))
                if args.geometry_only:
                    run.manifest["assertions"] = {"navigation_frames_stable": True, "copy_expired": True}
                    return
                tap_row("copy." + snippet)
                tap_row("copy." + snippet)
                run.screenshot("notice-repeated-copy")
                delete(snippet)
                run.screenshot("notice-deleted")
                undo()
                run.screenshot("notice-restored")
                wait("restored-row", lambda data: "snippet." + snippet in ids(data))
                time.sleep(2.3)
                assert_no_notice("restored-expired")
                if not args.baseline:
                    tab("検索")
                    data = wait("search-field", lambda data: any(e.get("role") == "TextField" for e in data["entries"]))
                    field = next(e for e in data["entries"] if e.get("role") == "TextField")
                    frame = field["frame"]
                    run.command(["sim-use", "paste", "--via-menu", "--target-x", str(frame["x"] + frame["width"] / 2),
                                 "--target-y", str(frame["y"] + frame["height"] / 2), "--device", args.device, term])
                    data = wait("search-result", lambda data: "copy." + snippet in ids(data) and "Search" in ids(data))
                    search_frame = next(e["frame"] for e in data["entries"] if e.get("role") == "TextField")
                    run.screenshot("search-before")
                    tap_row("copy." + snippet)
                    wait("search-notice", lambda data: "library.notice" in ids(data) and "Search" in ids(data))
                    run.screenshot("search-copy-keyboard")
                    time.sleep(2.3)
                    data = assert_no_notice("search-expired")
                    if not any(e.get("role") == "TextField" and e.get("value") == term for e in data["entries"]):
                        raise VerificationError("Search query was lost on notification expiry")
                    field_after = next(e for e in data["entries"] if e.get("role") == "TextField")
                    if "Search" not in ids(data) or any(abs(field_after["frame"][key] - search_frame[key]) > 1 for key in ("x", "y", "width", "height")):
                        raise VerificationError("Search keyboard or field placement changed on expiry")
                    run.screenshot("search-after")
                    delete(snippet)
                    run.screenshot("search-delete-keyboard")
                    undo()
                    data = wait("search-undo-input-preserved", lambda data: "Search" in ids(data)
                                and any(e.get("role") == "TextField" and e.get("value") == term
                                        for e in data["entries"]))
                    run.screenshot("search-restored-keyboard")
                    label("閉じる")
                    tab("一覧")
                    wait("library-restored", lambda data: "snippet." + snippet in ids(data))
                    delete(snippet)
                    tab("設定")
                    assert_no_notice("other-tab")
                    tab("一覧")
                    assert_no_notice("returned-tab")
                    tab("設定")
                    run.tap("library.trash")
                    wait("trash", lambda data: "more." + snippet in ids(data))
                    run.tap("more." + snippet)
                    label("復元")
                    run.screenshot("trash-restored")
                    run.tap("library.trash.close")
                    assert_no_notice("sheet-dismissed")
                    tab("一覧")
                    wait("restored-from-trash", lambda data: "snippet." + snippet in ids(data))
                    tap_row("copy." + snippet)
                    run.tap("library.add")
                    wait("editor-opened", lambda data: "editor.body" in ids(data))
                    run.screenshot("editor-no-notice")
                    run.tap("editor.close")
                    assert_no_notice("editor-dismissed")
                    delete(snippet)
                    run.command(["sim-use", "button", "home", "--device", args.device])
                    wait("home-settled", lambda data: data.get("appPackage") == "com.apple.springboard"
                         and "navigation.title" not in ids(data))
                    run.command([XCRUN, "simctl", "launch", args.device, run.config["bundle_id"]])
                    def library_is_active(data):
                        return (data.get("appPackage") == run.config["bundle_id"]
                                and any(e.get("uniqueId") == "navigation.title" and e.get("label") == "一覧" for e in data["entries"])
                                and any(e.get("role") == "RadioButton" and e.get("label") == "一覧"
                                        and "selected" in e.get("states", []) for e in data["entries"])
                                and ("library.add" in ids(data) or "library.createFirst" in ids(data)))
                    wait("foreground-root", library_is_active)
                    time.sleep(0.3)
                    wait("foreground-stable", library_is_active)
                    assert_no_notice("foreground")
                    run.screenshot("foreground-no-notice")
                    if args.scroll:
                        for index in range(8):
                            data = wait("seed-list", lambda data: "library.add" in ids(data) or "library.createFirst" in ids(data))
                            seeded_id = create_item(f"{term} スクロール確認 {index + 1}", data)
                            if index > 0:
                                tap_row("copy." + seeded_id)
                                wait("seed-copy", lambda data: "library.notice" in ids(data))
                        previous = None
                        for attempt in range(12):
                            data = run.ui(f"scroll-{attempt}")
                            add_frame = next(e["frame"] for e in data["entries"] if e.get("uniqueId") == "library.add")
                            controls = [e for e in data["entries"] if e.get("uniqueId", "").startswith("copy.")
                                        and 140 < e["frame"]["y"] and e["frame"]["y"] + e["frame"]["height"] <= add_frame["y"]]
                            signature = [(e["uniqueId"], round(e["frame"]["y"])) for e in controls]
                            if signature and signature == previous:
                                break
                            previous = signature
                            run.command(["sim-use", "swipe", "--from", "180,460", "--to", "180,160",
                                         "--duration", "0.5", "--post-delay", "0.5", "--device", args.device])
                        else:
                            raise VerificationError("Scrollable list did not reach a stable final row")
                        if not controls:
                            raise VerificationError("No final row is operable above the bottom controls")
                        final_control = [e for e in data["entries"] if e.get("uniqueId", "").startswith("copy.")][-1]
                        if final_control not in controls:
                            raise VerificationError("Final row is hidden behind the bottom controls")
                        final_id = final_control["uniqueId"]
                        run.screenshot("scroll-before")
                        # Every newer fixture row has already been copied once. The oldest row
                        # goes from zero uses to one and stays last (the tie uses update time).
                        # The separate window must preserve the viewport during the notice as
                        # well as after expiry. This also catches accidental safe-area insertion.
                        anchors = [e for e in data["entries"] if e.get("uniqueId", "").startswith("snippet.")
                                   and e["uniqueId"] != "snippet." + final_id.removeprefix("copy.")
                                   and 170 < e["frame"]["y"] < 400]
                        if not anchors:
                            raise VerificationError("No visible anchor before final-row copy")
                        anchor = anchors[0]
                        run.tap(final_id)
                        data = wait("scroll-copy-rendered", lambda data: "library.notice" in ids(data))
                        during = next((e for e in data["entries"] if e.get("uniqueId") == anchor["uniqueId"]), None)
                        if during is None or abs(during["frame"]["y"] - anchor["frame"]["y"]) > 1:
                            raise VerificationError("Scroll anchor changed while the notification was visible")
                        run.screenshot("scroll-copy")
                        time.sleep(2.3)
                        data = assert_no_notice("scroll-expired")
                        after = next((e for e in data["entries"] if e.get("uniqueId") == anchor["uniqueId"]), None)
                        if after is None or abs(after["frame"]["y"] - anchor["frame"]["y"]) > 1:
                            raise VerificationError("Scroll anchor changed on notification expiry")
                        run.screenshot("scroll-after")
                        run.manifest["scroll_assertions"] = {"seeded_rows": 8, "operated_control": final_id,
                            "anchor_id": anchor["uniqueId"],
                            "before_y": anchor["frame"]["y"], "during_y": during["frame"]["y"], "after_y": after["frame"]["y"],
                            "notice_expiry_preserved_scroll": True}

            run.manifest["assertions"] = {"baseline": args.baseline, "created_id": snippet,
                "search_term": term, "appearance": args.appearance, "copy_expired": True,
                "undo_same_id": True, "search_and_lifecycle": not args.baseline,
                "navigation_frames_stable": not args.baseline}
    except (Exception, KeyboardInterrupt) as caught:
        error = caught
    finally:
        if appearance in ("light", "dark"):
            try:
                run.command([XCRUN, "simctl", "ui", args.device, "appearance", appearance])
            except (Exception, KeyboardInterrupt) as caught:
                error = error or caught
        run.finish(error)
    if error:
        raise SystemExit(repr(error))


if __name__ == "__main__":
    main()
