#!/usr/bin/env python3
"""Compare real store/model sources in iOS 26.5 Simulator processes; no UI timing."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ios import select_device
from script_ui import ui


def run(argv):
    return subprocess.run([str(value) for value in argv], check=True, text=True, capture_output=True).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--baseline-ref", required=True)
    parser.add_argument("--output", type=Path, required=True, help="New artifact directory; never overwrites a run")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "--json"]))["devices"]
    runtimes = json.loads(run(["xcrun", "simctl", "list", "runtimes", "--json"]))["runtimes"]
    device = select_device(devices, runtimes, args.device, "26.0")
    if device["state"] != "Booted":
        raise ValueError("Boot the dedicated Simulator before measurement")
    sdk = run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).strip()
    files = ["Snippet", "Draft", "LibraryRequest", "StorageContracts", "SQLiteDatabase", "SnippetSchema",
             "SnippetQueries", "DraftQueries", "SnippetCommands", "SnippetStore", "EditorModel"]
    harness = ROOT / "validation/StoreBenchmark.swift"
    manifest = {"status": "running", "device": device, "xcode": run(["xcodebuild", "-version"]),
                "baseline_ref": run(["git", "-C", ROOT, "rev-parse", args.baseline_ref]).strip(),
                "harness_sha256": hashlib.sha256(harness.read_bytes()).hexdigest(), "variants": {}, "runs": []}
    (output / "Benchmark.swift").write_bytes(harness.read_bytes())
    for variant, optimization in [("baseline", "-Osize"), ("final", "-Osize")]:
        source = output / variant
        source.mkdir()
        hashes = {}
        for name in files:
            path = f"app/Shared/{name}.swift"
            if variant == "baseline":
                result = subprocess.run(["git", "-C", ROOT, "show", f"{args.baseline_ref}:{path}"], capture_output=True)
                if result.returncode:
                    if name in ["SQLiteDatabase", "SnippetSchema", "StorageContracts", "SnippetQueries", "DraftQueries", "SnippetCommands"]:
                        continue  # Historical revisions predate the connection and query splits.
                    raise RuntimeError(f"Missing baseline source: {path}")
                data = result.stdout
            else:
                data = (ROOT / path).read_bytes()
            (source / f"{name}.swift").write_bytes(data)
            hashes[path] = hashlib.sha256(data).hexdigest()
        binary = output / f"{variant}-benchmark"
        command = ["xcrun", "--sdk", "iphonesimulator", "swiftc", optimization, "-whole-module-optimization",
                   "-swift-version", "6", "-target", "arm64-apple-ios26.0-simulator", "-sdk", sdk,
                   *sorted(source.glob("*.swift")), output / "Benchmark.swift", "-o", binary]
        run(command)
        manifest["variants"][variant] = {"optimization": optimization, "sources": hashes, "command": list(map(str, command))}
    spawn = ["xcrun", "simctl", "spawn", args.device]
    seed = output / "seed.sqlite"
    run([*spawn, output / "baseline-benchmark", "seed", seed])
    for index, variant in enumerate(["baseline", "final", "final", "baseline", "baseline", "final"]):
        database = output / f"sample-{index}.sqlite"
        shutil.copyfile(seed, database)
        result = json.loads(run([*spawn, output / f"{variant}-benchmark", "measure", database]))
        result.update(index=index, variant=variant)
        manifest["runs"].append(result)
        (output / "results.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
        ui.message(f"{index + 1}/6: {variant}")
    manifest["status"] = "passed"
    (output / "results.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stderr or str(error))
        raise SystemExit(error.returncode) from error
