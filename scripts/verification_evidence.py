"""Source and media identity for local iOS runs; no Apple SDK dependency."""

import hashlib
from pathlib import Path
import subprocess


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def working_hashes(root):
    names = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=root
    ).decode().split('\0')
    return {name: digest(root / name) for name in sorted(set(names))
            if name and (root / name).is_file()}


def revision_hashes(root, revision):
    commit = subprocess.check_output(
        ['git', 'rev-parse', '--verify', revision + '^{commit}'], cwd=root, text=True
    ).strip()
    tree = subprocess.check_output(['git', 'ls-tree', '-rz', '--full-tree', commit], cwd=root)
    blobs = []
    for row in tree.split(b'\0'):
        if not row:
            continue
        metadata, name = row.split(b'\t', 1)
        _, kind, oid = metadata.split()
        if kind != b'blob':
            raise ValueError('Unsupported revision entry: ' + name.decode())
        blobs.append((oid, name.decode()))
    hashes = {}
    # One process per bounded batch, rather than one `git show` per file.
    # Binary content and filenames containing newlines remain unambiguous.
    for index in range(0, len(blobs), 128):
        batch = blobs[index:index + 128]
        payload = subprocess.run(['git', 'cat-file', '--batch'], cwd=root, check=True,
                                 input=b'\n'.join(oid for oid, _ in batch) + b'\n',
                                 capture_output=True).stdout
        offset = 0
        for oid, name in batch:
            end = payload.index(b'\n', offset)
            header = payload[offset:end].split()
            if len(header) != 3 or header[:2] != [oid, b'blob']:
                raise ValueError('Unexpected Git object for ' + name)
            size = int(header[2])
            offset = end + 1
            if size < 0 or len(payload) < offset + size + 1 or payload[offset + size:offset + size + 1] != b'\n':
                raise ValueError('Incomplete Git object for ' + name)
            hashes[name] = hashlib.sha256(payload[offset:offset + size]).hexdigest()
            offset += size + 1
        if offset != len(payload):
            raise ValueError('Unexpected trailing Git object data')
    return commit, hashes


def inputs(hashes, project):
    """Include target sources/settings/tests and every shared driver/tool input.

    Markdown changes do not require repeating an iOS run. File additions and
    deletions matter just as much as content changes. Scope cannot be narrowed
    from the CLI to make an obsolete run pass.
    """
    project_path = Path(project['project'])
    if project_path.is_absolute() or '..' in project_path.parts or not (project_path.parts[0] in {'app', 'validation'} or project_path.parts[:2] == ('research', 'probe')):
        raise ValueError('Expected a project under app/, validation/ or research/probe/')
    prefixes = (('research/probe/' if project_path.parts[0] == 'research' else project_path.parts[0] + '/'), 'scripts/')
    return {name: value for name, value in hashes.items()
            if not name.endswith('.md') and (name.startswith(prefixes) or name in {'flake.nix', 'flake.lock'})}


def differences(before, after):
    return sorted(name for name in before.keys() | after.keys() if before.get(name) != after.get(name))


def media_hashes(directory):
    return {p.relative_to(directory).as_posix(): digest(p)
            for p in sorted(directory.rglob('*')) if p.is_file()
            and (p.suffix in {'.png', '.mp4'} or p.name == 'video.json')
            and not any(part.endswith('.xcresult') for part in p.relative_to(directory).parts)}
