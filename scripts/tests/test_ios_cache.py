"""Build cache separation never replaces Xcode/source validation."""
from pathlib import Path
import plistlib
import tempfile
from types import SimpleNamespace
import unittest
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import ios


class BuildCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run = ios.Run.__new__(ios.Run)
        self.run.args = SimpleNamespace(device='12345678-1234-1234-1234-123456789abc', configuration='Release')
        self.run.path = self.root / 'run'
        self.run.path.mkdir()
        self.run.config = {'project': 'app/Nibble.xcodeproj', 'scheme': 'Nibble', 'bundle_id': 'nibble.example', 'app_name': 'Nibble'}
        self.run.manifest = {'commands': [], 'environment': {'xcode': '26.5', 'swift': '6.3', 'simulator_sdk': '26.5', 'developer_dir': '/Xcode'}}
        for name in ['boot', 'command']:
            patcher = patch.object(self.run, name)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.run.command.return_value = '{}'
        patcher = patch.object(ios, 'ARTIFACTS', self.root)
        patcher.start()
        self.addCleanup(patcher.stop)

    def build(self, test=False):
        with patch.object(ios, 'validate_summary'):
            self.run.build(test=test)
        return self.run.derived

    def test_testability_configuration_project_sdk_and_architecture_partition_cache(self):
        original = self.build()
        with patch.object(ios.platform, 'machine', return_value='another-arch'):
            self.assertNotEqual(original, self.build())
        self.assertNotEqual(original, self.build(test=True))
        self.run.args.configuration = 'Debug'
        self.assertNotEqual(original, self.build())
        self.run.args.configuration = 'Release'
        self.run.config['scheme'] = 'Another'
        self.assertNotEqual(original, self.build())
        self.run.config['scheme'] = 'Nibble'
        self.run.manifest['environment']['simulator_sdk'] = '27.0'
        self.assertNotEqual(original, self.build())

    def test_existing_output_still_invokes_xcodebuild(self):
        original = self.build()
        original.mkdir(parents=True)
        self.run.command.reset_mock()
        self.assertEqual(original, self.build())
        argv = self.run.command.call_args.args[0]
        self.assertEqual(argv[-1], 'build')
        self.assertIn('ONLY_ACTIVE_ARCH=YES', argv)
        self.assertIn('-disableAutomaticPackageResolution', argv)
        first = self.run.command.call_args_list[0]
        self.assertEqual(first.args[1], 'prepare-rive-runtime')
        self.assertEqual(first.args[0][-2:], [ios.ROOT / 'scripts/rive_runtime.py', 'prepare'])

    def test_runtime_preparation_failure_stops_before_xcodebuild(self):
        self.run.command.side_effect = ios.VerificationError('runtime build failed')
        with self.assertRaisesRegex(ios.VerificationError, 'runtime build failed'):
            self.build()
        self.assertEqual(self.run.command.call_count, 1)

    def test_incomplete_or_wrong_products_never_reach_install(self):
        self.build()
        app = self.run.derived / 'Build/Products/Release-iphonesimulator/Nibble.app'
        app.mkdir(parents=True)
        info = {'CFBundleIdentifier': 'nibble.example', 'CFBundleExecutable': 'Nibble'}
        for wrong in [None, {**info, 'CFBundleIdentifier': 'another.app'}, info,
                      {**info, 'CFBundleExecutable': '../outside'}]:
            if wrong is not None:
                (app / 'Info.plist').write_bytes(plistlib.dumps(wrong))
            self.run.command.reset_mock()
            with self.assertRaises(ios.VerificationError):
                self.run.launch()
            self.assertTrue(all('install' not in call.args[0] for call in self.run.command.call_args_list))
        (app / 'Info.plist').write_bytes(plistlib.dumps(info))
        (app / 'Nibble').write_bytes(b'compiled fixture')
        ios.validate_app(app, 'nibble.example')

    def test_device_lock_remains_exclusive_across_independent_runs(self):
        other = ios.Run.__new__(ios.Run)
        other.args = self.run.args
        with patch.object(ios.tempfile, 'gettempdir', return_value=str(self.root)):
            with ios.simulator_lock(self.run.args.device):
                with self.assertRaisesRegex(ios.VerificationError, 'Another'):
                    with ios.simulator_lock(other.args.device):
                        self.fail('A second owner acquired the Simulator')
            with ios.simulator_lock(other.args.device):
                pass
