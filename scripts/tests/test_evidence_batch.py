"""Batched Git reads preserve exact identity across binary/path edge cases."""
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1]))
import verification_evidence as evidence


class BatchIdentityTests(unittest.TestCase):
    def test_binary_empty_duplicate_newline_and_multiple_batches_match_git(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                # Detached maintenance must not outlive this temporary repository.
                return subprocess.check_output(['git', '-c', 'core.hooksPath=/dev/null',
                                                '-c', 'maintenance.auto=false', *args],
                                               cwd=root, stderr=subprocess.DEVNULL)
            git('init')
            payloads = {'space 日本語\nname': b'\x00\xff\nbody\x00', 'empty': b'', 'duplicate': b'\x00\xff\nbody\x00'}
            payloads.update({f'file-{i}': str(i).encode() for i in range(130)})
            for name, data in payloads.items():
                (root / name).write_bytes(data)
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '--no-gpg-sign', '-m', 'base')
            revision, hashes = evidence.revision_hashes(root, 'HEAD')
            self.assertEqual(revision, git('rev-parse', 'HEAD').decode().strip())
            self.assertEqual(hashes, {name: hashlib.sha256(data).hexdigest() for name, data in payloads.items()})
            (root / 'empty').write_bytes(b'new worktree content')
            self.assertEqual(evidence.revision_hashes(root, revision)[1], hashes)

    def test_truncated_or_wrong_object_is_never_certified(self):
        oid = b'a' * 40
        tree = b'100644 blob ' + oid + b'\tfile\0'
        for payload in [oid + b' blob 5\nabc\n', b'b' * 40 + b' blob 0\n\n', oid + b' blob 0\n\nextra']:
            with self.subTest(payload=payload), patch.object(evidence.subprocess, 'check_output', side_effect=['a' * 40 + '\n', tree]), \
                    patch.object(evidence.subprocess, 'run') as run:
                run.return_value.stdout = payload
                with self.assertRaises(ValueError):
                    evidence.revision_hashes(Path('.'), 'HEAD')
