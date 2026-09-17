#!/usr/bin/env python3
"""Build pinned, script-free Rive assets; check source/output freshness without Apple tools."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = Path("app/Animations/assets.json")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources(directory):
    return {p.relative_to(directory).as_posix(): digest(p)
            for p in sorted(directory.rglob("*")) if p.is_file()
            and "build" not in p.relative_to(directory).parts
            and p.suffix not in (".md",) and p.name != ".gitignore"}


def structure(directory, asset):
    nodes = [node for path in sorted(directory.rglob("*.rml")) for node in ET.parse(path).iter()]
    ids = {node.get("id"): node for node in nodes if node.get("id")}
    if len(ids) != sum(node.get("id") is not None for node in nodes):
        raise ValueError("Duplicate RML IDs")
    def named(tag, name):
        matches = [n for n in nodes if n.tag == tag and n.get("name") == name]
        if len(matches) != 1:
            raise ValueError(f"Expected one {tag}: {name}")
        return matches[0]
    artboard = named("Artboard", asset["artboard"])
    machine = named("StateMachine", asset["state_machine"])
    model = named("ViewModel", asset["view_model"])
    if machine not in list(artboard) or artboard.get("defaultStateMachineId") != machine.get("id"):
        raise ValueError("Artboard must select the contracted state machine")
    if artboard.get("viewModelId") != model.get("id"):
        raise ValueError("Artboard must select the contracted view model")
    instance = ids.get(model.get("defaultInstanceId"))
    if instance is None or instance not in list(model) or instance.get("exports") != "true":
        raise ValueError("View model must export its default instance")
    for name, kind in asset["properties"].items():
        matches = [n for n in model if n.tag == "ViewModelProperty" + kind and n.get("name") == name]
        if len(matches) != 1:
            raise ValueError(f"Missing or changed property: {name} ({kind})")
        if not any(n.get("viewModelPropertyId") == matches[0].get("id") for n in instance):
            raise ValueError(f"Missing initial value: {name}")
    prohibited = {"StateMachineBool", "StateMachineNumber", "StateMachineTrigger"}
    if any(n.tag in prohibited or "Script" in n.tag or "Shader" in n.tag for n in nodes):
        raise ValueError("This pipeline accepts Data Binding and unsigned, script-free assets only")


def check_asset(root, asset):
    directory = root / asset["source"]
    structure(directory, asset)
    if sources(directory) != asset.get("sources_sha256"):
        raise ValueError(f"Sources changed: rebuild {asset['source']}")
    output = root / asset["output"]
    if not output.is_file() or digest(output) != asset.get("output_sha256"):
        raise ValueError(f"Missing or changed generated file: {asset['output']}")


def build_asset(root, asset, cli):
    directory = root / asset["source"]
    structure(directory, asset)
    for mode in ("--verify", "--once"):
        completed = subprocess.run([cli, str(directory), mode, "--format=json"],
                                   text=True, capture_output=True, check=True, timeout=90)
        report = json.loads(completed.stdout)
        if not report.get("success") or report.get("errors") or report.get("warnings"):
            raise ValueError(f"Rive {mode} reported problems: {report}")
    generated = Path(report["data"]["riv"])
    if not generated.is_absolute():
        generated = root / generated
    output = root / asset["output"]
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(generated, output)
    asset["sources_sha256"] = sources(directory)
    asset["output_sha256"] = digest(output)
    check_asset(root, asset)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "build"))
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    root = args.root.resolve()
    path = root / MANIFEST
    try:
        manifest = json.loads(path.read_text())
        if manifest["schema"] != 1:
            raise ValueError("Unsupported manifest schema")
        if args.command == "build":
            cli = shutil.which("rive")
            if not cli:
                raise ValueError("Run in the Nix shell on Apple Silicon macOS")
            version = subprocess.check_output([cli, "--version"], text=True, timeout=10).strip().removeprefix("rive ")
            if version != manifest["cli_version"]:
                raise ValueError(f"Expected CLI {manifest['cli_version']}, got {version}")
            for asset in manifest["assets"]:
                build_asset(root, asset, cli)
            path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        for asset in manifest["assets"]:
            check_asset(root, asset)
        print(f"Rive: {len(manifest['assets'])} source/output contracts verified")
    except (OSError, ValueError, KeyError, ET.ParseError, subprocess.SubprocessError) as error:
        print(f"Rive validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
