"""Reject obsolete or modified generated runtime packages before Xcode uses them."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
import build_rive_runtime as runtime


class RuntimeCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.package = Path(self.temp.name)
        self.identity = {'patch_sha256': 'patch-one', 'xcode': 'Xcode 26.5', 'sources': {'rive-ios': 'fixed-source'}}
        (self.package / 'Package.swift').write_text('fixture package')
        framework = self.package / 'RiveRuntime.xcframework'
        framework.mkdir()
        (framework / 'Info.plist').write_bytes(b'fixture info')
        (framework / 'RiveRuntime').write_bytes(b'fixture binary')
        self.manifest = {'inputs': self.identity, 'files_sha256': runtime.package_hashes(self.package)}
        self.write_manifest()

    def write_manifest(self):
        (self.package / 'build-manifest.json').write_text(json.dumps(self.manifest))

    def test_reuses_identical_inputs_and_unchanged_framework(self):
        self.assertTrue(runtime.cache_valid(self.package, self.identity))

    def test_patch_toolchain_or_source_change_invalidates_cache(self):
        for key, value in [('patch_sha256', 'patch-two'), ('xcode', 'Xcode 27'), ('sources', {'rive-ios': 'other'})]:
            with self.subTest(key=key):
                self.assertFalse(runtime.cache_valid(self.package, {**self.identity, key: value}))

    def test_modified_deleted_or_extra_framework_file_invalidates_cache(self):
        binary = self.package / 'RiveRuntime.xcframework/RiveRuntime'
        binary.write_bytes(b'tampered')
        self.assertFalse(runtime.cache_valid(self.package, self.identity))
        binary.unlink()
        self.assertFalse(runtime.cache_valid(self.package, self.identity))
        binary.write_bytes(b'fixture binary')
        (binary.parent / 'extra').write_bytes(b'not recorded')
        self.assertFalse(runtime.cache_valid(self.package, self.identity))

    def test_incomplete_or_malformed_manifest_is_not_a_build(self):
        self.manifest['files_sha256'] = {}
        self.write_manifest()
        self.assertFalse(runtime.cache_valid(self.package, self.identity))
        (self.package / 'build-manifest.json').write_text('{')
        self.assertFalse(runtime.cache_valid(self.package, self.identity))

    def test_read_only_nix_headers_can_be_removed_before_next_platform_build(self):
        import shutil
        source = self.package / 'readonly'
        source.mkdir()
        header = source / 'header.h'
        header.write_text('fixture')
        header.chmod(0o444)
        source.chmod(0o555)
        target = self.package / 'writable'
        try:
            runtime.writable_copy(source, target)
            self.assertTrue(target.stat().st_mode & 0o200)
            self.assertTrue((target / 'header.h').stat().st_mode & 0o200)
            shutil.rmtree(target)
        finally:
            source.chmod(0o755)


if __name__ == '__main__':
    unittest.main()
