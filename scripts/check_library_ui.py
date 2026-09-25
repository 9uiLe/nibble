#!/usr/bin/env python3
"""Exercise the shipping app on an explicitly selected iOS 26.5 Simulator."""

import argparse
import json
import time
from types import SimpleNamespace
from uuid import uuid4

from ios import simulator_lock, XCRUN, VerificationError
from product_ui import ProductRun as Run, identifiers


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    args = parser.parse_args()
    run = Run(SimpleNamespace(command="library-ui", device=args.device, configuration="Release",
                              project_config="app/project.json"))
    body = "  日本語 か\u3099\n\t👩🏽‍💻 <code>  "
    title = "日本語コピー " + uuid4().hex[:8]
    error = None

    def label(text):
        run.command(["sim-use", "tap", "--label", text, "--element-type", "Button",
                     "--wait-timeout", "5", "--device", args.device])

    def check_navigation_title(data, title):
        headings = [e["frame"] for e in data["entries"]
                    if e.get("uniqueId") == "navigation.title"
                    and e.get("role") == "Heading" and e.get("label") == title]
        # The top safe area differs between Home-button and notched devices.
        if not headings or not any(frame["x"] < data["screen"]["width"] / 4
                                   and 0 <= frame["y"] < 120 and frame["width"] >= 32 for frame in headings):
            raise VerificationError("Root heading must be leading below the top safe area: " + title)
        return headings[0]

    def check_actions(data, snippet_id):
        add = next(e["frame"] for e in data["entries"] if e.get("uniqueId") == "library.add")
        row = next(e["frame"] for e in data["entries"] if e.get("uniqueId") == "snippet." + snippet_id)
        copy = next(e["frame"] for e in data["entries"] if e.get("uniqueId") == "copy." + snippet_id)
        trailing = copy["x"] >= row["x"] + row["width"] - 1
        if not trailing or min(copy["width"], copy["height"]) < 44:
            raise VerificationError("Copy must stay trailing with a minimum 44pt target")
        if add["height"] < 48 or add["width"] < data["screen"]["width"] - 48:
            raise VerificationError("Create must remain a full-width bottom action")

    def search_fields(data):
        return [entry for entry in data["entries"] if entry.get("role") == "TextField"]

    def search_active(data):
        return "search.done" in identifiers(data) or "Search" in identifiers(data)

    def submit_search():
        data = run.ui("before-search-submit")
        if "search.done" in identifiers(data):
            run.tap("search.done")
        elif "Search" in identifiers(data):
            run.tap("Search")
        else:
            # Native search has no app-owned dismiss button. Return also works
            # when the simulator hides the software keyboard.
            run.command(["sim-use", "ios", "key", "40", "--device", args.device])

    def enter_search(text):
        data = run.wait_ui("native-search-field", lambda data: len(search_fields(data)) == 1)
        if "search.clear" in identifiers(data):
            run.tap("search.clear")
            data = run.wait_ui("query-cleared-for-paste", lambda d: "search.clear" not in identifiers(d))
        # Resolve the live AX frame for both app search and the deleted-items search field.
        frame = search_fields(data)[0]["frame"]
        x, y = frame["x"] + frame["width"] / 2, frame["y"] + frame["height"] / 2
        run.paste_text(text, ["--target-x", str(x), "--target-y", str(y)],
                       lambda applied: any(text in (field.get("value") or "")
                                           for field in search_fields(applied)), name="search-paste")

    def clear_search():
        data = run.ui("before-clear-search")
        if "search.clear" in identifiers(data):
            run.tap("search.clear")
            run.wait_ui("search-cleared", lambda d: "search.clear" not in identifiers(d))
        else:
            label("テキストを消去")
            run.wait_ui("search-cleared", lambda d: not any(e.get("label") == "テキストを消去" for e in d["entries"]))

    def close_search():
        data = run.ui("before-search-done")
        if "search.done" in identifiers(data):
            run.tap("search.done")
        run.wait_ui("search-closed", lambda d: "library.add" in identifiers(d) and not search_active(d))

    def menu(row, name):
        run.tap("more." + row.removeprefix("snippet."))
        time.sleep(0.35)
        run.ui(name)

    def background_editor(name):
        before = run.wait_ui(name + "-before", lambda data: "editor.body" in identifiers(data))
        values = {e["uniqueId"]: e.get("value") for e in before["entries"]
                  if e.get("uniqueId") in ("editor.title", "editor.body")}
        run.command(["sim-use", "button", "home", "--device", args.device])
        run.wait_ui(name + "-home", lambda data: data.get("appPackage") == "com.apple.springboard")
        run.command([XCRUN, "simctl", "launch", args.device, run.config["bundle_id"]])
        after = run.wait_ui(name + "-returned", lambda data: "editor.save" in identifiers(data)
                        and "editor.body" in identifiers(data))
        actual = {e["uniqueId"]: e.get("value") for e in after["entries"]
                  if e.get("uniqueId") in values}
        if actual != values:
            raise VerificationError("Editor input changed during background transition: " + name)
        run.screenshot(name)

    try:
        run.setup()
        with simulator_lock(args.device):
            run.launch()
            before = run.wait_ui("before", lambda data: data.get("appPackage") == run.config["bundle_id"]
                             and {"navigation.title", "search.field", "navigation.settings", "library.add"} <= identifiers(data))
            library_heading = check_navigation_title(before, "nibble")
            filters = {e.get("uniqueId") for e in before["entries"]
                       if e.get("uniqueId", "").startswith("library.filter.")}
            if filters != {"library.filter.all", "library.filter.pinned", "library.filter.drafts"}:
                raise VerificationError("Expected All, Pinned and Drafts filters above the library")
            run.screenshot("before")
            if len(search_fields(before)) != 1 or 'search.done' in identifiers(before):
                raise VerificationError("Workspace must expose search without opening the keyboard")
            create_id = "library.add"
            add = next(e["frame"] for e in before["entries"] if e.get("uniqueId") == create_id)
            if add["height"] < 48 or add["width"] < before["screen"]["width"] - 48 or add["y"] < before["screen"]["height"] * .7:
                raise VerificationError("Creation must remain full-width at the bottom")
            with run.recording():
                run.tap(create_id)
                run.wait_ui("new-editor", lambda data: "editor.body" in identifiers(data)
                        and "editor.keyboard.dismiss" in identifiers(data))
                run.paste_editor("editor.title", title)
                run.paste_editor("editor.body", body)
                background_editor("library-editor-background")
                run.tap("editor.close")
                pending = run.wait_ui("draft-kept", lambda data: any(
                    entry.get("uniqueId", "").startswith("draft.") and entry.get("label", "").endswith(title)
                    for entry in data["entries"]))
                drafts = [entry["uniqueId"] for entry in pending["entries"]
                          if entry.get("uniqueId", "").startswith("draft.") and entry.get("label", "").endswith(title)]
                if len(drafts) != 1:
                    raise VerificationError("Expected exactly one draft for this run's title")
                run.tap("library.filter.drafts")
                filtered_drafts = run.wait_ui("draft-filter", lambda data: drafts[0] in identifiers(data)
                                         and not any(e.get("uniqueId", "").startswith("snippet.") for e in data["entries"]))
                run.screenshot("draft-filter")
                run.tap(drafts[0])
                run.wait_ui("draft-resumed", lambda data: "editor.body" in identifiers(data))
                run.screenshot("resumed-draft")
                # Native AX text can omit surrounding whitespace. Validate the
                # resumed bytes through save/copy below, not a display value.
                run.tap("editor.save")
                run.wait_ui("saved", lambda data: "library.add" in identifiers(data) or "library.createFirst" in identifiers(data))
                remaining_drafts = run.ui("saved-draft-removed")
                if drafts[0] in identifiers(remaining_drafts):
                    raise VerificationError("Saved draft remains in the Drafts filter")
                run.tap("library.filter.all")
                run.wait_ui("all-filter", lambda data: any(e.get("uniqueId", "").startswith("snippet.") for e in data["entries"]))
                run.workspace()
                opened = run.wait_ui("search-opened", lambda data: "search.field" in identifiers(data))
                time.sleep(0.5)
                opened = run.ui("search-no-autofocus")
                if search_active(opened):
                    raise VerificationError("The idle workspace search field must not activate the keyboard")
                run.tap("search.field")
                focused = run.wait_ui("search-focused", search_active)
                search_heading = check_navigation_title(focused, "nibble")
                if abs(search_heading["height"] - library_heading["height"]) > 1:
                    raise VerificationError("Search focus must preserve the workspace heading typography")
                if not any(e.get("uniqueId", "").startswith("snippet.") for e in focused["entries"]):
                    raise VerificationError("Focusing empty search must preserve the browsed collection")
                field = search_fields(focused)[0]["frame"]
                if field["y"] + field["height"] > focused["screen"]["height"] * 0.3:
                    raise VerificationError("Search field must remain at the top of the screen")
                if "library.add" in identifiers(focused):
                    raise VerificationError("Create obscures the active search input")
                # Identify this run's item through a unique Japanese search term.
                # A visible-row difference can mistake an older, newly revealed row
                # for the saved item when the keyboard or existing pins change layout.
                enter_search(title)
                data = run.wait_ui("searched", lambda data: any(
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
                submit_search()
                run.wait_ui("search-dismissed", lambda data: row in identifiers(data)
                        and not search_active(data) and "library.add" in identifiers(data))
                time.sleep(0.35)
                run.tap(row)
                run.wait_ui("reopened", lambda data: "editor.close" in identifiers(data))
                edited_title = title + " 編集済み"
                edited_body = "更新された本文\n" + body
                run.paste_editor("editor.title", edited_title, replace=True)
                run.paste_editor("editor.body", edited_body, replace=True)
                background_editor("search-editor-background")
                run.tap("editor.save")
                run.wait_ui("edited", lambda data: any(e.get("uniqueId") == row
                        and e.get("label") == edited_title for e in data["entries"]))
                run.tap("copy." + snippet_id)
                if run.command([XCRUN, "simctl", "pbpaste", args.device], "edited-copy") != edited_body:
                    raise VerificationError("The edited row copied stale or altered text")
                run.screenshot("edited")
                menu(row, "pin-menu")
                label("ピン留め")
                run.wait_ui("pinned", lambda data: any(e.get("uniqueId") == row and "ピン留め" in e.get("label", "") for e in data["entries"]))
                close_search()
                run.workspace()
                reselected = run.wait_ui("search-reselected", lambda data: "search.field" in identifiers(data))
                if search_active(reselected):
                    raise VerificationError("Reselecting Search must not activate the keyboard")
                close_search()
                run.workspace(clear_query=True)
                library = run.wait_ui("returned-library", lambda data: row in identifiers(data))
                if len(search_fields(library)) != 1:
                    raise VerificationError("Search must remain available in the workspace")
                run.screenshot("pinned")
                run.tap("library.filter.pinned")
                pins = run.wait_ui("pinned-filter", lambda data: row in identifiers(data)
                               and not any(e.get("uniqueId", "").startswith("draft.") for e in data["entries"]))
                if any(e.get("uniqueId", "").startswith("snippet.") and "ピン留め" not in e.get("label", "") for e in pins["entries"]):
                    raise VerificationError("Pinned filter contains an unpinned item")
                run.screenshot("pinned-filter")
                menu(row, "unpin-filter-menu")
                label("ピン留めを解除")
                run.wait_ui("unpinned-filter", lambda data: row not in identifiers(data))
                run.workspace()
                run.wait_ui("independent-search-opened", lambda data: "search.field" in identifiers(data))
                run.tap("search.field")
                run.wait_ui("independent-search-focused", search_active)
                # The query remains independent from the library's pinned filter.
                enter_search(title)
                run.wait_ui("independent-search", lambda data: row in identifiers(data))
                submit_search()
                run.wait_ui("independent-search-submitted", lambda data: not search_active(data))
                menu(row, "repin-filter-menu")
                label("ピン留め")
                run.wait_ui("repinned-filter", lambda data: any(e.get("uniqueId") == row and "ピン留め" in e.get("label", "") for e in data["entries"]))
                close_search()
                run.workspace(clear_query=True)
                run.wait_ui("pinned-filter-returned", lambda data: row in identifiers(data))
                run.tap("library.filter.all")
                run.wait_ui("all-filter-restored", lambda data: row in identifiers(data))
                run.open_settings()
                settings = run.wait_ui("settings", lambda data: "settings.about" in identifiers(data))
                if "BackButton" not in identifiers(settings):
                    raise VerificationError("Settings must have a route back to the workspace")
                run.screenshot("settings")
                run.workspace(clear_query=True)
                library = run.wait_ui("trailing-actions", lambda data: row in identifiers(data))
                check_actions(library, snippet_id)
                run.screenshot("trailing-actions")
                run.tap("copy." + snippet_id)
                if run.command([XCRUN, "simctl", "pbpaste", args.device], "trailing-copy") != edited_body:
                    raise VerificationError("Copy after settings navigation changed the text")
                run.tap("library.add")
                run.wait_ui("trailing-editor", lambda data: "editor.close" in identifiers(data))
                run.tap("editor.close")
                run.wait_ui("trailing-editor-closed", lambda data: "library.add" in identifiers(data))
                run.command([XCRUN, "simctl", "launch", "--terminate-running-process", args.device,
                             run.config["bundle_id"]], "restart-for-actions")
                run.wait_for_launch()
                restarted = run.wait_ui("actions-after-restart", lambda data: row in identifiers(data))
                check_actions(restarted, snippet_id)
                run.screenshot("actions-after-restart")
                run.workspace()
                run.wait_ui("search-opened-again", lambda data: "search.field" in identifiers(data))
                run.tap("search.field")
                run.wait_ui("search-refocused", search_active)
                enter_search(title)
                run.wait_ui("pin-search-result", lambda data: row in identifiers(data))
                submit_search()
                run.wait_ui("pin-search-submitted", lambda data: not search_active(data))
                run.screenshot("library")
                run.tap(row)
                run.wait_ui("editor", lambda data: "editor.body" in identifiers(data))
                run.screenshot("editor")
                run.tap("editor.more")
                run.ui("editor-menu")
                run.tap("editor.discard")
                run.ui("discard-confirmation")
                run.tap("editor.confirmDiscard")
                run.wait_ui("discarded", lambda data: row in identifiers(data)
                        and "editor.body" not in identifiers(data))
                run.tap("copy." + snippet_id)
                if run.command([XCRUN, "simctl", "pbpaste", args.device], "discarded-copy") != edited_body:
                    raise VerificationError("Discard changed the saved snippet's original text")
                clear_search()
                enter_search("該当なし-" + uuid4().hex)
                run.wait_ui("search-empty", lambda data: not any(
                    e.get("uniqueId", "").startswith("snippet.") for e in data["entries"]))
                run.screenshot("search-empty")
                close_search()
                run.workspace(clear_query=True)
                finished = run.wait_ui("finished", lambda data: row in identifiers(data)
                                   and "library.filter.all" in identifiers(data))
                if any(entry.get("uniqueId", "").startswith("draft.")
                       and entry.get("label", "").endswith(edited_title) for entry in finished["entries"]):
                    raise VerificationError("Discarded draft is still listed")
                menu(row, "trash-delete-menu")
                run.tap("delete." + snippet_id)
                run.wait_ui("trash-deleted", lambda data: row not in identifiers(data))
                run.open_settings()
                run.wait_ui("trash-settings", lambda data: "library.trash" in identifiers(data))
                run.tap("library.trash")
                run.wait_ui("trash-destination", lambda data: "BackButton" in identifiers(data)
                            and any(e.get("role") == "Heading" and e.get("label") == "削除した項目"
                                    for e in data["entries"]))
                enter_search("missing-" + uuid4().hex)
                run.wait_ui("trash-search-empty", lambda data: any(
                    e.get("label") == "見つかりませんでした" for e in data["entries"]))
                clear_search()
                enter_search(title.rsplit(" ", 1)[-1])
                run.wait_ui("trash-search-result", lambda data: "restore." + snippet_id in identifiers(data))
                submit_search()
                run.wait_ui("trash-search-submitted", lambda data: "Search" not in identifiers(data))
                run.screenshot("trash-search")
                run.tap("restore." + snippet_id)
                run.wait_ui("trash-restored", lambda data: row not in identifiers(data))
                data = run.wait_ui("trash-restored-notice", lambda data: "library.notice" in identifiers(data))
                notice_frame = next(e["frame"] for e in data["entries"] if e.get("uniqueId") == "library.notice")
                search_frame = next(e["frame"] for e in data["entries"] if e.get("role") == "TextField")
                if notice_frame["y"] + notice_frame["height"] > search_frame["y"] - 8:
                    raise VerificationError("Restoration notice overlaps the native search controls")
                run.screenshot("trash-restored-notice")
                label("閉じる")
                run.wait_ui("trash-search-closed", lambda data: "BackButton" in identifiers(data))
                run.tap("BackButton")
                run.wait_ui("trash-returned", lambda data: "settings.about" in identifiers(data)
                        and "library.trash" in identifiers(data))
                run.workspace(clear_query=True)
                run.wait_ui("restored-in-library", lambda data: row in identifiers(data))
                run.tap("copy." + snippet_id)
                if run.command([XCRUN, "simctl", "pbpaste", args.device], "trash-restored-copy") != edited_body:
                    raise VerificationError("Trash search/restore changed the snippet's text")
                time.sleep(2.3)
                run.screenshot("finished")
            run.manifest.setdefault("assertions", {}).update({
                "created_id": snippet_id, "search_term": title, "copy_utf8_exact": True, "japanese_search": True,
                "edited_title": edited_title, "edit_same_id": True, "edited_copy_utf8_exact": True,
                "visible_row_menu": True, "pin": True,
                "kept_draft_resumed": True, "discard_absent": True, "discard_preserves_saved_utf8": True,
                "unified_workspace": True, "search_does_not_autofocus": True, "stable_workspace_heading": True,
                "create_full_width_at_bottom": True, "search_field_at_top": True,
                "create_hidden_while_searching": True, "search_title_visible_during_input": True,
                "empty_query_preserves_collection": True, "top_filters": True,
                "draft_filter_resume_and_save": True, "pinned_filter_unpin_and_search_independent": True,
                "settings_navigation": True, "trailing_actions": True, "actions_after_restart": True,
                "no_match_search_is_empty": True,
                "trash_search": True, "trash_restore_same_id_and_utf8": True,
                "data": "Dummy text only; existing snippets are retained",
            })
    except (Exception, KeyboardInterrupt) as caught:
        error = repr(caught)
    finally:
        run.finish(error)
    if error:
        raise SystemExit(error)


if __name__ == "__main__":
    main()
