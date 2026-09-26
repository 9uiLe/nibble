#!/usr/bin/env python3
"""Require compiler warnings as errors in repository-owned Xcode builds."""

import argparse
from pathlib import Path
import re

from script_ui import ui


PROJECTS = (
    'app/Nibble.xcodeproj/project.pbxproj',
    'validation/VerificationApp.xcodeproj/project.pbxproj',
)


def project_errors(path):
    lines = path.read_text().splitlines()
    objects = {}
    for line in lines:
        match = re.match(r'\s*([A-F0-9]{24}) = \{', line)
        if match:
            objects[match.group(1)] = line
    projects = [line for line in objects.values() if 'isa = PBXProject;' in line]
    if len(projects) != 1:
        return ['Project must have one PBXProject configuration']
    list_id = re.search(r'buildConfigurationList = ([A-F0-9]{24});', projects[0])
    config_list = objects.get(list_id.group(1), '') if list_id else ''
    ids = re.search(r'buildConfigurations = \(([^)]+)\)', config_list)
    if not ids:
        return ['Project build configurations are missing']
    configurations = [objects.get(identifier.strip(), '') for identifier in ids.group(1).split(',')]
    names = [re.search(r'\bname = (Debug|Release);', line) for line in configurations]
    if len(configurations) != 2 or {match.group(1) for match in names if match} != {'Debug', 'Release'}:
        return ['Project must define Debug and Release build configurations']
    errors = []
    for name, line in zip(names, configurations):
        for setting in ('SWIFT_TREAT_WARNINGS_AS_ERRORS', 'GCC_TREAT_WARNINGS_AS_ERRORS'):
            if not re.search(rf'\b{setting} = "?YES"?;', line):
                errors.append(f'{name.group(1)} must set {setting} to YES')
    return errors


def check(root):
    errors = []
    for name in PROJECTS:
        try:
            errors.extend(f'{name}: {error}' for error in project_errors(root / name))
        except OSError as error:
            errors.append(f'{name}: {error}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    errors = check(args.root.resolve())
    ui.check('Compiler build settings', errors, 'Xcode Debug and Release Swift/Clang warnings are errors')
    return int(bool(errors))


if __name__ == '__main__':
    raise SystemExit(main())
