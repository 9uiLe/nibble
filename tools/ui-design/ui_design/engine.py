"""Product-independent design inventory and review checks. Public API: check, snapshot."""

from fnmatch import fnmatchcase
from hashlib import sha256
import json
from pathlib import Path, PurePosixPath
import re

from markdown_it import MarkdownIt

_PARSER = MarkdownIt('commonmark').enable('table')


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'Duplicate JSON key: {key}')
        result[key] = value
    return result


def _keys(value, required, optional=()):
    if not isinstance(value, dict) or not set(required) <= value.keys() or value.keys() - set(required) - set(optional):
        raise ValueError(f'Expected fields {sorted(required)}; optional {sorted(optional)}')


def _relative(value):
    if not isinstance(value, str) or not value or '\\' in value or ':' in value:
        raise ValueError(f'Expected a repository-relative POSIX path: {value!r}')
    path = PurePosixPath(value)
    if path.is_absolute() or '..' in path.parts or path.as_posix() != value or value == '.':
        raise ValueError(f'Expected a canonical repository-relative path: {value!r}')
    return value


def _path(root, name):
    path = root
    for part in PurePosixPath(_relative(name)).parts:
        path = path / part
        if path.is_symlink():
            raise ValueError(f'Input must not use symlinks: {name}')
    if not path.resolve().is_relative_to(root):
        raise ValueError(f'Input outside project: {name}')
    return path


def _patterns(values):
    if not isinstance(values, list) or any(not isinstance(v, str) or not v or '/' in v or '\\' in v for v in values):
        raise ValueError('Exclusions must be lists of filename patterns without path separators')


def _policy(root, name):
    path = _path(root, name)
    value = json.loads(path.read_text(), object_pairs_hook=_unique_object)
    _keys(value, {'version', 'record', 'inputs', 'registries'})
    if type(value['version']) is not int or value['version'] != 1:
        raise ValueError('Unsupported policy version; expected 1')
    _path(root, value['record'])
    if value['record'] == name:
        raise ValueError('Policy and review record must be different files')
    if not isinstance(value['inputs'], list) or not value['inputs']:
        raise ValueError('Policy needs at least one input')
    input_paths = set()
    for item in value['inputs']:
        _keys(item, {'path', 'kind'}, {'exclude_directories', 'exclude_files', 'references'})
        _relative(item['path'])
        if item['path'] in input_paths or item['path'] == value['record']:
            raise ValueError(f'Duplicate input or review record input: {item["path"]}')
        input_paths.add(item['path'])
        if not isinstance(item['kind'], str) or item['kind'] not in {'tree', 'file'}:
            raise ValueError('Input kind must be tree or file')
        if type(item.get('references', False)) is not bool:
            raise ValueError('Input references flag must be boolean')
        if item['kind'] == 'file' and set(item) - {'path', 'kind', 'references'}:
            raise ValueError('File inputs cannot have exclusions')
        for field in ('exclude_directories', 'exclude_files'):
            _patterns(item.get(field, []))
    if not isinstance(value['registries'], list) or not value['registries']:
        raise ValueError('Policy needs at least one registry')
    prefixes = set()
    for item in value['registries']:
        _keys(item, {'prefix', 'path', 'format'}, {'columns'})
        prefix = item['prefix']
        if not isinstance(prefix, str) or not re.fullmatch('[A-Z]+', prefix) or prefix in prefixes:
            raise ValueError('Registry prefixes must be unique uppercase letters')
        prefixes.add(prefix)
        _relative(item['path'])
        if Path(item['path']).suffix != '.md':
            raise ValueError('Registry paths must be Markdown files')
        if item['format'] == 'table':
            if type(item.get('columns')) is not int or item['columns'] < 2:
                raise ValueError('Table registry needs a column count of at least 2')
        elif item['format'] != 'heading' or 'columns' in item:
            raise ValueError('Registry format must be heading or table with columns')
    return value


def _raise_walk_error(error):
    raise error


def _files(root, config, policy):
    # Scope comes from policy, never from the review record. New files are discovered.
    paths, documents = {config}, set()
    for item in policy['inputs']:
        path = _path(root, item['path'])
        if item['kind'] == 'file':
            if not path.is_file():
                raise ValueError(f'Missing input file: {item["path"]}')
            paths.add(item['path'])
            if item.get('references', False):
                documents.add(item['path'])
            continue
        if not path.is_dir():
            raise ValueError(f'Missing input directory: {item["path"]}')
        collected = set()
        for parent, folders, files in path.walk(on_error=_raise_walk_error, follow_symlinks=False):
            folders[:] = sorted(folder for folder in folders if not any(
                fnmatchcase(folder, pattern) for pattern in item.get('exclude_directories', [])))
            for filename in sorted(files):
                if any(fnmatchcase(filename, pattern) for pattern in item.get('exclude_files', [])):
                    continue
                relative = (parent / filename).relative_to(root).as_posix()
                if relative == policy['record']:
                    continue
                source = _path(root, relative)
                if not source.is_file():
                    raise ValueError(f'Input must be a regular file: {relative}')
                collected.add(relative)
        if not collected:
            raise ValueError(f'No inputs found under: {item["path"]}')
        paths.update(collected)
        if item.get('references', False):
            documents.update(collected)
    files = {name: sha256(_path(root, name).read_bytes()).hexdigest() for name in sorted(paths)}
    return files, {name for name in documents if Path(name).suffix == '.md'}


def _inline_text(token):
    return ''.join(child.content for child in token.children or []
                   if child.type in {'text', 'code_inline', 'image', 'softbreak', 'hardbreak'})


def _identifiers(root, documents, registries):
    # Comments and fenced examples cannot define identifiers.
    errors, known, references, counts = [], set(), set(), {}
    parsed = {name: _PARSER.parse(_path(root, name).read_text())
              for name in documents}
    for registry in registries:
        prefix, name, kind = registry['prefix'], registry['path'], registry['format']
        if name not in parsed:
            errors.append(f'Missing design registry: {name}')
            continue
        tokens, entries = parsed[name], []
        for index, token in enumerate(tokens):
            if kind == 'heading' and token.type == 'heading_open':
                entries.append([_inline_text(tokens[index + 1]).strip()])
            if kind == 'table' and token.type == 'tr_open':
                cells = []
                for child in tokens[index + 1:]:
                    if child.type == 'tr_close':
                        break
                    if child.type == 'inline':
                        cells.append(_inline_text(child).strip())
                if cells:
                    entries.append(cells)
        count = 0
        for cells in entries:
            match = re.match(rf'^({prefix}[0-9]{{2,}})(?:\s+(.*))?$', cells[0])
            if not match:
                continue
            identifier, title = match.groups()
            count += 1
            digits = identifier[len(prefix):]
            if digits != f'{int(digits):02}':
                errors.append(f'Noncanonical design ID: {identifier} ({name})')
            if identifier in known:
                errors.append(f'Duplicate design ID: {identifier} ({name})')
            known.add(identifier)
            if not title or (kind == 'table' and (len(cells) != registry['columns'] or not all(cells))):
                errors.append(f'Incomplete design entry: {identifier} ({name})')
        if not count:
            errors.append(f'No {prefix} definitions: {name}')
        counts[prefix] = count
    prefixes = '|'.join(re.escape(item['prefix']) for item in registries)
    identifier_pattern = rf'(?:{prefixes})[0-9]{{2,}}'
    reference = re.compile(rf'(?<![A-Za-z0-9])({identifier_pattern})(?:[〜–-]({identifier_pattern}))?(?![A-Za-z0-9])')
    for name, tokens in parsed.items():
        for token in tokens:
            if token.type != 'inline':
                continue
            for match in reference.finditer(_inline_text(token)):
                first, last = match.groups()
                if last:
                    first_prefix, start = re.fullmatch(r'([A-Z]+)([0-9]+)', first).groups()
                    last_prefix, end = re.fullmatch(r'([A-Z]+)([0-9]+)', last).groups()
                    start, end = int(start), int(end)
                    if first_prefix != last_prefix or start > end or end - start > 1000:
                        errors.append(f'Invalid design ID range: {match[0]} ({name})')
                        continue
                    references.update(f'{first_prefix}{number:02}' for number in range(start, end + 1))
                else:
                    references.add(first)
    errors.extend(f'Undefined design ID: {identifier}' for identifier in sorted(references - known))
    return counts, errors


def _review_metadata(summary, references, documents):
    if not isinstance(summary, str) or not summary.strip():
        raise ValueError('Review summary must describe the design impact and review conclusion')
    if not isinstance(references, list) or not references or any(
        not isinstance(name, str) or name not in documents
        for name in references
    ) or len(references) != len(set(references)):
        raise ValueError('Review references must name unique, inspected design documents')


def _inspect(root, config):
    root = Path(root).resolve()
    policy = _policy(root, config)
    files, documents = _files(root, config, policy)
    counts, errors = _identifiers(root, documents, policy['registries'])
    return root, policy, files, documents, counts, errors


def snapshot(root, config, summary, references):
    """Return a candidate review record; no writes, approval or semantic claims."""
    _, _, files, documents, _, errors = _inspect(root, config)
    if errors:
        raise ValueError('\n'.join(errors))
    _review_metadata(summary, references, documents)
    return {'version': 1, 'summary': summary.strip(), 'references': references, 'files': files}


def check(root, config):
    """Return a JSON-compatible report. Invalid policy/I/O raises ValueError/OSError."""
    root, policy, files, documents, counts, errors = _inspect(root, config)
    path = _path(root, policy['record'])
    if not path.is_file():
        errors.append(f'Missing review record: {policy["record"]}')
    else:
        try:
            record = json.loads(path.read_text(), object_pairs_hook=_unique_object)
            _keys(record, {'version', 'summary', 'references', 'files'})
            if type(record['version']) is not int or record['version'] != 1:
                raise ValueError('Unsupported design review record version; expected 1')
            _review_metadata(record['summary'], record['references'], documents)
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
