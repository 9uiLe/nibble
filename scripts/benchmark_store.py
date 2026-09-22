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
from ios import select_device, simulator_lock
from ios_project import load_project, PRODUCT_CONFIG
from script_ui import ui


def run(argv):
    return subprocess.run([str(value) for value in argv], check=True, text=True, capture_output=True).stdout


def source_files(paths):
    """Select the storage/editor boundary independently of a revision's directory layout."""
    contracts = {'EditorModel.swift', 'LibraryRequest.swift', 'StorageContracts.swift', 'KeyboardContracts.swift'}
    selected = sorted(path for path in map(Path, paths) if path.suffix == '.swift'
                      and path.parts[:2] == ('app', 'Shared')
                      and (path.parts[2] in {'Domain', 'Persistence'} or path.name in contracts))
    if not selected or 'EditorModel.swift' not in {path.name for path in selected}:
        raise ValueError('Store measurement requires the domain, storage and EditorModel sources')
    if len({path.name for path in selected}) != len(selected):
        raise ValueError('Store measurement source basenames must be unique')
    return selected


def sources(revision=None):
    paths = (run(['git', '-C', ROOT, 'ls-tree', '-r', '--name-only', revision]).splitlines() if revision
             else [path.relative_to(ROOT) for path in (ROOT / 'app/Shared').rglob('*.swift')])
    return {path.as_posix(): subprocess.check_output(['git', '-C', ROOT, 'show', f'{revision}:{path}'])
            if revision else (ROOT / path).read_bytes() for path in source_files(paths)}


def measure(args, output, manifest):
    devices = json.loads(run(['xcrun', 'simctl', 'list', 'devices', '--json']))['devices']
    runtimes = json.loads(run(['xcrun', 'simctl', 'list', 'runtimes', '--json']))['runtimes']
    config = load_project(ROOT, PRODUCT_CONFIG)
    device = select_device(devices, runtimes, args.device, config['minimum_ios'])
    if device['state'] != 'Booted':
        raise ValueError('Boot the dedicated Simulator before measurement')
    sdk = run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path']).strip()
    harness = ROOT / 'validation/StoreBenchmark.swift'
    baseline = run(['git', '-C', ROOT, 'rev-parse', '--verify', args.baseline_ref + '^{commit}']).strip()
    manifest.update(device=device, xcode=run(['xcodebuild', '-version']), baseline_ref=baseline,
                    harness_sha256=hashlib.sha256(harness.read_bytes()).hexdigest())
    (output / 'Benchmark.swift').write_bytes(harness.read_bytes())
    for variant, revision in [('baseline', baseline), ('final', None)]:
        source = output / variant
        source.mkdir()
        hashes = {}
        for path, data in sources(revision).items():
            (source / Path(path).name).write_bytes(data)
            hashes[path] = hashlib.sha256(data).hexdigest()
        binary = output / f'{variant}-benchmark'
        command = ['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-Osize', '-whole-module-optimization',
                   '-swift-version', '6', '-target', f'arm64-apple-ios{config["minimum_ios"]}-simulator', '-sdk', sdk,
                   *sorted(source.glob('*.swift')), output / 'Benchmark.swift', '-o', binary]
        manifest['variants'][variant] = {'optimization': '-Osize', 'sources': hashes, 'command': list(map(str, command))}
        run(command)
    spawn = ['xcrun', 'simctl', 'spawn', args.device]
    seed = output / 'seed.sqlite'
    run([*spawn, output / 'baseline-benchmark', 'seed', seed])
    for index, variant in enumerate(['baseline', 'final', 'final', 'baseline', 'baseline', 'final']):
        database = output / f'sample-{index}.sqlite'
        shutil.copyfile(seed, database)
        result = json.loads(run([*spawn, output / f'{variant}-benchmark', 'measure', database]))
        result.update(index=index, variant=variant)
        manifest['runs'].append(result)
        (output / 'results.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
        ui.message(f'{index + 1}/6: {variant}')
    current = {name: hashlib.sha256(data).hexdigest() for name, data in sources().items()}
    if current != manifest['variants']['final']['sources'] or hashlib.sha256(harness.read_bytes()).hexdigest() != manifest['harness_sha256']:
        raise ValueError('Measurement sources changed during execution')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--baseline-ref", required=True)
    parser.add_argument("--output", type=Path, required=True, help="New artifact directory; never overwrites a run")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    manifest = {'status': 'running', 'variants': {}, 'runs': []}
    try:
        with simulator_lock(args.device):
            measure(args, output, manifest)
        manifest['status'] = 'passed'
    except (Exception, KeyboardInterrupt) as error:
        manifest.update(status='failed', error=str(error) or type(error).__name__)
        raise
    finally:
        (output / 'results.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stderr or str(error))
        raise SystemExit(error.returncode) from error
