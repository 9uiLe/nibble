#!/usr/bin/env python3
"""Verify adaptive native navigation, forms and guidance on the selected Simulator."""
import argparse
from contextlib import ExitStack
import time
from types import SimpleNamespace

from check_about_ui import read_setting_topic
from check_controls_ui import assert_adaptive_text
from ios import simulator_lock, XCRUN, VerificationError
from product_ui import WorkspaceRun as Run, identifiers, workspace_entry, workspace_visible


MODES = (("default", "large", "disabled"),
         ("accessibility", "accessibility-extra-extra-extra-large", "enabled"))


def visible_controls(data, expected):
    found = {}
    for identifier in expected:
        entry = workspace_entry(data, identifier)
        if not workspace_visible(data, entry):
            raise VerificationError("Control is absent or clipped: " + identifier)
        found[identifier] = dict(entry["frame"])
    return found


def capture_controls(run, mode, screen, expected):
    observations = run.manifest.setdefault("adaptive_layout", {}).setdefault(mode, {}).setdefault(screen, {})
    for identifier in expected:
        # A Form may legitimately need separate scroll positions for each field.
        data = run.reveal_workspace(identifier)
        observations.update(visible_controls(data, (identifier,)))
        run.screenshot(mode + "-" + screen + "-" + identifier.replace(".", "-"))
    return observations


def exercise_interface(run, option):
    guidance = run.manifest.setdefault("adaptive_guidance", {})
    for mode, size, contrast in MODES:
        option("content_size", size)
        option("increase_contrast", contrast)
        run.workspace()
        capture_controls(run, mode, "workspace", ("workspace.search", "workspace.filter",
                                                  "workspace.create", "workspace.settings"))
        run.tap("workspace.create")
        run.wait_ui(mode + "-editor-open", lambda data: {"workspace.editor.close", "workspace.editor.save"}
                    .issubset(identifiers(data)))
        capture_controls(run, mode, "editor", ("workspace.editor.title", "workspace.editor.body",
                                               "workspace.editor.variables", "workspace.editor.checkpoint",
                                               "workspace.editor.discard", "workspace.editor.save",
                                               "workspace.editor.close"))
        run.tap("workspace.editor.close")
        run.wait_ui(mode + "-editor-closed", lambda data: "workspace.create" in identifiers(data)
                    and "workspace.editor.close" not in identifiers(data))
        for topic in ("workspace.settings.copyGuide", "workspace.settings.keyboardGuide",
                      "workspace.settings.privacy"):
            run.workspace()
            run.open_settings()
            guidance.setdefault(mode, {})[topic] = read_setting_topic(run, topic)
        capture_controls(run, mode, "settings", ("workspace.settings.close", "workspace.trash"))
        run.tap("workspace.trash")
        run.wait_ui(mode + "-trash-open", lambda data: "BackButton" in identifiers(data))
        capture_controls(run, mode, "trash", ("BackButton",))
        run.workspace()
        capture_controls(run, mode, "returned-workspace", ("workspace.create", "workspace.settings"))
    assert_adaptive_text(guidance["default"]["workspace.settings.copyGuide"],
                         guidance["accessibility"]["workspace.settings.copyGuide"])
    run.manifest["assertions"] = {
        "workspace_navigation_reachable_in_both_text_modes": True,
        "editor_form_controls_reachable_by_scroll_in_both_text_modes": True,
        "guidance_readable_to_the_end_in_both_text_modes": True,
        "standard_guidance_height_increases_with_system_text_size": True,
        "trash_route_returns_to_workspace_in_both_text_modes": True,
        "scope": "Observed navigation, form controls and guidance; not Japanese IME, output bytes or external delivery acceptance.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    args = parser.parse_args()
    # Retain the catalog/evidence identity while checking adaptive product behavior.
    run = Run(SimpleNamespace(command="fixed-interface", device=args.device,
                              configuration="Release", project_config="app/project.json"))
    original, error = {}, None
    contexts = ExitStack()

    def option(name, value):
        run.command([XCRUN, "simctl", "ui", args.device, name, value])
        observed = run.command([XCRUN, "simctl", "ui", args.device, name]).strip()
        if observed.casefold() != value.casefold():
            raise VerificationError(f"{name}: requested {value}, observed {observed}")
        time.sleep(0.5)

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
            exercise_interface(run, option)
    except (Exception, KeyboardInterrupt) as caught:
        error = caught
    finally:
        for name, value in original.items():
            try:
                option(name, value)
            except (Exception, KeyboardInterrupt) as caught:
                run.manifest.setdefault("setting_restore_errors", []).append(repr(caught))
                error = error or caught
        contexts.close()
        run.finish(error)
    if error is not None:
        raise SystemExit(repr(error))


if __name__ == "__main__":
    main()
