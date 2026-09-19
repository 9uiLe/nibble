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

    def tab(text):
        run.command(["sim-use", "tap", "--label", text, "--element-type", "RadioButton",
                     "--wait-timeout", "5", "--device", args.device])

    def check_navigation_title(data, title):
        headings = [e["frame"] for e in data["entries"]
                    if e.get("role") == "Heading" and e.get("label") == title]
        if not headings or not any(frame["x"] < data["screen"]["width"] / 4
                                   and 50 <= frame["y"] < 120 and frame["width"] >= 32 for frame in headings):
            raise VerificationError("Root title must be leading inside the navigation bar: " + title)

    def choose_side(side):
        data = wait_ui("position-picker", lambda data: "settings.actionButtonSide" in identifiers(data))
        frame = next(e["frame"] for e in data["entries"] if e.get("uniqueId") == "settings.actionButtonSide")
        # sim-use exposes this native segmented control as one TabGroup. Its two
        # visible segments are left/right; resolve the live frame before tapping.
        run.command(["sim-use", "tap", "-x", str(frame["x"] + frame["width"] * (0.25 if side == "left" else 0.75)),
                     "-y", str(frame["y"] + frame["height"] / 2), "--device", args.device])

    def check_side(data, side, snippet_id):
        add = next(e["frame"] for e in data["entries"] if e.get("uniqueId") == "library.add")
        row = next(e["frame"] for e in data["entries"] if e.get("uniqueId") == "snippet." + snippet_id)
        copy = next(e["frame"] for e in data["entries"] if e.get("uniqueId") == "copy." + snippet_id)
        if side == "left":
            valid = copy["x"] < row["x"] and add["x"] < row["x"] + row["width"] / 2
        else:
            valid = copy["x"] >= row["x"] + row["width"] - 1 and add["x"] > row["x"] + row["width"] / 2
        if not valid or min(copy["width"], copy["height"], add["width"], add["height"]) < 44:
            raise VerificationError("Action position or minimum target size is incorrect: " + side)

    def search_fields(data):
        return [entry for entry in data["entries"] if entry.get("role") == "TextField"]

    def paste_search(text):
        data = wait_ui("native-search-field", lambda data: len(search_fields(data)) == 1)
        # The system search field has no app-owned identifier. Resolve its live
        # AX frame immediately before the native edit-menu gesture.
        frame = search_fields(data)[0]["frame"]
        run.command(["sim-use", "paste", "--via-menu",
                     "--target-x", str(frame["x"] + frame["width"] / 2),
                     "--target-y", str(frame["y"] + frame["height"] / 2),
                     "--device", args.device, text])

    def clear_search():
        label("テキストを消去")
        wait_ui("search-cleared", lambda data: not any(
            e.get("label") == "テキストを消去" for e in data["entries"]))

    def close_search():
        label("閉じる")
        wait_ui("search-closed", lambda data: not search_fields(data))

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
        run.tap("more." + row.removeprefix("snippet."))
        time.sleep(0.35)
        run.ui(name)

    def wait_ui(name, predicate):
        for attempt in range(20):
            data = run.ui(f"{name}-{attempt}")
            if predicate(data):
                return data
            time.sleep(0.25)
        raise VerificationError(f"UI did not reach expected state: {name}")

    def background_editor(name):
        before = wait_ui(name + "-before", lambda data: "editor.body" in identifiers(data))
        values = {e["uniqueId"]: e.get("value") for e in before["entries"]
                  if e.get("uniqueId") in ("editor.title", "editor.body")}
        run.command(["sim-use", "button", "home", "--device", args.device])
        wait_ui(name + "-home", lambda data: data.get("appPackage") == "com.apple.springboard")
        run.command([XCRUN, "simctl", "launch", args.device, run.config["bundle_id"]])
        after = wait_ui(name + "-returned", lambda data: "editor.save" in identifiers(data)
                        and "editor.body" in identifiers(data))
        actual = {e["uniqueId"]: e.get("value") for e in after["entries"]
                  if e.get("uniqueId") in values}
        if actual != values:
            raise VerificationError("Editor input changed during background transition: " + name)
        run.screenshot(name)

    try:
        run.setup()
        with run.device_lock():
            run.launch()
            before = wait_ui("before", lambda data: data.get("appPackage") == run.config["bundle_id"]
                             and "navigation.title" in identifiers(data))
            check_navigation_title(before, "一覧")
            filters = {e.get("uniqueId") for e in before["entries"]
                       if e.get("uniqueId", "").startswith("library.filter.")}
            if filters != {"library.filter.all", "library.filter.pinned", "library.filter.drafts"}:
                raise VerificationError("Expected All, Pinned and Drafts filters above the library")
            run.screenshot("before")
            tabs = {e.get("label"): e for e in before["entries"] if e.get("role") == "RadioButton"}
            if set(tabs) != {"一覧", "設定", "検索"} or search_fields(before):
                raise VerificationError("Expected Library, Settings and Search tabs with no search field in Library")
            create_id = "library.add" if "library.add" in identifiers(before) else "library.createFirst"
            if create_id == "library.add":
                add = next(e["frame"] for e in before["entries"] if e.get("uniqueId") == create_id)
                search_tab = tabs["検索"]["frame"]
                if not (44 <= add["width"] <= 60 and 44 <= add["height"] <= 60):
                    raise VerificationError("Create control must remain compact and tappable")
                if (add["y"] + add["height"] > search_tab["y"] or
                        abs(add["x"] + add["width"] - search_tab["x"] - search_tab["width"]) > 8):
                    raise VerificationError("Create must sit above the trailing search button")
            elif create_id not in identifiers(before):
                raise VerificationError("Empty library must expose one labelled creation action")
            with run.recording():
                run.tap(create_id)
                run.ui("new-editor")
                paste("editor.title", title)
                paste("editor.body", body)
                background_editor("library-editor-background")
                run.tap("editor.close")
                pending = wait_ui("draft-kept", lambda data: any(
                    entry.get("uniqueId", "").startswith("draft.") and entry.get("label", "").endswith(title)
                    for entry in data["entries"]))
                drafts = [entry["uniqueId"] for entry in pending["entries"]
                          if entry.get("uniqueId", "").startswith("draft.") and entry.get("label", "").endswith(title)]
                if len(drafts) != 1:
                    raise VerificationError("Expected exactly one draft for this run's title")
                run.tap("library.filter.drafts")
                filtered_drafts = wait_ui("draft-filter", lambda data: drafts[0] in identifiers(data)
                                         and not any(e.get("uniqueId", "").startswith("snippet.") for e in data["entries"]))
                run.screenshot("draft-filter")
                run.tap(drafts[0])
                wait_ui("draft-resumed", lambda data: "editor.body" in identifiers(data))
                run.screenshot("resumed-draft")
                # Native AX text can omit surrounding whitespace. Validate the
                # resumed bytes through save/copy below, not a display value.
                run.tap("editor.save")
                wait_ui("saved", lambda data: "library.add" in identifiers(data) or "library.createFirst" in identifiers(data))
                remaining_drafts = run.ui("saved-draft-removed")
                if drafts[0] in identifiers(remaining_drafts):
                    raise VerificationError("Saved draft remains in the Drafts filter")
                run.tap("library.filter.all")
                wait_ui("all-filter", lambda data: any(e.get("uniqueId", "").startswith("snippet.") for e in data["entries"]))
                tab("検索")
                focused = wait_ui("search-focused", lambda data: "Search" in identifiers(data))
                check_navigation_title(focused, "検索")
                if "search.prompt" not in identifiers(focused) or any(
                        e.get("uniqueId", "").startswith("snippet.") for e in focused["entries"]):
                    raise VerificationError("Empty search must show guidance instead of saved rows")
                if "library.add" in identifiers(focused):
                    raise VerificationError("Create obscures the active search input")
                # Identify this run's item through a unique Japanese search term.
                # A visible-row difference can mistake an older, newly revealed row
                # for the saved item when the keyboard or existing pins change layout.
                paste_search(title)
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
                run.screenshot("search-keyboard")
                run.tap("Search")
                wait_ui("search-dismissed", lambda data: row in identifiers(data)
                        and "Search" not in identifiers(data) and "library.add" in identifiers(data))
                time.sleep(0.35)
                run.tap(row)
                wait_ui("reopened", lambda data: "editor.close" in identifiers(data))
                edited_title = title + " 編集済み"
                edited_body = "更新された本文\n" + body
                paste("editor.title", edited_title, replace=True)
                paste("editor.body", edited_body, replace=True)
                background_editor("search-editor-background")
                run.tap("editor.save")
                wait_ui("edited", lambda data: any(e.get("uniqueId") == row
                        and e.get("label") == edited_title for e in data["entries"]))
                run.tap("copy." + snippet_id)
                if run.command([XCRUN, "simctl", "pbpaste", args.device], "edited-copy") != edited_body:
                    raise VerificationError("The edited row copied stale or altered text")
                run.screenshot("edited")
                menu(row, "pin-menu")
                label("ピン留め")
                wait_ui("pinned", lambda data: any(e.get("uniqueId") == row and "ピン留め" in e.get("label", "") for e in data["entries"]))
                close_search()
                tab("一覧")
                library = wait_ui("returned-library", lambda data: row in identifiers(data))
                if search_fields(library):
                    raise VerificationError("Library must remain separate from Search")
                run.screenshot("pinned")
                run.tap("library.filter.pinned")
                pins = wait_ui("pinned-filter", lambda data: row in identifiers(data)
                               and not any(e.get("uniqueId", "").startswith("draft.") for e in data["entries"]))
                if any(e.get("uniqueId", "").startswith("snippet.") and "ピン留め" not in e.get("label", "") for e in pins["entries"]):
                    raise VerificationError("Pinned filter contains an unpinned item")
                run.screenshot("pinned-filter")
                menu(row, "unpin-filter-menu")
                label("ピン留めを外す")
                wait_ui("unpinned-filter", lambda data: row not in identifiers(data))
                tab("検索")
                wait_ui("independent-search-focused", lambda data: "Search" in identifiers(data))
                # Native search cancellation clears its query. Search this item
                # again while the library remains scoped to pinned snippets.
                paste_search(title)
                wait_ui("independent-search", lambda data: row in identifiers(data))
                run.tap("Search")
                wait_ui("independent-search-submitted", lambda data: "Search" not in identifiers(data))
                menu(row, "repin-filter-menu")
                label("ピン留め")
                wait_ui("repinned-filter", lambda data: any(e.get("uniqueId") == row and "ピン留め" in e.get("label", "") for e in data["entries"]))
                close_search()
                tab("一覧")
                wait_ui("pinned-filter-returned", lambda data: row in identifiers(data))
                run.tap("library.filter.all")
                wait_ui("all-filter-restored", lambda data: row in identifiers(data))
                tab("設定")
                settings = wait_ui("settings", lambda data: "settings.about" in identifiers(data))
                check_navigation_title(settings, "設定")
                run.screenshot("settings")
                choose_side("left")
                run.ui("left-setting")
                tab("一覧")
                left = wait_ui("left-library", lambda data: row in identifiers(data))
                check_side(left, "left", snippet_id)
                run.screenshot("left-library")
                run.tap("copy." + snippet_id)
                if run.command([XCRUN, "simctl", "pbpaste", args.device], "left-copy") != edited_body:
                    raise VerificationError("Left-side copy changed the text")
                run.tap("library.add")
                wait_ui("left-editor", lambda data: "editor.close" in identifiers(data))
                run.tap("editor.close")
                wait_ui("left-editor-closed", lambda data: "library.add" in identifiers(data))
                run.command([XCRUN, "simctl", "launch", "--terminate-running-process", args.device,
                             run.config["bundle_id"]], "restart-for-preference")
                run.wait_for_launch()
                left = wait_ui("left-after-restart", lambda data: row in identifiers(data))
                check_side(left, "left", snippet_id)
                tab("設定")
                wait_ui("settings-after-restart", lambda data: "settings.about" in identifiers(data))
                choose_side("right")
                run.ui("right-setting")
                tab("一覧")
                right = wait_ui("right-library", lambda data: row in identifiers(data))
                check_side(right, "right", snippet_id)
                run.screenshot("right-library")
                tab("検索")
                wait_ui("search-refocused", lambda data: "Search" in identifiers(data))
                paste_search(title)
                wait_ui("pin-search-result", lambda data: row in identifiers(data))
                run.tap("Search")
                wait_ui("pin-search-submitted", lambda data: "Search" not in identifiers(data))
                menu(row, "delete-menu")
                run.tap("delete." + snippet_id)
                deleted = wait_ui("deleted", lambda data: "library.undo" in identifiers(data))
                if row in identifiers(deleted):
                    raise VerificationError("Deleted row is still visible")
                # The notice expires after six seconds. A second AX traversal
                # can outlast it; tap the alias from the state just observed.
                undo = next(entry for entry in deleted["entries"] if entry.get("uniqueId") == "library.undo")
                run.command(["sim-use", "tap", "@" + str(undo["aliases"]["at"]), "--device", args.device])
                wait_ui("restored", lambda data: row in identifiers(data))
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
                clear_search()
                paste_search("該当なし-" + uuid4().hex)
                wait_ui("search-empty", lambda data: not any(
                    e.get("uniqueId", "").startswith("snippet.") for e in data["entries"]))
                run.screenshot("search-empty")
                close_search()
                finished = wait_ui("finished", lambda data: row in identifiers(data)
                                   and not search_fields(data))
                if any(entry.get("uniqueId", "").startswith("draft.")
                       and entry.get("label", "").endswith(edited_title) for entry in finished["entries"]):
                    raise VerificationError("Discarded draft is still listed")
                menu(row, "trash-delete-menu")
                run.tap("delete." + snippet_id)
                wait_ui("trash-deleted", lambda data: row not in identifiers(data))
                tab("設定")
                wait_ui("trash-settings", lambda data: "library.trash" in identifiers(data))
                run.tap("library.trash")
                wait_ui("trash-sheet", lambda data: "library.trash.close" in identifiers(data))
                paste_search("該当なし-" + uuid4().hex)
                wait_ui("trash-search-empty", lambda data: any(
                    e.get("label") == "見つかりませんでした" for e in data["entries"]))
                clear_search()
                paste_search(title)
                wait_ui("trash-search-result", lambda data: "restore." + snippet_id in identifiers(data))
                run.tap("Search")
                wait_ui("trash-search-submitted", lambda data: "Search" not in identifiers(data))
                run.screenshot("trash-search")
                run.tap("restore." + snippet_id)
                wait_ui("trash-restored", lambda data: row not in identifiers(data))
                label("閉じる")
                wait_ui("trash-search-closed", lambda data: "library.trash.close" in identifiers(data))
                run.tap("library.trash.close")
                wait_ui("trash-returned", lambda data: "settings.about" in identifiers(data)
                        and "library.trash.close" not in identifiers(data))
                tab("一覧")
                wait_ui("restored-in-library", lambda data: row in identifiers(data))
                run.tap("copy." + snippet_id)
                if run.command([XCRUN, "simctl", "pbpaste", args.device], "trash-restored-copy") != edited_body:
                    raise VerificationError("Trash search/restore changed the snippet's text")
                time.sleep(2.3)
                run.screenshot("finished")
            run.manifest.setdefault("assertions", {}).update({
                "created_id": snippet_id, "search_term": title, "copy_utf8_exact": True, "japanese_search": True,
                "edited_title": edited_title, "edit_same_id": True, "edited_copy_utf8_exact": True,
                "visible_row_menu": True, "pin": True, "delete_absent": True, "undo_same_id": True,
                "kept_draft_resumed": True, "discard_absent": True, "discard_preserves_saved_utf8": True,
                "native_tabs": True, "root_titles_in_navigation_bar": True, "create_above_search": True,
                "create_hidden_while_searching": True, "search_title_visible_during_input": True,
                "empty_search_guidance": True, "top_filters": True,
                "draft_filter_resume_and_save": True, "pinned_filter_unpin_and_search_independent": True,
                "settings_navigation": True, "left_and_right_actions": True, "side_survives_restart": True,
                "empty_search_does_not_filter_all": True,
                "trash_search": True, "trash_restore_same_id_and_utf8": True,
                "data": "Dummy text only; existing snippets are retained",
            })
    except Exception as caught:
        error = repr(caught)
    finally:
        run.finish(error)
    if error:
        raise SystemExit(error)


if __name__ == "__main__":
    main()
