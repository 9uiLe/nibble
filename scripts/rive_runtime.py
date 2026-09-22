#!/usr/bin/env python3
"""Prepare or verify the Rive rendering runtime from locked, unsigned build inputs."""

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

from script_ui import ui

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'artifacts/RiveRuntime'
DEFINITION = ROOT / 'runtime/rive'
PATCH = DEFINITION / 'drawable-acquisition.patch'


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def package_hashes(path):
    return {p.relative_to(path).as_posix(): sha256(p) for p in sorted(path.rglob('*'))
            if p.is_file() and p.relative_to(path).as_posix() != 'build-manifest.json'}


def definition_hashes(path=DEFINITION):
    """Every executable definition participates in build and evidence identity."""
    return {p.relative_to(path).as_posix(): sha256(p) for p in sorted(path.rglob('*'))
            if p.is_file() and p.suffix != '.md'}


def cache_valid(path, identity):
    try:
        manifest = json.loads((path / 'build-manifest.json').read_text())
        files = manifest['files_sha256']
        return (manifest['inputs'] == identity and 'Package.swift' in files
                and 'RiveRuntime.xcframework/Info.plist' in files
                and files == package_hashes(path))
    except (OSError, ValueError, KeyError, TypeError):
        return False


def writable_copy(source, target):
    shutil.copytree(source, target, symlinks=True)
    for base, _, files in os.walk(target):
        os.chmod(base, 0o755)
        for name in files:
            path = Path(base) / name
            if not path.is_symlink():
                os.chmod(path, path.stat().st_mode | 0o200)


def build(identity, sources, destination):
    definition = json.loads((DEFINITION / 'build.json').read_text())
    runs = ROOT / 'artifacts/rive-runtime'
    runs.mkdir(parents=True, exist_ok=True)
    run = runs / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:6])
    run.mkdir()
    (run / 'inputs.json').write_text(json.dumps(identity, indent=2) + '\n')
    environment = os.environ.copy()

    def command(name, argv, cwd=ROOT):
        with ui.step(name), (run / (name + '.stdout.log')).open('w') as out, \
                (run / (name + '.stderr.log')).open('w') as err:
            result = subprocess.run([str(v) for v in argv], cwd=cwd, env=environment,
                                    stdin=subprocess.DEVNULL, stdout=out, stderr=err, timeout=1800)
            if result.returncode:
                raise RuntimeError(f'{name} failed; inspect {run}')

    source = run / 'source'
    with ui.step('prepare-rive-sources'):
        writable_copy(sources / 'rive-ios', source)
        core = source / 'submodules/rive-runtime'
        core.rmdir()  # Empty gitlink from the pinned Apple source archive.
        writable_copy(sources / 'rive-runtime', core)
        dependencies = run / 'dependencies'
        dependencies.mkdir()
        for item in sources.iterdir():
            if item.name not in {'rive-ios', 'rive-runtime'}:
                (dependencies / item.name).symlink_to(item.resolve(), target_is_directory=True)
        shutil.copy2(DEFINITION / 'dependency.lua', core / 'build/dependency.lua')
        premake_tag = 'v' + definition['premake_version']
        premake = core / ('build/dependencies/premake-core/bin/' + premake_tag + '_release')
        premake.mkdir(parents=True)
        (premake / 'premake5').symlink_to(shutil.which('premake5'))
        localbin = run / 'bin'
        localbin.mkdir()
        # The upstream Apple script uses BSD sed's -i syntax.
        (localbin / 'sed').symlink_to('/usr/bin/sed')
        environment.update(DEPENDENCIES=str(dependencies), RIVE_PREMAKE_TAG=premake_tag)
        environment['PATH'] = str(localbin) + ':' + str(core / 'build') + ':' + environment['PATH']
    command('patch-runtime', ['git', 'apply', '--check', PATCH], source)
    command('apply-runtime', ['git', 'apply', PATCH], source)
    frameworks = []
    for platform in definition['platforms']:
        name = platform['name']
        command('core-' + name, ['bash', 'scripts/build.rive.sh', name, 'release'], source)
        includes = source / 'dependencies/includes'
        writable_copy(dependencies / 'luigi-rosso_luau_rive_0_734/VM/include', includes / 'luau')
        (includes / 'miniaudio').mkdir()
        shutil.copy2(dependencies / 'rive-app_miniaudio_rive_changes_5/miniaudio.h', includes / 'miniaudio/miniaudio.h')
        archive = run / (name + '.xcarchive')
        command('framework-' + name, ['/usr/bin/xcodebuild', 'archive', '-project', 'RiveRuntime.xcodeproj',
                '-scheme', 'RiveRuntime', '-configuration', 'Release', '-destination', 'generic/platform=' + platform['destination'],
                '-archivePath', archive, '-derivedDataPath', run / 'DerivedData', 'SKIP_INSTALL=NO',
                'BUILD_LIBRARY_FOR_DISTRIBUTION=YES', 'CODE_SIGNING_ALLOWED=NO',
                'MARKETING_VERSION=' + definition['version'], 'DEBUG_INFORMATION_FORMAT=dwarf-with-dsym'], source)
        frameworks += ['-framework', archive / 'Products/Library/Frameworks/RiveRuntime.framework',
                       '-debug-symbols', archive / 'dSYMs/RiveRuntime.framework.dSYM']
    package = run / 'package'
    package.mkdir()
    command('xcframework', ['/usr/bin/xcodebuild', '-create-xcframework', *frameworks,
                           '-output', package / 'RiveRuntime.xcframework'])
    shutil.copy2(DEFINITION / 'Package.swift', package / 'Package.swift')
    manifest = {'inputs': identity, 'run': str(run.relative_to(ROOT)), 'files_sha256': package_hashes(package)}
    (package / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    if destination.exists():
        destination.rename(run / 'previous-package')
    package.rename(destination)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('prepare', 'check'),
                        help='Build missing inputs, or verify an existing runtime without building')
    args = parser.parse_args()
    try:
        if sys.platform != 'darwin' or not os.environ.get('NIBBLE_RIVE_SOURCES'):
            raise RuntimeError('Run on the local Mac through nix develop')
        sources = Path(os.environ['NIBBLE_RIVE_SOURCES'])
        definition = json.loads((DEFINITION / 'build.json').read_text())
        xcode = subprocess.check_output(['/usr/bin/xcodebuild', '-version'], text=True).strip()
        premake = subprocess.check_output(['premake5', '--version'], text=True).strip()
        if not premake.endswith(definition['premake_version']):
            raise RuntimeError('Use the Premake version selected by runtime/rive/build.json')
        identity = {'sources': {p.name: str(p.resolve()) for p in sorted(sources.iterdir())},
                    'definition_sha256': definition_hashes(), 'builder_sha256': sha256(Path(__file__)),
                    'xcode': xcode, 'premake': premake}
        PACKAGE.parent.mkdir(parents=True, exist_ok=True)
        with (PACKAGE.parent / 'rive-runtime.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            cached = cache_valid(PACKAGE, identity)
            if args.command == 'check' and not cached:
                raise RuntimeError('Rive runtime is missing or stale; run scripts/rive_runtime.py prepare')
            manifest = json.loads((PACKAGE / 'build-manifest.json').read_text()) if cached else build(identity, sources, PACKAGE)
        print(json.dumps({'package': str(PACKAGE.relative_to(ROOT)), 'cached': cached, 'manifest': manifest}))
        ui.result(True, 'Rive rendering runtime is ready')
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        ui.message(str(error), level='error')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
