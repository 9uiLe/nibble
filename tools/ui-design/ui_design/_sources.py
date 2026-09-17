"""Filesystem Adapter. Capture hashes and document text from the same bytes."""

from dataclasses import dataclass
from fnmatch import fnmatchcase
from hashlib import sha256
from pathlib import Path
import stat

from ._policy import Policy, relative_path

_CHUNK_BYTES = 128 * 1024


@dataclass(frozen=True, slots=True)
class CapturedInputs:
    files: dict[str, str]
    documents: dict[str, str]


def _walk_error(error):
    raise error


def _excluded(name, patterns):
    return any(fnmatchcase(name, pattern) for pattern in patterns)


class Repository:
    def __init__(self, root):
        self.root = Path(root).resolve()

    def _path(self, name):
        # Canonical relative paths cannot escape this root; check each ancestor once.
        path = self.root
        for part in relative_path(name).split('/'):
            path = path / part
            if path.is_symlink():
                raise ValueError(f'Input must not use symlinks: {name}')
        return path

    def _file(self, name):
        path = self._path(name)
        if not stat.S_ISREG(path.stat().st_mode):
            raise ValueError(f'Input must be a regular file: {name}')
        return path

    def read(self, name) -> bytes:
        return self._file(name).read_bytes()

    def review(self, name) -> bytes | None:
        try:
            return self.read(name)
        except FileNotFoundError:
            return None

    def _names(self, policy):
        # References are unioned for overlapping inputs; each file is read only once.
        names = {policy.config: False}
        for item in policy.inputs:
            path = self._path(item.path)
            if item.kind == 'file':
                collected = [item.path]
            else:
                if not path.is_dir():
                    raise ValueError(f'Missing input directory: {item.path}')
                collected = []
                for parent, folders, files in path.walk(on_error=_walk_error, follow_symlinks=False):
                    folders[:] = sorted(name for name in folders if not _excluded(name, item.exclude_directories))
                    collected.extend((parent / name).relative_to(self.root).as_posix()
                                     for name in sorted(files) if not _excluded(name, item.exclude_files)
                                     and (parent / name).relative_to(self.root).as_posix() != policy.record)
                if not collected:
                    raise ValueError(f'No inputs found under: {item.path}')
            for name in collected:
                names[name] = names.get(name, False) or (item.references and name.endswith('.md'))
        return names

    def capture(self, policy: Policy, config_bytes: bytes) -> CapturedInputs:
        self._path(policy.record)  # Validate the destination even when proposing a record.
        hashes, documents = {}, {}
        for name, document in sorted(self._names(policy).items()):
            if name == policy.config:
                content = config_bytes  # Hash the configuration that was actually decoded.
                hashes[name] = sha256(content).hexdigest()
                if document:
                    documents[name] = content.decode('utf-8')
                continue
            path = self._file(name)
            if document:
                content = path.read_bytes()
                hashes[name] = sha256(content).hexdigest()
                documents[name] = content.decode('utf-8')
            else:
                digest = sha256()
                with path.open('rb') as source:
                    while chunk := source.read(_CHUNK_BYTES):
                        digest.update(chunk)
                hashes[name] = digest.hexdigest()
        return CapturedInputs(hashes, documents)
