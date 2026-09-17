"""Public use cases: capture inputs, analyze design, compare or propose a review record."""

import re

from ._catalog import inspect_documents
from ._policy import decode_json, fields, parse_policy, relative_path
from ._sources import Repository


def _review_metadata(summary, references, documents):
    if not isinstance(summary, str) or not summary.strip():
        raise ValueError('Review summary must describe the design impact and review conclusion')
    if not isinstance(references, list) or not references or any(
        not isinstance(name, str) or name not in documents for name in references
    ) or len(references) != len(set(references)):
        raise ValueError('Review references must name unique, inspected design documents')


def _review_errors(content, inputs):
    """Pure comparison: the record never determines the scope or performs file I/O."""
    try:
        record = decode_json(content)
        fields(record, {'version', 'summary', 'references', 'files'})
        if type(record['version']) is not int or record['version'] != 1:
            raise ValueError('Unsupported design review record version; expected 1')
        _review_metadata(record['summary'], record['references'], inputs.documents)
        previous = record['files']
        if not isinstance(previous, dict):
            raise ValueError('Review files must map paths to SHA-256 hashes')
        for name, value in previous.items():
            relative_path(name)
            if not isinstance(value, str) or not re.fullmatch(r'[a-f0-9]{64}', value):
                raise ValueError('Review files must map paths to SHA-256 hashes')
    except ValueError as error:
        return [f'Invalid review record: {error}']
    errors = []
    for name in sorted(inputs.files.keys() | previous.keys()):
        if inputs.files.get(name) == previous.get(name):
            continue
        change = 'added' if name not in previous else 'removed' if name not in inputs.files else 'changed'
        errors.append(f'Unreviewed {change} input: {name}')
    return errors


def _inspect(root, config):
    repository = Repository(root)
    content = repository.read(config)
    policy = parse_policy(content, config)
    inputs = repository.capture(policy, content)
    catalog = inspect_documents(inputs.documents, policy.registries)
    return repository, policy, inputs, catalog


def snapshot(root, config, summary, references):
    """Return a candidate review record; no writes, approval or semantic claims."""
    _, _, inputs, catalog = _inspect(root, config)
    if catalog.errors:
        raise ValueError('\n'.join(catalog.errors))
    _review_metadata(summary, references, inputs.documents)
    return {'version': 1, 'summary': summary.strip(), 'references': list(references), 'files': inputs.files}


def check(root, config):
    """Return a JSON-compatible report. Invalid policy/I/O raises ValueError/OSError."""
    repository, policy, inputs, catalog = _inspect(root, config)
    content = repository.review(policy.record)
    errors = list(catalog.errors)
    errors.extend([f'Missing review record: {policy.record}'] if content is None else _review_errors(content, inputs))
    return {'inputs': len(inputs.files), 'ids': catalog.counts, 'errors': errors}
