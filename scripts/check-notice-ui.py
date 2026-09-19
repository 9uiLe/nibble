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

    def delete(snippet):
        run.tap("more." + snippet)
        wait("delete-menu", lambda data: any(e.get("label") == "削除" for e in data["entries"]))
        label("削除")

    def undo():
        data = wait("undo", lambda data: "library.undo" in ids(data))
        entry = next(e for e in data["entries"] if e.get("uniqueId") == "library.undo")
        if entry["frame"]["height"] < 44:
            raise VerificationError("Undo hit target is shorter than 44 points")
        run.command(["sim-use", "tap", "@" + str(entry["aliases"]["at"]), "--device", args.device])

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
            run.tap("library.add" if "library.add" in ids(data) else "library.createFirst")
            wait("editor", lambda data: "editor.body" in ids(data))
            run.command(["sim-use", "paste", "--via-menu", "--target-id", "editor.title",
                         "--device", args.device, title])
            run.command(["python3", "-c", "import subprocess,sys; subprocess.run(['/usr/bin/xcrun','simctl','pbcopy',sys.argv[1]], input=sys.argv[2].encode(), check=True)",
                         args.device, "通知を確認するダミー本文"])
            label("本文の末尾にペースト")
            wait("body-pasted", lambda data: any(e.get("uniqueId") == "editor.body" and e.get("value") == "通知を確認するダミー本文" for e in data["entries"]))
            run.tap("editor.save")
            data = wait("saved", lambda data: any(e.get("uniqueId", "").startswith("snippet.")
                                                   and term in e.get("label", "") for e in data["entries"]))
            snippet = next(e["uniqueId"].removeprefix("snippet.") for e in data["entries"]
                           if e.get("uniqueId", "").startswith("snippet.") and term in e.get("label", ""))
            run.screenshot("notice-before")
            with run.recording():
                run.tap("copy." + snippet)
                run.screenshot("notice-copy")
                time.sleep(2.3)
                assert_no_notice("copy-expired")
                run.screenshot("notice-after")
                run.tap("copy." + snippet)
                run.tap("copy." + snippet)
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
                    run.tap("copy." + snippet)
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
                    run.tap("copy." + snippet)
                    run.tap("library.add")
                    wait("editor-opened", lambda data: "editor.body" in ids(data))
                    run.screenshot("editor-no-notice")
                    run.tap("editor.close")
                    assert_no_notice("editor-dismissed")
                    delete(snippet)
                    run.command(["sim-use", "button", "home", "--device", args.device])
                    run.command([XCRUN, "simctl", "launch", args.device, run.config["bundle_id"]])
                    assert_no_notice("foreground")
                    run.screenshot("foreground-no-notice")
            run.manifest["assertions"] = {"baseline": args.baseline, "created_id": snippet,
                "search_term": term, "appearance": args.appearance, "copy_expired": True,
                "undo_same_id": True, "search_and_lifecycle": not args.baseline}
    except Exception as caught:
        error = caught
    finally:
        if appearance in ("light", "dark"):
            try:
                run.command([XCRUN, "simctl", "ui", args.device, "appearance", appearance])
            except Exception as caught:
                error = error or caught
        run.finish(error)
    if error:
        raise SystemExit(repr(error))


if __name__ == "__main__":
    main()
