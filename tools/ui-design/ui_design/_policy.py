"""Decode untrusted configuration into immutable contracts. No filesystem access."""

from dataclasses import dataclass
import json
from pathlib import PurePosixPath
import re


@dataclass(frozen=True, slots=True)
class Input:
    path: str
    kind: str
    references: bool
    exclude_directories: tuple[str, ...]
    exclude_files: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class Registry:
    prefix: str
    path: str
    format: str
    columns: int | None


@dataclass(frozen=True, slots=True)
class Policy:
    config: str
    record: str
    inputs: tuple[Input, ...]
    registries: tuple[Registry, ...]


def decode_json(content: bytes):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'Duplicate JSON key: {key}')
            result[key] = value
        return result
    return json.loads(content.decode('utf-8'), object_pairs_hook=unique_object)


def fields(value, required, optional=()):
    if not isinstance(value, dict) or not set(required) <= value.keys() or value.keys() - set(required) - set(optional):
        raise ValueError(f'Expected fields {sorted(required)}; optional {sorted(optional)}')


def relative_path(value):
    if not isinstance(value, str) or not value or '\\' in value or ':' in value:
        raise ValueError(f'Expected a repository-relative POSIX path: {value!r}')
    path = PurePosixPath(value)
    if path.is_absolute() or '..' in path.parts or path.as_posix() != value or value == '.':
        raise ValueError(f'Expected a canonical repository-relative path: {value!r}')
    return value


def _patterns(values):
    if not isinstance(values, list) or any(not isinstance(v, str) or not v or '/' in v or '\\' in v for v in values):
        raise ValueError('Exclusions must be lists of filename patterns without path separators')
    return tuple(values)


def _input(value):
    fields(value, {'path', 'kind'}, {'exclude_directories', 'exclude_files', 'references'})
    path, kind = relative_path(value['path']), value['kind']
    if not isinstance(kind, str) or kind not in {'tree', 'file'}:
        raise ValueError('Input kind must be tree or file')
    references = value.get('references', False)
    if type(references) is not bool:
        raise ValueError('Input references flag must be boolean')
    if kind == 'file' and set(value) - {'path', 'kind', 'references'}:
        raise ValueError('File inputs cannot have exclusions')
    return Input(path, kind, references, _patterns(value.get('exclude_directories', [])),
                 _patterns(value.get('exclude_files', [])))


def _registry(value):
    fields(value, {'prefix', 'path', 'format'}, {'columns'})
    prefix = value['prefix']
    if not isinstance(prefix, str) or not re.fullmatch('[A-Z]+', prefix):
        raise ValueError('Registry prefixes must be unique uppercase letters')
    path, kind = relative_path(value['path']), value['format']
    if PurePosixPath(path).suffix != '.md':
        raise ValueError('Registry paths must be Markdown files')
    columns = value.get('columns')
    if kind == 'table':
        if type(columns) is not int or columns < 2:
            raise ValueError('Table registry needs a column count of at least 2')
    elif kind != 'heading' or 'columns' in value:
        raise ValueError('Registry format must be heading or table with columns')
    return Registry(prefix, path, kind, columns)


def parse_policy(content: bytes, config: str) -> Policy:
    config = relative_path(config)
    value = decode_json(content)
    fields(value, {'version', 'record', 'inputs', 'registries'})
    if type(value['version']) is not int or value['version'] != 1:
        raise ValueError('Unsupported policy version; expected 1')
    record = relative_path(value['record'])
    if record == config:
        raise ValueError('Policy and review record must be different files')
    for key in ('inputs', 'registries'):
        if not isinstance(value[key], list) or not value[key]:
            raise ValueError(f'Policy needs at least one entry in {key}')
    inputs = tuple(_input(item) for item in value['inputs'])
    paths = [item.path for item in inputs]
    if len(set(paths)) != len(paths) or record in paths:
        raise ValueError('Duplicate input or review record input')
    registries = tuple(_registry(item) for item in value['registries'])
    if len({item.prefix for item in registries}) != len(registries):
        raise ValueError('Registry prefixes must be unique uppercase letters')
    return Policy(config, record, inputs, registries)
