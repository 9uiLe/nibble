"""Archive and deployment behavior using disposable fixtures, never real credentials."""

from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import testflight as tf


def make_archive(archive, build='1'):
    app = archive / 'Products/Applications/Nibble.app'
    share = app / 'PlugIns/NibbleShare.appex'
    for path, identifier, kind in [(app, 'nibble.9uiLe.com', 'APPL'), (share, 'nibble.9uiLe.com.share', 'XPC!')]:
        path.mkdir(parents=True)
        info = {'CFBundleIdentifier': identifier, 'CFBundlePackageType': kind,
                'CFBundleSupportedPlatforms': ['iPhoneOS'], 'DTPlatformName': 'iphoneos',
                'DTPlatformVersion': '26.5', 'MinimumOSVersion': '26.0',
                'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': build,
                'CFBundleExecutable': 'fixture',
                'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon'}},
                'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.share-services'}}
        (path / 'Info.plist').write_bytes(plistlib.dumps(info))
        (path / 'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps({}))
        (path / 'fixture').write_bytes(b'not executable')
    return app, share


class Fixture(unittest.TestCase):
    def setUp(self):
        original_umask = os.umask(0o077)
        self.addCleanup(os.umask, original_umask)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.credentials = self.home / '.appstoreconnect'
        self.credentials.mkdir(parents=True, mode=0o700)
        self.values = {'ASC_KEY_ID': 'ABCDEFGHIJ', 'ASC_TEAM_ID': 'KLMNOPQRST',
                       'ASC_ISSUER_ID': '00000000-0000-0000-0000-000000000000',
                       'ASC_KEY_PATH': str(self.credentials / 'AuthKey_ABCDEFGHIJ.p8')}
        self.key = Path(self.values['ASC_KEY_PATH'])
        self.key.write_text('FAKE_KEY_CONTENT_MUST_NOT_BE_READ')
        self.key.chmod(0o600)
        self.env = self.credentials / 'nibble.env'
        self.env.write_text('\n'.join(name + '=' + value for name, value in self.values.items()))
        self.env.chmod(0o600)

    def deployment(self, dry_run=False):
        with patch.object(tf, 'source_commit', return_value='a' * 40):
            return tf.Deployment(self.root / 'repository', self.home, self.values, '1', dry_run)


class CredentialTests(Fixture):
    def test_loads_only_metadata_without_opening_the_key(self):
        self.env.write_text(self.env.read_text().replace(str(self.home), '$HOME'))
        original = Path.open

        def open_checked(path, *args, **kwargs):
            self.assertNotEqual(path, self.key, 'The deployment wrapper must not read private key bytes')
            return original(path, *args, **kwargs)

        with patch.object(Path, 'open', open_checked):
            self.assertEqual(tf.load_credentials(self.home), self.values)

    def test_rejects_shell_expressions_unknown_and_duplicate_fields(self):
        contents = self.env.read_text()
        for value in [contents + '\nASC_KEY_ID=ABCDEFGHIJ', contents + '\nRUN_COMMAND=anything',
                      contents.replace(self.values['ASC_KEY_PATH'], '$(id)'),
                      contents.replace(self.values['ASC_KEY_PATH'], '/tmp/AuthKey_ABCDEFGHIJ.p8')]:
            self.env.write_text(value)
            with self.subTest(value=value), self.assertRaises(tf.DistributionError), \
                    patch.object(tf.subprocess, 'run') as process:
                tf.load_credentials(self.home)
            process.assert_not_called()

    def test_rejects_broad_permissions_and_symlinks(self):
        self.env.chmod(0o644)
        with self.assertRaises(tf.DistributionError):
            tf.load_credentials(self.home)
        self.env.chmod(0o600)
        self.key.unlink()
        self.key.symlink_to(self.env)
        with self.assertRaises(tf.DistributionError):
            tf.load_credentials(self.home)

    def test_check_config_prints_no_values_and_makes_no_native_calls(self):
        output = io.StringIO()
        with patch.object(tf.Path, 'home', return_value=self.home), patch.object(tf.sys, 'platform', 'darwin'), \
                patch.object(tf.sys, 'argv', ['testflight.py', 'deploy', '--check-config']), \
                patch.object(tf.subprocess, 'run') as native, redirect_stdout(output):
            self.assertEqual(tf.main(), 0)
        native.assert_not_called()
        self.assertIn('利用可能', output.getvalue())
        for value in self.values.values():
            self.assertNotIn(value, output.getvalue())

    def test_configuration_failure_does_not_print_exception_details(self):
        output = io.StringIO()
        with patch.object(tf.sys, 'platform', 'darwin'), \
                patch.object(tf.sys, 'argv', ['testflight.py', 'deploy', '--check-config']), \
                patch.object(tf, 'load_credentials', side_effect=OSError('FAKE_SECRET')), \
                redirect_stderr(output):
            self.assertEqual(tf.main(), 1)
        self.assertNotIn('FAKE_SECRET', output.getvalue())


class ArchiveTests(Fixture):
    def test_device_bundle_versions_and_privacy_resources(self):
        archive = self.root / 'Nibble.xcarchive'
        app, share = make_archive(archive)
        self.assertEqual(tf.archive_info(archive)['build'], '1')
        path = share / 'Info.plist'
        info = plistlib.loads(path.read_bytes())
        info['CFBundleVersion'] = '2'
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaises(tf.DistributionError):
            tf.archive_info(archive)
        info['CFBundleVersion'] = '1'
        info['CFBundleSupportedPlatforms'] = ['iPhoneSimulator']
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaises(tf.DistributionError):
            tf.archive_info(archive)
        info['CFBundleSupportedPlatforms'] = ['iPhoneOS']
        path.write_bytes(plistlib.dumps(info))
        (app / 'PrivacyInfo.xcprivacy').unlink()
        with self.assertRaises(OSError):
            tf.archive_info(archive)

    def test_other_app_is_rejected(self):
        archive = self.root / 'Nibble.xcarchive'
        app, _ = make_archive(archive)
        path = app / 'Info.plist'
        info = plistlib.loads(path.read_bytes())
        info['CFBundleIdentifier'] = 'another.app'
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaises(tf.DistributionError):
            tf.archive_info(archive)


class DeploymentTests(Fixture):
    def test_clean_commit_and_no_tracked_signing_files_are_required(self):
        for outputs in [['a' * 40, b' M app/file.swift'], ['a' * 40, b'', b'keys/secret.p8\0']]:
            with patch.object(tf.subprocess, 'check_output', side_effect=outputs), self.assertRaises(tf.DistributionError):
                tf.source_commit(self.root)

    def test_concurrent_deployments_are_rejected_and_lock_is_released(self):
        with tf.deployment_lock(self.root):
            with self.assertRaises(tf.DistributionError), tf.deployment_lock(self.root):
                self.fail('A second deployment must not start')
        with tf.deployment_lock(self.root):
            pass

    def test_same_build_cannot_silently_overwrite_an_attempt(self):
        self.deployment()
        with self.assertRaises(tf.DistributionError):
            self.deployment()

    def execute_fake(self, dry_run, create_ipa=True):
        run = self.deployment(dry_run)
        calls = []

        def native(stage, command, timeout):
            calls.append((stage, command))
            if stage == 'archive':
                make_archive(run.archive)
            if stage == 'export' and create_ipa:
                (run.path / 'export').mkdir()
                (run.path / 'export/Nibble.ipa').touch()

        output = io.StringIO()
        with patch.object(run, 'native', side_effect=native), patch.object(run, 'unchanged'), \
                patch.object(tf.shutil, 'which', return_value='/test/nix'), \
                patch.object(tf.subprocess, 'check_output', return_value='26.5'), redirect_stdout(output):
            run.execute()
        return run, calls, output.getvalue()

    def test_dry_run_exports_only_and_keeps_secrets_out_of_summary_and_manifest(self):
        run, calls, output = self.execute_fake(True)
        self.assertEqual([stage for stage, _ in calls], ['checks', 'resolve', 'archive', 'export'])
        options = plistlib.loads((run.logs / 'ExportOptions.plist').read_bytes())
        self.assertEqual(options['destination'], 'export')
        self.assertTrue(options['testFlightInternalTestingOnly'])
        self.assertFalse(options['manageAppVersionAndBuildNumber'])
        for value in self.values.values():
            self.assertNotIn(value, output + json.dumps(run.manifest))
        self.assertTrue(run.manifest['completed'])
        archive_command = dict(calls)['archive']
        self.assertNotIn('-skipMacroValidation', archive_command)
        self.assertIn('-onlyUsePackageVersionsFromResolvedFile', archive_command)
        self.assertIn('CURRENT_PROJECT_VERSION=1', archive_command)

    def test_upload_uses_native_export_with_api_authentication(self):
        run, calls, _ = self.execute_fake(False)
        options = plistlib.loads((run.logs / 'ExportOptions.plist').read_bytes())
        self.assertEqual(options['destination'], 'upload')
        command = dict(calls)['upload']
        self.assertEqual(command[0], '/usr/bin/xcodebuild')
        self.assertIn('-exportArchive', command)
        self.assertEqual(command[command.index('-authenticationKeyPath') + 1], self.values['ASC_KEY_PATH'])

    def test_missing_exported_ipa_is_not_reported_as_success(self):
        with self.assertRaises(tf.DistributionError):
            self.execute_fake(True, create_ipa=False)

    def test_source_change_stops_before_upload(self):
        run = self.deployment()
        with patch.object(run, 'native') as native, patch.object(run, 'unchanged',
                side_effect=tf.DistributionError('changed')), patch.object(tf.shutil, 'which', return_value='/test/nix'):
            with self.assertRaises(tf.DistributionError):
                run.execute()
        self.assertEqual(native.call_count, 1)

    def test_native_errors_and_timeouts_never_return_raw_output_or_inherited_credentials(self):
        run = self.deployment()

        def failure(command, **kwargs):
            self.assertEqual(set(kwargs['env']) - {'DEVELOPER_DIR'}, {'HOME', 'PATH', 'LANG'})
            kwargs['stdout'].write(b'FAKE_BEARER_TOKEN')
            return Mock(returncode=65)

        with patch.object(tf.subprocess, 'run', side_effect=failure), redirect_stdout(io.StringIO()):
            with self.assertRaises(tf.DistributionError) as failure_result:
                run.native('archive', ['native', 'FAKE_SECRET'], 10)
        self.assertNotIn('FAKE', str(failure_result.exception))
        with patch.object(tf.subprocess, 'run', side_effect=tf.subprocess.TimeoutExpired('FAKE_SECRET', 10)), \
                redirect_stdout(io.StringIO()), self.assertRaises(tf.DistributionError) as timeout_result:
            run.native('upload', ['native'], 10)
        self.assertNotIn('FAKE', str(timeout_result.exception))

    def test_build_number_rejects_paths_flags_and_non_numeric_versions(self):
        for value in ['../1', '-1', '1.2.3.4', '1.01', 'a', '1' * 19]:
            with self.subTest(value=value), self.assertRaises(tf.DistributionError):
                tf.build_number(value)
        self.assertEqual(tf.build_number('1'), '1')
        self.assertEqual(tf.build_number('202609161200'), '202609161200')


if __name__ == '__main__':
    unittest.main()
