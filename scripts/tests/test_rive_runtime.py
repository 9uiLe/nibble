"""Reject obsolete or modified generated runtime packages before Xcode uses them."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
import rive_runtime as runtime


class RuntimeCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.package = Path(self.temp.name)
        self.identity = {'definition_sha256': {'drawable-acquisition.patch': 'one'},
                         'xcode': 'Xcode 26.5', 'sources': {'rive-ios': 'fixed-source'}}
        (self.package / 'Package.swift').write_text('fixture package')
        framework = self.package / 'RiveRuntime.xcframework'
        framework.mkdir()
        (framework / 'Info.plist').write_bytes(b'fixture info')
        (framework / 'RiveRuntime').write_bytes(b'fixture binary')
        self.manifest = {'inputs': self.identity, 'files_sha256': runtime.package_hashes(self.package)}
        self.write_manifest()

    def write_manifest(self):
        (self.package / 'build-manifest.json').write_text(json.dumps(self.manifest))

    def test_patch_toolchain_or_source_change_invalidates_cache(self):
        self.assertTrue(runtime.cache_valid(self.package, self.identity))
        for key, value in [('definition_sha256', {'drawable-acquisition.patch': 'two'}),
                           ('xcode', 'Xcode 27'), ('sources', {'rive-ios': 'other'})]:
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

    def test_nested_manifest_cannot_hide_an_unrecorded_file(self):
        (self.package / 'RiveRuntime.xcframework/build-manifest.json').write_text('{}')
        self.assertFalse(runtime.cache_valid(self.package, self.identity))

    def test_package_configuration_and_dependency_resolver_are_build_inputs(self):
        definition = self.package / 'definition'
        definition.mkdir()
        expected = {'Package.swift', 'build.json', 'dependency.lua', 'drawable-acquisition.patch'}
        for name in expected:
            (definition / name).write_text('input')
        before = runtime.definition_hashes(definition)
        self.assertEqual(set(before), expected)
        (definition / 'README.md').write_text('documentation')
        self.assertEqual(before, runtime.definition_hashes(definition))
        for name in expected:
            with self.subTest(name=name):
                (definition / name).write_text('changed')
                self.assertNotEqual(before, runtime.definition_hashes(definition))
                (definition / name).write_text('input')

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
