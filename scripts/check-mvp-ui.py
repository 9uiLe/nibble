#!/usr/bin/env python3
"""Exercise the shipping app on an explicitly selected iOS 26.5 Simulator."""

import argparse
import json
import time
from types import SimpleNamespace
from uuid import uuid4

from ios import Run, XCRUN, VerificationError


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    args = parser.parse_args()
    run = Run(SimpleNamespace(command="mvp-ui", device=args.device, configuration="Release",
                              project_config="app/project.json"))
    body = "  日本語 か\u3099\n\t👩🏽‍💻 <code>  "
    title = "日本語コピー " + uuid4().hex[:8]
    error = None

    def label(text):
        run.command(["sim-use", "tap", "--label", text, "--element-type", "Button",
                     "--wait-timeout", "5", "--device", args.device])

    def paste(identifier, text):
        run.command(["sim-use", "paste", "--via-menu", "--target-id", identifier,
                     "--device", args.device, text])

    def identifiers(data):
        return {e.get("uniqueId", "") for e in data["entries"]}

    def menu(row, name):
        run.command(["sim-use", "long-press", "--id", row, "--device", args.device])
        time.sleep(0.35)
        run.ui(name)

    def wait_ui(name, predicate):
        for attempt in range(20):
            data = run.ui(f"{name}-{attempt}")
            if predicate(data):
                return data
            time.sleep(0.25)
        raise VerificationError(f"UI did not reach expected state: {name}")

    try:
        run.setup()
        if run.device["runtime"]["version"] != "26.5":
            raise VerificationError("MVP execution verification requires iOS 26.5")
        with run.device_lock():
            run.launch()
            before = run.ui("before")
            run.screenshot("before")
            with run.recording():
                run.tap("library.add")
                run.ui("new-editor")
                paste("editor.title", title)
                paste("editor.body", body)
                run.tap("editor.save")
                wait_ui("saved", lambda data: "library.search" in identifiers(data))
                # Identify this run's item through a unique Japanese search term.
                # A visible-row difference can mistake an older, newly revealed row
                # for the saved item when the keyboard or existing pins change layout.
                paste("library.search", title)
                data = wait_ui("searched", lambda data: any(
                    e.get("uniqueId", "").startswith("snippet.") and e.get("label") == title
                    for e in data["entries"]))
                added = [e["uniqueId"] for e in data["entries"]
                         if e.get("uniqueId", "").startswith("snippet.") and e.get("label") == title]
                if len(added) != 1:
                    raise VerificationError("Expected exactly one item for this run's unique search term")
                row = added[0]
                snippet_id = row.removeprefix("snippet.")
                run.tap("copy." + snippet_id)
                copied = run.command([XCRUN, "simctl", "pbpaste", args.device], "copied")
                if copied != body:
                    raise VerificationError("Copied UTF-8 text differs from input")
                run.tap("library.search.clear")
                wait_ui("search-cleared", lambda data: "library.search.clear" not in identifiers(data))
                paste("library.search", title)
                wait_ui("searched-again", lambda data: row in identifiers(data))
                run.tap("library.keyboard.dismiss")
                wait_ui("search-dismissed", lambda data: row in identifiers(data)
                        and "Return" not in identifiers(data))
                time.sleep(0.35)
                run.tap(row)
                wait_ui("reopened", lambda data: "editor.close" in identifiers(data))
                run.tap("editor.close")
                wait_ui("closed", lambda data: row in identifiers(data))
                menu(row, "pin-menu")
                label("ピン留め")
                pinned = wait_ui("pinned", lambda data: any(e.get("uniqueId") == row and "ピン留め" in e.get("label", "") for e in data["entries"]))
                if not any(e.get("uniqueId") == row and "ピン留め" in e.get("label", "") for e in pinned["entries"]):
                    raise VerificationError("Pin state did not update")
                menu(row, "delete-menu")
                run.tap("trash")
                if row in identifiers(wait_ui("deleted", lambda data: "library.undo" in identifiers(data))):
                    raise VerificationError("Deleted row is still visible")
                run.tap("library.undo")
                if row not in identifiers(wait_ui("restored", lambda data: row in identifiers(data))):
                    raise VerificationError("Undo did not restore the same snippet ID")
            run.screenshot("library")
            run.tap(row)
            wait_ui("editor", lambda data: "editor.body" in identifiers(data))
            run.screenshot("editor")
            # Exercise explicit draft discard as well as the earlier unchanged close.
            run.tap("editor.more")
            run.ui("editor-menu")
            run.tap("editor.discard")
            run.ui("discard-confirmation")
            run.tap("editor.confirmDiscard")
            run.ui("finished")
            run.manifest["assertions"] = {
                "created_id": snippet_id, "search_term": title, "copy_utf8_exact": True, "japanese_search": True,
                "pin": True, "delete_absent": True, "undo_same_id": True,
                "data": "Dummy text only; existing snippets are retained",
            }
    except Exception as caught:
        error = str(caught)
    finally:
        run.finish(error)
    if error:
        raise SystemExit(error)


if __name__ == "__main__":
    main()
