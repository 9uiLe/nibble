#!/usr/bin/env python3
"""Check Markdown, shared skills, Swift examples and UI design review consistency."""

import argparse
from dataclasses import dataclass
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import unicodedata
from urllib.parse import unquote, urlsplit

from markdown_it import MarkdownIt
import yaml

import check_ui_design
from script_ui import ui

from check_swift_policy import GENERATED, violations

CONTEXT_DEPENDENT_PHRASES = (
    '以前は', '今回の変更で', '新方式', '旧方式', '暫定的に', '議論したとおり',
)


class SiteLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.targets = []

    def handle_starttag(self, tag, attrs):
        attribute = 'href' if tag in {'a', 'link'} else 'src' if tag in {'img', 'script'} else None
        if attribute:
            self.targets.extend(value for name, value in attrs if name == attribute and value)


def check_site(root):
    public = root / 'marketing/public'
    if not public.is_dir():
        return {'site_pages': 0, 'site_links': 0, 'errors': []}
    config = root / 'marketing/firebase.json'
    redirects = {}
    errors = []
    if config.exists():
        try:
            redirects = {item['source']: item['destination']
                         for item in json.loads(config.read_text(encoding='utf-8'))['hosting'].get('redirects', [])}
        except (KeyError, TypeError, ValueError) as error:
            errors.append(f'marketing/firebase.json: invalid Hosting redirects: {error}')
    for source, target in redirects.items():
        path = unquote(urlsplit(target).path)
        destination = (public / ('index.html' if path == '/' else path.lstrip('/'))).resolve()
        if not path.startswith('/') or not destination.is_relative_to(public.resolve()) or not destination.is_file():
            errors.append(f'marketing/firebase.json: missing/outside redirect destination: {source} -> {target}')
    links = 0
    pages = list(public.glob('*.html'))
    for page in pages:
        parser = SiteLinks()
        parser.feed(page.read_text(encoding='utf-8'))
        for target in parser.targets:
            url = urlsplit(target)
            if url.scheme or url.netloc or not url.path:
                continue
            links += 1
            path = redirects.get(url.path, url.path)
            destination = (public / ('index.html' if path == '/' else unquote(path).lstrip('/'))).resolve() if path.startswith('/') else (page.parent / unquote(path)).resolve()
            if not destination.is_relative_to(public.resolve()) or not destination.is_file():
                errors.append(f'{page.relative_to(root)}: missing/outside site link: {target}')
    return {'site_pages': len(pages), 'site_links': links, 'errors': errors}

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


@dataclass(frozen=True, slots=True)
class Document:
    headings: frozenset[str]
    links: tuple[str, ...]
    swift_examples: tuple[tuple[int, str], ...]
    frontmatter: str | None
    command_paths: tuple[str, ...]
    context_dependent_prose: tuple[tuple[int, str], ...]


def inspect_document(source):
    """Parse one source into compact facts. No filesystem or shared parser state."""
    tokens = MarkdownIt('commonmark').parse(source)
    links, examples, command_paths, context_dependent_prose = [], [], [], []
    for token in tokens:
        if token.type == 'inline':
            for child in token.children or []:
                if child.type != 'text':
                    continue
                for phrase in CONTEXT_DEPENDENT_PHRASES:
                    if phrase in child.content:
                        context_dependent_prose.append(((token.map or [0])[0] + 1, phrase))
        for child in token.children or []:
            target = child.attrGet('href') if child.type == 'link_open' else child.attrGet('src') if child.type == 'image' else None
            if target is not None:
                url = urlsplit(target)
                if not url.scheme and not url.netloc:
                    links.append(target)
        if token.type == 'fence' and token.info == 'swift':
            examples.append((token.map[0] + 1, token.content))
        if token.type == 'fence' and token.info in {'sh', 'bash', 'shell', 'zsh'}:
            command_paths.extend(re.findall(
                r'(?<![\w./-])((?:scripts|app|validation|tools)/[A-Za-z0-9_./-]+\.(?:py|sh|json|swift|xcodeproj))(?![\w./-])',
                token.content))
    front = re.match(r'\A---\n(.*?)\n---(?:\n|$)', source, flags=re.S)
    return Document(frozenset(anchors(tokens)), tuple(links), tuple(examples), front[1] if front else None,
                    tuple(command_paths), tuple(context_dependent_prose))


def document_errors(document, relative):
    """Apply path-specific contracts after parsing, including aliases of the same source."""
    errors = []
    for line, phrase in document.context_dependent_prose:
        errors.append(f'{relative}:{line}: context-dependent design prose: {phrase}')
    if relative == 'docs/library-policy.md':
        for line, source in document.swift_examples:
            found = violations(source)
            if found:
                errors.append(f'{relative}:{line}: Swift example violates policy: {found}')
    path = Path(relative)
    if path.name == 'SKILL.md':
        try:
            data = yaml.safe_load(document.frontmatter) if document.frontmatter is not None else None
            if not isinstance(data, dict) or data.get('name') != path.parent.name or not re.fullmatch(r'[a-z0-9-]{1,64}', data.get('name', '')) or not isinstance(data.get('description'), str) or not data['description'].strip():
                raise ValueError('name must match the skill directory; description must be nonempty')
        except (ValueError, yaml.YAMLError) as error:
            errors.append(f'{relative}: invalid skill frontmatter: {error}')
    return errors


def check(root):
    root = root.resolve()
    files = list(markdown_files(root))
    documents = {}
    def load(path):
        key = path.resolve()
        if key not in documents:
            documents[key] = inspect_document(key.read_text(encoding='utf-8'))
        return documents[key]
    errors, links, examples, commands = [], 0, 0, 0
    for path in files:
        relative = path.relative_to(root).as_posix()
        document = load(path)
        errors.extend(document_errors(document, relative))
        for name in document.command_paths:
            commands += 1
            target = (root / name).resolve()
            if not target.is_relative_to(root) or not target.exists():
                errors.append(f'{relative}: missing/outside command input: {name}')
        if relative == 'docs/library-policy.md':
            examples += len(document.swift_examples)
        for target in document.links:
            links += 1
            url = urlsplit(target)
            dest = ((root if url.path.startswith('/') else path.parent) / unquote(url.path).lstrip('/')).resolve() if url.path else path.resolve()
            if not dest.is_relative_to(root) or not dest.exists():
                errors.append(f'{relative}: missing/outside local link: {target}')
            elif url.fragment and dest.suffix == '.md' and unquote(url.fragment) not in load(dest).headings:
                errors.append(f'{relative}: missing heading: {target}')
    site = check_site(root)
    errors.extend(site['errors'])
    if not files:
        errors.append('No Markdown files found')
    return {'markdown_files': len(files), 'local_links': links, 'swift_examples': examples,
            'command_paths': commands, 'site_pages': site['site_pages'],
            'site_links': site['site_links'], 'errors': errors}


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
        ui.check('Documentation', report['errors'], f"{report['markdown_files']} Markdown files, {report['local_links']} local links")
        return bool(report['errors'])
    except (OSError, ValueError) as error:
        ui.result(False, f'Documentation check failed: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
