#!/usr/bin/env python3
"""Check Markdown, shared skills, Swift examples and UI design review consistency."""

import argparse
import json
from pathlib import Path
import re
import unicodedata
from urllib.parse import unquote, urlsplit

from markdown_it import MarkdownIt
import yaml

import check_ui_design

from check_swift_policy import GENERATED, violations

PARSER = MarkdownIt('commonmark')


def markdown_files(root):
    for directory, folders, files in root.walk(follow_symlinks=False):
        folders[:] = sorted(n for n in folders if n not in GENERATED and n != 'result' and not n.startswith('result-'))
        for name in sorted(files):
            path = directory / name
            if path.suffix == '.md':
                yield path


def slug(text):
    return ''.join(c for c in text.lower() if c in '-_ ' or unicodedata.category(c)[0] not in 'PS').replace(' ', '-')


def anchors(tokens):
    result, counts = set(), {}
    for index, token in enumerate(tokens):
        if token.type == 'heading_open':
            inline = tokens[index + 1]
            text = ''.join(t.content for t in inline.children or [] if t.type in {'text', 'code_inline', 'image'})
            base = slug(text)
            number = counts.get(base, 0)
            anchor = base if not number else f'{base}-{number}'
            while anchor in result:
                number += 1
                anchor = f'{base}-{number}'
            counts[base] = number + 1
            result.add(anchor)
        if token.type in {'html_block', 'inline'}:
            result.update(re.findall(r'\b(?:id|name)=["\']([^"\']+)', token.content))
    return result


def check(root):
    errors, links, examples = [], 0, 0
    files = list(markdown_files(root))
    parsed = {p.resolve(): PARSER.parse(p.read_text()) for p in files}
    for path in files:
        relative = path.relative_to(root).as_posix()
        tokens = parsed[path.resolve()]
        for token in tokens:
            for child in token.children or []:
                target = child.attrGet('href') if child.type == 'link_open' else child.attrGet('src') if child.type == 'image' else None
                if target is None:
                    continue
                url = urlsplit(target)
                if url.scheme or url.netloc:
                    continue
                links += 1
                dest = ((root if url.path.startswith('/') else path.parent) / unquote(url.path).lstrip('/')).resolve() if url.path else path.resolve()
                if not dest.is_relative_to(root.resolve()) or not dest.exists():
                    errors.append(f'{relative}: missing/outside local link: {target}')
                elif url.fragment and dest.suffix == '.md' and unquote(url.fragment) not in anchors(parsed.get(dest, PARSER.parse(dest.read_text()))):
                    errors.append(f'{relative}: missing heading: {target}')
            if relative == 'docs/library-policy.md' and token.type == 'fence' and token.info == 'swift':
                examples += 1
                found = violations(token.content)
                if found:
                    errors.append(f'{relative}:{token.map[0] + 1}: Swift example violates policy: {found}')
        if path.name == 'SKILL.md':
            source = path.read_text()
            front = re.match(r'\A---\n(.*?)\n---(?:\n|$)', source, flags=re.S)
            try:
                data = yaml.safe_load(front[1]) if front else None
                if not isinstance(data, dict) or data.get('name') != path.parent.name or not re.fullmatch(r'[a-z0-9-]{1,64}', data.get('name', '')) or not isinstance(data.get('description'), str) or not data['description'].strip():
                    raise ValueError('name must match the skill directory; description must be nonempty')
            except (ValueError, yaml.YAMLError) as error:
                errors.append(f'{relative}: invalid skill frontmatter: {error}')
    if not files:
        errors.append('No Markdown files found')
    return {'markdown_files': len(files), 'local_links': links, 'swift_examples': examples, 'errors': errors}


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = cli.parse_args()
    try:
        report = check(args.root.resolve())
        design = check_ui_design.check(args.root.resolve())
        report['ui_design'] = {key: value for key, value in design.items() if key != 'errors'}
        report['errors'].extend('UI design: ' + error for error in design['errors'])
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return bool(report['errors'])
    except (OSError, ValueError) as error:
        print(f'Documentation check failed: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
