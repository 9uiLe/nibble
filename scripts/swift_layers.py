"""Check source-level dependencies; Swift compilation remains the type authority."""
from pathlib import Path


IMPORTS = {
    'domain': {'Foundation', 'Darwin'},
    'contracts': {'Foundation'},
    'application': {'Foundation', 'Observation'},
    'persistence': {'Foundation', 'SQLite3', 'OSLog'},
}
DEPENDENCIES = {
    'domain': {'domain'},
    'contracts': {'domain', 'contracts'},
    'application': {'domain', 'contracts', 'application'},
    'persistence': {'domain', 'contracts', 'persistence'},
}


def layer(path):
    parts = Path(path).parts
    if len(parts) < 3 or parts[0] != 'app' or any('Tests' in part for part in parts):
        return None
    if parts[1] == 'Shared':
        if parts[2] == 'Application':
            return 'contracts' if len(parts) > 3 and parts[3] == 'Contracts' else 'application'
        return {'Domain': 'domain', 'Persistence': 'persistence'}.get(parts[2], 'presentation')
    return 'presentation' if parts[1] in {'Nibble', 'NibbleShare', 'NibbleKeyboard'} else None


def top_level_types(tokens):
    depth = 0
    for index, token in enumerate(tokens[:-1]):
        if depth == 0 and token.text in {'struct', 'class', 'enum', 'actor', 'protocol', 'typealias'}:
            # Scoped imports name a type, but do not declare one in this source.
            if index == 0 or tokens[index - 1].text != 'import':
                yield tokens[index + 1].text
        depth += (token.text == '{') - (token.text == '}')


def check_layers(sources, tokenize):
    parsed, owners, errors = {}, {}, []
    for path, source in sources.items():
        owner = layer(path)
        if owner is None:
            continue
        try:
            tokens = tokenize(source)
        except ValueError:
            continue  # The syntax checker reports lexical failures.
        parsed[path] = (owner, tokens)
        for name in top_level_types(tokens):
            owners.setdefault(name, set()).add(owner)
    for path, (owner, tokens) in parsed.items():
        if owner not in DEPENDENCIES:
            continue
        source, reported = sources[path], set()
        for index, token in enumerate(tokens):
            message = None
            if token.text == 'import':
                following = tokens[index + 1:]
                if following and following[0].text in {'struct', 'class', 'enum', 'protocol', 'func', 'var', 'let', 'typealias'}:
                    following = following[1:]
                if following and following[0].text not in IMPORTS[owner]:
                    message = f'{owner} cannot import {following[0].text}.'
            elif token.text in owners and not owners[token.text] <= DEPENDENCIES[owner]:
                message = f'{owner} cannot reference {token.text} from {", ".join(sorted(owners[token.text]))}.'
            elif token.text in {'localizedDescription', 'displayTitle', 'textPresentation'} and index and tokens[index - 1].text == '.':
                message = f'{owner} returns facts and outcomes; format {token.text} in presentation.'
            if message and message not in reported:
                reported.add(message)
                line = source.count('\n', 0, token.offset) + 1
                column = token.offset - source.rfind('\n', 0, token.offset)
                errors.append(f'{path}:{line}:{column}: error: {message}')
    return errors
