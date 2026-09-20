"""Typecheck the exact API probe with iOS 26.0 availability and extension restrictions."""
import json
import pathlib
import subprocess
import sys
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from script_ui import ui

OUT = ROOT / "artifacts/research/sdk" / uuid.uuid4().hex
OUT.mkdir(parents=True, exist_ok=False)
results = []
for sdk, target in [("iphonesimulator", "arm64-apple-ios26.0-simulator"), ("iphoneos", "arm64-apple-ios26.0")]:
    sdk_path = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
    for extension in [False, True]:
        argv = ["xcrun", "swiftc", "-typecheck", "-parse-as-library", "-swift-version", "6",
                "-strict-concurrency=complete", "-target", target, "-sdk", sdk_path,
                str(ROOT / "research/probe/ResearchProbe/SDKCompileProbe.swift")]
        if extension:
            argv.append("-application-extension")
        result = subprocess.run(argv, capture_output=True, text=True)
        name = f"{sdk}-{'extension' if extension else 'app'}"
        (OUT / f"{name}.log").write_text(result.stdout + result.stderr)
        results.append({"case": name, "argv": argv, "exit": result.returncode})
        ui.result(result.returncode == 0, name)
(OUT / "results.json").write_text(json.dumps(results, indent=2))
print(json.dumps({"results": str(OUT / "results.json"), "passed": all(result["exit"] == 0 for result in results)}))
raise SystemExit(any(result["exit"] for result in results))
