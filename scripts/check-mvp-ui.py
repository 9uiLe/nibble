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

    def paste(identifier, text, replace=False):
        if replace:
            for attempt in range(2):
                try:
                    run.command(["sim-use", "paste", "--replace", "--via-menu", "--target-id", identifier,
                                 "--device", args.device, text])
                    return
                except VerificationError as error:
                    if "Edit menu 'Select All' item did not appear" not in str(error):
                        raise
                    run.manifest["commands"][-1]["handled_error"] = {
                        "reason": "sim-use 0.14.0 cannot match the observed Japanese Select All menu; use the native menu",
                        "assertion": "edited_copy_utf8_exact",
                    }
                    run.save()
                    current = run.ui(identifier + f"-replace-menu-{attempt}")
                    if any(entry.get("label") in ("すべてを選択", "Select All") for entry in current["entries"]):
                        break
                    # The initial gesture can just focus the field. Retry once
                    # after observing it; do not accept an absent menu as success.
                    if attempt == 1:
                        raise
            # sim-use 0.14.0 opens the native menu but cannot match this
            # runtime's Japanese Select All label. Verify and operate that menu.
            for labels in (("すべてを選択", "Select All"), ("カット", "Cut")):
                data = wait_ui(identifier + "-" + labels[0], lambda data: any(
                    entry.get("label") in labels for entry in data["entries"]))
                item = next(entry["label"] for entry in data["entries"] if entry.get("label") in labels)
                run.command(["sim-use", "tap", "--label", item, "--device", args.device])
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
                run.tap("editor.close")
                pending = wait_ui("draft-kept", lambda data: any(
                    entry.get("uniqueId", "").startswith("draft.") and entry.get("label", "").endswith(title)
                    for entry in data["entries"]))
                drafts = [entry["uniqueId"] for entry in pending["entries"]
                          if entry.get("uniqueId", "").startswith("draft.") and entry.get("label", "").endswith(title)]
                if len(drafts) != 1:
                    raise VerificationError("Expected exactly one draft for this run's title")
                run.tap(drafts[0])
                wait_ui("draft-resumed", lambda data: "editor.body" in identifiers(data))
                run.screenshot("resumed-draft")
                # Native AX text can omit surrounding whitespace. Validate the
                # resumed bytes through save/copy below, not a display value.
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
                edited_title = title + " 編集済み"
                edited_body = "更新された本文\n" + body
                paste("editor.title", edited_title, replace=True)
                paste("editor.body", edited_body, replace=True)
                run.tap("editor.save")
                wait_ui("edited", lambda data: any(e.get("uniqueId") == row
                        and e.get("label") == edited_title for e in data["entries"]))
                run.tap("copy." + snippet_id)
                if run.command([XCRUN, "simctl", "pbpaste", args.device], "edited-copy") != edited_body:
                    raise VerificationError("The edited row copied stale or altered text")
                run.screenshot("edited")
                run.tap(row)
                wait_ui("edited-reopened", lambda data: "editor.close" in identifiers(data))
                run.tap("editor.close")
                wait_ui("closed", lambda data: row in identifiers(data))
                menu(row, "pin-menu")
                label("ピン留め")
                pinned = wait_ui("pinned", lambda data: any(e.get("uniqueId") == row and "ピン留め" in e.get("label", "") for e in data["entries"]))
                if not any(e.get("uniqueId") == row and "ピン留め" in e.get("label", "") for e in pinned["entries"]):
                    raise VerificationError("Pin state did not update")
                menu(row, "delete-menu")
                run.tap("trash")
                deleted = wait_ui("deleted", lambda data: "library.undo" in identifiers(data))
                if row in identifiers(deleted):
                    raise VerificationError("Deleted row is still visible")
                # The notice expires after six seconds. A second AX traversal
                # can outlast it; tap the alias from the state just observed.
                undo = next(entry for entry in deleted["entries"] if entry.get("uniqueId") == "library.undo")
                run.command(["sim-use", "tap", "@" + str(undo["aliases"]["at"]), "--device", args.device])
                if row not in identifiers(wait_ui("restored", lambda data: row in identifiers(data))):
                    raise VerificationError("Undo did not restore the same snippet ID")
                run.screenshot("library")
                run.tap(row)
                wait_ui("editor", lambda data: "editor.body" in identifiers(data))
                run.screenshot("editor")
                run.tap("editor.more")
                run.ui("editor-menu")
                run.tap("editor.discard")
                run.ui("discard-confirmation")
                run.tap("editor.confirmDiscard")
                wait_ui("discarded", lambda data: row in identifiers(data)
                        and "editor.body" not in identifiers(data))
                run.tap("copy." + snippet_id)
                if run.command([XCRUN, "simctl", "pbpaste", args.device], "discarded-copy") != edited_body:
                    raise VerificationError("Discard changed the saved snippet's original text")
                run.tap("library.search.clear")
                finished = wait_ui("finished", lambda data: row in identifiers(data)
                                   and "library.search.clear" not in identifiers(data))
                if any(entry.get("uniqueId", "").startswith("draft.")
                       and entry.get("label", "").endswith(edited_title) for entry in finished["entries"]):
                    raise VerificationError("Discarded draft is still listed")
                run.screenshot("finished")
            run.manifest.setdefault("assertions", {}).update({
                "created_id": snippet_id, "search_term": title, "copy_utf8_exact": True, "japanese_search": True,
                "edited_title": edited_title, "edit_same_id": True, "edited_copy_utf8_exact": True,
                "pin": True, "delete_absent": True, "undo_same_id": True,
                "kept_draft_resumed": True, "discard_absent": True, "discard_preserves_saved_utf8": True,
                "data": "Dummy text only; existing snippets are retained",
            })
    except Exception as caught:
        error = str(caught)
    finally:
        run.finish(error)
    if error:
        raise SystemExit(error)


if __name__ == "__main__":
    main()
