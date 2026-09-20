"""Record a repeatable research-only CRUD/search/copy/delete/restore sequence."""
import argparse
import json
import pathlib
import sys
from types import SimpleNamespace

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from ios import Run, XCRUN, expect_text

parser = argparse.ArgumentParser()
parser.add_argument("--device", required=True)
args = parser.parse_args()
run = Run(SimpleNamespace(command="research-ui", device=args.device, configuration="Release",
                          project_config="research/probe/project.json"))
text = "  日本語 か\u3099\n\t👩🏽‍💻 <code>  "
error = None
try:
    run.setup()
    with run.device_lock():
        run.launch()
        container = pathlib.Path(run.command([XCRUN, "simctl", "get_app_container", args.device, run.config["bundle_id"], "data"], "container").strip())
        # Reset only this disposable probe's unsaved new-item draft for repeatable input.
        (container / "Documents/draft-new.json").unlink(missing_ok=True)
        run.manifest["setup"] = "Removed ResearchProbe Documents/draft-new.json only"
        run.save()
        initial = run.ui("initial")
        previous = {e.get("uniqueId") for e in initial["entries"]}
        run.screenshot("initial")
        with run.recording():
            run.tap("probe.add")
            run.ui("editor")
            for target, value in [("probe.title", "検証用の定型文"), ("probe.body", text)]:
                run.command(["sim-use", "paste", "--via-menu", "--target-id", target, "--device", args.device, value])
            # UITextView's accessibility value omits outer whitespace here. The clipboard assertion below checks all bytes.
            expect_text(run.ui("input"), "probe.body", text.strip())
            run.tap("probe.save")
            data = run.ui("saved")
            row = next(e["uniqueId"] for e in data["entries"] if e.get("uniqueId", "").startswith("probe.row.") and e["uniqueId"] not in previous)
            run.command(["sim-use", "paste", "--via-menu", "--target-id", "probe.search", "--device", args.device, "日本"])
            run.ui("search")
            run.tap(row)
            expect_text(run.ui("reopened"), "probe.body", text.strip())
            run.tap("probe.copy")
            copied = run.command([XCRUN, "simctl", "pbpaste", args.device], "clipboard")
            assert copied == text, repr(copied)
            run.ui("copied")
            run.tap("probe.delete")
            data = run.ui("deleted")
            assert not any(e.get("uniqueId") == row for e in data["entries"])
            run.tap("probe.undo")
            data = run.ui("restored")
            assert any(e.get("uniqueId") == row for e in data["entries"])
        run.screenshot("restored")
        run.tap(row)
        run.ui("final-editor")
        run.screenshot("final-editor")
        (run.path / "assertions.json").write_text(json.dumps({"copiedUTF8Exact": True, "deletedAbsent": True,
                                                            "undoRestored": True, "row": row}, indent=2))
except (Exception, KeyboardInterrupt) as caught:
    error = repr(caught)
finally:
    run.finish(error)
if error:
    raise SystemExit(error)
