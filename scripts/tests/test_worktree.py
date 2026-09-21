"""Exercise the pinned wts against disposable repositories, without network or iOS."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class WorktreeConfigTests(unittest.TestCase):
    def test_shared_configuration_has_no_automatic_copy_or_naming_commands(self):
        self.assertEqual(json.loads((ROOT / '.wts.json').read_text()), {
            'baseBranch': 'main', 'worktreeDirectory': '../nibble-worktrees'})
        self.assertFalse((ROOT / '.worktree-copy').exists())


@unittest.skipUnless(platform.system() == 'Darwin' and platform.machine() == 'arm64',
                     'Pinned wts supports Apple Silicon macOS')
class WorktreeIntegrationTests(unittest.TestCase):
    def test_concurrent_sessions_isolate_files_and_reject_name_collision(self):
        self.assertIsNotNone(shutil.which('wts'), 'Use the locked Nix development shell')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'nibble'
            root.mkdir()

            def git(*args, cwd=root):
                return subprocess.check_output(['git', '-c', 'core.hooksPath=/dev/null',
                                                '-c', 'maintenance.auto=false', *args],
                                               cwd=cwd, stderr=subprocess.DEVNULL, text=True)

            def wts(*args, cwd=root):
                return subprocess.run(['wts', '--format', 'json', *args], cwd=cwd,
                                      capture_output=True, text=True, timeout=60)

            git('init', '-b', 'main')
            shutil.copyfile(ROOT / '.wts.json', root / '.wts.json')
            (root / '.gitignore').write_text('/artifacts/\n')
            (root / 'shared.txt').write_text('base')
            (root / 'artifacts').mkdir()
            (root / 'artifacts/private.txt').write_text('not for copying')
            git('add', '.')
            git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                'commit', '--no-gpg-sign', '-m', 'fixture')
            self.assertEqual(wts('config', 'check').returncode, 0)

            def start(name):
                return wts('start', '--branch', 'feature/' + name, '--worktree', name,
                           '--base-branch', 'main')

            with ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(start, ('one', 'two')))
            for result in results:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                for line in result.stdout.splitlines():
                    self.assertIsInstance(json.loads(line), dict)
            one, two = (Path(directory) / 'nibble-worktrees' / name for name in ('one', 'two'))
            for path in (one, two):
                self.assertFalse((path / 'artifacts').exists())
                self.assertEqual(wts('config', 'check', cwd=path).returncode, 0)
                self.assertIn('../nibble-worktrees', (path / '.wts.json').read_text())
            (one / 'shared.txt').write_text('one only')
            self.assertEqual((two / 'shared.txt').read_text(), 'base')
            self.assertEqual((root / 'shared.txt').read_text(), 'base')
            self.assertNotEqual(start('one').returncode, 0)
            self.assertEqual((one / 'shared.txt').read_text(), 'one only')
            self.assertEqual(git('branch', '--show-current', cwd=two).strip(), 'feature/two')
            listing = wts('list', cwd=one)
            self.assertEqual(listing.returncode, 0, listing.stdout + listing.stderr)
            self.assertIn(str(one), listing.stdout)
            self.assertIn(str(two), listing.stdout)
            self.assertEqual(git('worktree', 'list', '--porcelain').count('worktree '), 3)
