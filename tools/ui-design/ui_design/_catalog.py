"""Pure Markdown design analysis. No paths are opened and no parser state is shared."""

from dataclasses import dataclass
import re

from markdown_it import MarkdownIt

from ._policy import Registry


@dataclass(frozen=True, slots=True)
class Catalog:
    counts: dict[str, int]
    errors: tuple[str, ...]


def _text(token):
    return ''.join(child.content for child in token.children or []
                   if child.type in {'text', 'code_inline', 'image', 'softbreak', 'hardbreak'})


def _entries(tokens, kind):
    # Walk table cells once. Never allocate the remaining token list for each row.
    row = None
    for index, token in enumerate(tokens):
        if kind == 'heading' and token.type == 'heading_open':
            yield [_text(tokens[index + 1]).strip()]
        elif kind == 'table':
            if token.type == 'tr_open':
                row = []
            elif token.type == 'inline' and row is not None:
                row.append(_text(token).strip())
            elif token.type == 'tr_close' and row is not None:
                yield row
                row = None


def _canonical(identifier):
    digits = re.search(r'[0-9]+$', identifier)[0]
    return len(digits) >= 2 and (len(digits) == 2 or not digits.startswith('0'))


def inspect_documents(documents: dict[str, str], registries: tuple[Registry, ...]) -> Catalog:
    parser = MarkdownIt('commonmark').enable('table')
    known, references, counts, errors = set(), set(), {}, []
    prefixes = '|'.join(re.escape(item.prefix) for item in registries)
    identifier = rf'(?:{prefixes})[0-9]+'
    reference = re.compile(rf'(?<![A-Za-z0-9])({identifier})(?:[〜–-]({identifier}))?(?![A-Za-z0-9])')
    for registry in registries:
        if registry.path not in documents:
            errors.append(f'Missing design registry: {registry.path}')
    # Retain only compact IDs/counts; release each document's syntax tree before the next.
    for name in sorted(documents):
        tokens = parser.parse(documents[name])
        for registry in (item for item in registries if item.path == name):
            definition = re.compile(rf'^({registry.prefix}[0-9]+)(?:\s+(.*))?$')
            count = 0
            for cells in _entries(tokens, registry.format):
                match = definition.match(cells[0]) if cells else None
                if not match:
                    continue
                key, title = match.groups()
                count += 1
                if not _canonical(key):
                    errors.append(f'Noncanonical design ID: {key} ({name})')
                if key in known:
                    errors.append(f'Duplicate design ID: {key} ({name})')
                known.add(key)
                if not title or (registry.format == 'table' and (len(cells) != registry.columns or not all(cells))):
                    errors.append(f'Incomplete design entry: {key} ({name})')
            if not count:
                errors.append(f'No {registry.prefix} definitions: {name}')
            counts[registry.prefix] = count
        for token in tokens:
            if token.type != 'inline':
                continue
            for match in reference.finditer(_text(token)):
                first, last = match.groups()
                if any(not _canonical(key) for key in (first, last) if key):
                    errors.append(f'Noncanonical design ID reference: {match[0]} ({name})')
                    continue
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
        del tokens
    errors.extend(f'Undefined design ID: {key}' for key in sorted(references - known))
    return Catalog({item.prefix: counts[item.prefix] for item in registries if item.prefix in counts}, tuple(errors))
