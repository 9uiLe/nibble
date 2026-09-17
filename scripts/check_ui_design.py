#!/usr/bin/env python3
"""Detect unreviewed product/design changes and broken UI design identifiers."""

import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
import sys

from markdown_it import MarkdownIt

RECORD = 'docs/design/review.json'
DOCUMENTS = ('docs/decisions/0002-mvp-app.md', 'research/06-interface-design-evidence.md')
REGISTRIES = {
    'C': ('docs/design/components.md', 'table'),
    'S': ('docs/design/screens.md', 'heading'),
    'F': ('docs/design/foundations.md', 'heading'),
    'R': ('research/06-interface-design-evidence.md', 'heading'),
    'G': ('docs/design/audit.md', 'heading'),
}
GENERATED = {'build', '.build', 'DerivedData', 'xcuserdata', '__pycache__', '.DS_Store'}
ID = r'[CSFRG][0-9]{2,}'
REFERENCE = re.compile(rf'(?<![A-Za-z0-9])({ID})(?:[〜–-]({ID}))?(?![A-Za-z0-9])')
PARSER = MarkdownIt('commonmark').enable('table')


def input_files(root):
    """Discover inputs independently of the receipt, including new files/targets/assets."""
    paths = []
    for name in ('app', 'docs/design'):
        directory = root / name
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError(f'Missing or symlink input directory: {name}')
        for parent, folders, files in directory.walk(follow_symlinks=False):
            folders[:] = sorted(folder for folder in folders if folder not in GENERATED
                                and not (name == 'app' and folder.endswith('Tests')))
            for filename in sorted(files):
                path = parent / filename
                relative = path.relative_to(root).as_posix()
                if filename in GENERATED or relative == RECORD or (name == 'app' and path.suffix == '.md'):
                    continue
                if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
                    raise ValueError(f'Input must be a regular file: {relative}')
                paths.append(path)
    for name in DOCUMENTS:
        path = root / name
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError(f'Missing or symlink design document: {name}')
        paths.append(path)
    if not any(path.is_relative_to(root / 'app') for path in paths):
        raise ValueError('No product inputs found under app/')
    return sorted(paths)


def inventory(root):
    return {path.relative_to(root).as_posix(): sha256(path.read_bytes()).hexdigest()
            for path in input_files(root)}


def inline_text(token):
    return ''.join(child.content for child in token.children or []
                   if child.type in {'text', 'code_inline', 'image', 'softbreak', 'hardbreak'})


def identifiers(root, files):
    """Parse real headings/table rows; comments and fenced examples are not definitions."""
    errors, known, references, counts = [], set(), set(), {}
    parsed = {name: PARSER.parse((root / name).read_text())
              for name in files if Path(name).suffix == '.md'}
    for prefix, (name, kind) in REGISTRIES.items():
        if name not in parsed:
            errors.append(f'Missing design registry: {name}')
            continue
        tokens, entries = parsed[name], []
        for index, token in enumerate(tokens):
            if kind == 'heading' and token.type == 'heading_open':
                entries.append([inline_text(tokens[index + 1]).strip()])
            if kind == 'table' and token.type == 'tr_open':
                cells = []
                for child in tokens[index + 1:]:
                    if child.type == 'tr_close':
                        break
                    if child.type == 'inline':
                        cells.append(inline_text(child).strip())
                if cells:
                    entries.append(cells)
        count = 0
        for cells in entries:
            match = re.match(rf'^({prefix}[0-9]{{2,}})(?:\s+(.*))?$', cells[0])
            if not match:
                continue
            identifier, title = match.groups()
            count += 1
            if identifier in known:
                errors.append(f'Duplicate design ID: {identifier} ({name})')
            known.add(identifier)
            if not title or (kind == 'table' and (len(cells) != 4 or not all(cells))):
                errors.append(f'Incomplete design entry: {identifier} ({name})')
        if not count:
            errors.append(f'No {prefix} definitions: {name}')
        counts[prefix] = count
    for name, tokens in parsed.items():
        for token in tokens:
            if token.type != 'inline':
                continue
            for match in REFERENCE.finditer(inline_text(token)):
                first, last = match.groups()
                if last:
                    start, end = int(first[1:]), int(last[1:])
                    if first[0] != last[0] or start > end or end - start > 1000:
                        errors.append(f'Invalid design ID range: {match[0]} ({name})')
                        continue
                    references.update(f'{first[0]}{number:02}' for number in range(start, end + 1))
                else:
                    references.add(first)
    errors.extend(f'Undefined design ID: {identifier}' for identifier in sorted(references - known))
    return counts, errors


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'Duplicate JSON key: {key}')
        result[key] = value
    return result


def review_metadata(summary, references, files):
    if not isinstance(summary, str) or not summary.strip():
        raise ValueError('Review summary must describe the design impact and review conclusion')
    if not isinstance(references, list) or not references or any(
        not isinstance(name, str) or name not in files or Path(name).suffix != '.md'
        for name in references
    ) or len(references) != len(set(references)):
        raise ValueError('Review references must name unique, inspected design documents')


def snapshot(root, summary, references):
    files = inventory(root)
    _, errors = identifiers(root, files)
    if errors:
        raise ValueError('\n'.join(errors))
    review_metadata(summary, references, files)
    return {'version': 1, 'summary': summary.strip(), 'references': references, 'files': files}


def check(root):
    files = inventory(root)
    counts, errors = identifiers(root, files)
    path = root / RECORD
    if path.is_symlink() or not path.is_file():
        errors.append(f'Missing review record: {RECORD}')
    else:
        try:
            record = json.loads(path.read_text(), object_pairs_hook=unique_object)
            if not isinstance(record, dict) or set(record) != {'version', 'summary', 'references', 'files'} or type(record['version']) is not int or record['version'] != 1:
                raise ValueError('Invalid design review record schema')
            review_metadata(record['summary'], record['references'], files)
            previous = record['files']
            if not isinstance(previous, dict) or any(not isinstance(value, str) or not re.fullmatch(r'[a-f0-9]{64}', value) for value in previous.values()):
                raise ValueError('Review files must map paths to SHA-256 hashes')
            for name in sorted(files.keys() | previous.keys()):
                if files.get(name) == previous.get(name):
                    continue
                change = 'added' if name not in previous else 'removed' if name not in files else 'changed'
                errors.append(f'Unreviewed {change} input: {name}')
        except (ValueError, TypeError) as error:
            errors.append(f'Invalid review record: {error}')
    return {'inputs': len(files), 'ids': counts, 'errors': errors}


def main(argv=None):
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    sub = cli.add_subparsers(dest='command', required=True)
    sub.add_parser('check', help='Read-only check; never changes the review record')
    candidate = sub.add_parser('snapshot', help='Print a candidate record after reviewing design impact')
    candidate.add_argument('--summary', required=True, help='Impact, reviewed contracts and conclusion')
    candidate.add_argument('--reference', action='append', required=True, dest='references', help='Inspected design document path; repeat as needed')
    args = cli.parse_args(argv)
    try:
        root = args.root.resolve()
        report = check(root) if args.command == 'check' else snapshot(root, args.summary, args.references)
        print(json.dumps(report, ensure_ascii=False, indent=2) + '\n', end='')
        return bool(report.get('errors'))
    except (OSError, ValueError) as error:
        print(f'UI design check failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
