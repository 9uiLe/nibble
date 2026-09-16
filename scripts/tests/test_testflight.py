"""Distribution boundaries, archive identity, and secret-free responses (no Apple credentials)."""

import base64
import json
import os
from pathlib import Path
import plistlib
import socket
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import testflight as tf


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / 'release.xcarchive'
        self.app = self.archive / 'Products/Applications/Nibble.app'
        self.share = self.app / 'PlugIns/NibbleShare.appex'
        for path, bundle, kind in [(self.app, 'dev.nibble.app', 'APPL'),
                                   (self.share, 'dev.nibble.app.share', 'XPC!')]:
            path.mkdir(parents=True)
            info = {'CFBundleIdentifier': bundle, 'CFBundlePackageType': kind,
                    'CFBundleSupportedPlatforms': ['iPhoneOS'], 'DTPlatformName': 'iphoneos',
                    'DTPlatformVersion': '26.5', 'MinimumOSVersion': '26.0',
                    'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1',
                    'CFBundleExecutable': 'test-executable',
                    'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon'}},
                    'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.share-services'}}
            (path / 'Info.plist').write_bytes(plistlib.dumps(info))
            (path / 'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps({}))
            (path / 'test-executable').write_bytes(b'fixture, not executable')

    def alter(self, path, **values):
        info = plistlib.loads(path.read_bytes())
        info.update(values)
        path.write_bytes(plistlib.dumps(info))

    def test_inspects_device_bundles_without_claiming_signature_validation(self):
        self.assertEqual(tf.archive_info(self.archive)['build'], '1')
        self.assertNotIn('signed', tf.archive_info(self.archive))

    def test_rejects_version_mismatch_and_other_app(self):
        self.alter(self.share / 'Info.plist', CFBundleVersion='2')
        with self.assertRaises(tf.DistributionError):
            tf.archive_info(self.archive)
        self.alter(self.share / 'Info.plist', CFBundleVersion='1', CFBundleIdentifier='another.app.share')
        with self.assertRaises(tf.DistributionError):
            tf.archive_info(self.archive)

    def test_rejects_simulator_and_missing_privacy_manifest(self):
        self.alter(self.app / 'Info.plist', CFBundleSupportedPlatforms=['iPhoneSimulator'])
        with self.assertRaises(tf.DistributionError):
            tf.archive_info(self.archive)
        self.alter(self.app / 'Info.plist', CFBundleSupportedPlatforms=['iPhoneOS'])
        (self.share / 'PrivacyInfo.xcprivacy').unlink()
        with self.assertRaises(OSError):
            tf.archive_info(self.archive)

    def test_digest_detects_changed_content_and_rejects_links_and_writable_files(self):
        before = tf.archive_digest(self.archive, os.geteuid())
        binary = self.app / 'test-executable'
        binary.write_bytes(b'changed')
        self.assertNotEqual(tf.archive_digest(self.archive, os.geteuid()), before)
        link = self.app / 'link'
        link.symlink_to(binary)
        with self.assertRaises(tf.DistributionError):
            tf.archive_digest(self.archive, os.geteuid())
        link.unlink()
        os.link(binary, link)
        with self.assertRaises(tf.DistributionError):
            tf.archive_digest(self.archive, os.geteuid())
        link.unlink()
        binary.chmod(0o666)
        with self.assertRaises(tf.DistributionError):
            tf.archive_digest(self.archive, os.geteuid())

    def test_upload_requires_exact_release_and_never_retries_uncertain_attempt(self):
        service = tf.Service({'key_id': 'EXAMPLEKEY', 'bundle_id': 'dev.nibble.app',
                              'extension_bundle_id': 'dev.nibble.app.share'}, self.root)
        with patch.object(service, 'verify_app') as api, patch.object(tf.subprocess, 'run') as run:
            with self.assertRaises(tf.DistributionError):
                service.upload('0' * 64)
            digest = service.local_release()['release']
            (self.root / 'uploads.json').write_text(json.dumps({digest: 'started'}))
            (self.root / 'uploads.json').chmod(0o600)
            with self.assertRaises(tf.DistributionError):
                service.upload(digest)
            api.assert_not_called()
            run.assert_not_called()

    def test_upload_uses_private_snapshot_and_suppresses_native_output(self):
        config = {'key_id': 'EXAMPLEKEY', 'issuer_id': 'example-issuer', 'team_id': 'EXAMPLETEAM',
                  'bundle_id': 'dev.nibble.app', 'extension_bundle_id': 'dev.nibble.app.share'}
        service = tf.Service(config, self.root)
        service.key_path.touch(mode=0o600)
        digest = service.local_release()['release']
        with patch.object(service, 'verify_app'), patch.object(tf.subprocess, 'run', return_value=Mock(returncode=0)) as run:
            self.assertEqual(service.upload(digest)['upload'], 'accepted')
        args, kwargs = run.call_args
        command = args[0]
        snapshot = self.root / 'exports' / digest / 'Nibble.xcarchive'
        self.assertEqual(command[command.index('-archivePath') + 1], str(snapshot))
        self.assertEqual(tf.archive_digest(snapshot, os.geteuid()), digest)
        self.assertEqual(kwargs['stdout'], tf.subprocess.DEVNULL)
        self.assertEqual(kwargs['stderr'], tf.subprocess.DEVNULL)
        self.assertEqual(set(kwargs['env']), {'HOME', 'PATH', 'LANG'})
        options = plistlib.loads((snapshot.parent / 'ExportOptions.plist').read_bytes())
        self.assertTrue(options['testFlightInternalTestingOnly'])
        self.assertFalse(options['manageAppVersionAndBuildNumber'])

    def test_timeout_leaves_attempt_recorded_and_blocks_automatic_retry(self):
        config = {'key_id': 'EXAMPLEKEY', 'issuer_id': 'example-issuer', 'team_id': 'EXAMPLETEAM',
                  'bundle_id': 'dev.nibble.app', 'extension_bundle_id': 'dev.nibble.app.share'}
        service = tf.Service(config, self.root)
        service.key_path.touch(mode=0o600)
        digest = service.local_release()['release']
        with patch.object(service, 'verify_app'), patch.object(tf.subprocess, 'run',
                side_effect=tf.subprocess.TimeoutExpired('native tool', 1800)):
            with self.assertRaises(tf.subprocess.TimeoutExpired):
                service.upload(digest)
            with self.assertRaises(tf.DistributionError):
                service.upload(digest)
        self.assertEqual(json.loads((self.root / 'uploads.json').read_text())[digest], 'started')


class BoundaryTests(unittest.TestCase):
    def test_configuration_rejects_same_user_and_private_files_with_broad_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / 'config.json'
            path.write_text(json.dumps({'client_uid': 501, 'team_id': 'ABCDEFGHIJ', 'key_id': 'KLMNOPQRST',
                'issuer_id': '00000000-0000-0000-0000-000000000000', 'app_id': '1234567890',
                'bundle_id': 'dev.nibble.app', 'extension_bundle_id': 'dev.nibble.app.share'}))
            path.chmod(0o644)
            with self.assertRaises(tf.DistributionError):
                tf.owned_path(path, os.geteuid(), private=True)
            path.chmod(0o600)
            with patch.object(tf.os, 'geteuid', return_value=501), \
                    patch.object(tf.pwd, 'getpwuid', return_value=Mock(pw_dir=directory)), \
                    patch.object(tf, 'owned_path'):
                with self.assertRaisesRegex(tf.DistributionError, 'must be different'):
                    tf.load_config(path)

    def test_status_returns_only_public_allowlisted_fields(self):
        service = tf.Service({'key_id': 'EXAMPLEKEY', 'app_id': '123'}, Path('/unused'))
        with patch.object(service, 'verify_app'), patch.object(service, 'apple_get', return_value={
                'data': [{'id': 'private-unused-value', 'attributes': {'version': '1',
                    'processingState': 'VALID', 'expired': False, 'extra': 'FAKE_SECRET_FOR_TEST_ONLY'}}]}):
            result = service.status()
        self.assertEqual(result, {'builds': [{'build': '1', 'processing': 'VALID', 'expired': False}],
                                  'staged_release': None})

    def test_only_two_fixed_requests_are_accepted(self):
        tf.validate_request({'action': 'status'})
        tf.validate_request({'action': 'upload', 'release': 'a' * 64})
        for request in [{'action': 'shell', 'command': 'whoami'},
                        {'action': 'status', 'url': 'https://example.com'},
                        {'action': 'upload', 'release': '../private-key'},
                        {'action': 'upload', 'release': 'a' * 64, 'archive': '/tmp/other'}]:
            with self.subTest(request=request), self.assertRaises(tf.DistributionError):
                tf.validate_request(request)

    def connection(self, service, uid=501):
        connection = Mock()
        connection.recv.return_value = b'{"action":"status"}\n'
        with patch.object(tf, 'peer_uid', return_value=uid):
            tf.handle_connection(connection, service, 501)
        return json.loads(connection.sendall.call_args.args[0])

    def test_kernel_peer_identity_checked_before_reading_request_or_key(self):
        service = Mock()
        result = self.connection(service, uid=502)
        self.assertFalse(result['ok'])
        service.handle.assert_not_called()

    def test_exception_details_never_reach_client(self):
        service = Mock()
        service.handle.side_effect = RuntimeError('FAKE_SECRET_FOR_TEST_ONLY')
        result = self.connection(service)
        self.assertFalse(result['ok'])
        self.assertNotIn('FAKE_SECRET_FOR_TEST_ONLY', json.dumps(result))

    def test_real_local_socket_reports_os_user(self):
        left, right = socket.socketpair()
        with left, right:
            self.assertEqual(tf.peer_uid(left), os.geteuid())

    def test_oversized_and_multiple_messages_rejected(self):
        for data in [b'x' * 100, b'{}\n{}\n']:
            connection = Mock()
            connection.recv.return_value = data
            with self.assertRaises(tf.DistributionError):
                tf.read_message(connection, 50)

    def test_apple_http_error_does_not_read_or_return_body(self):
        service = tf.Service({'key_id': 'EXAMPLEKEY'}, Path('/unused'))
        connection = Mock()
        response = connection.getresponse.return_value
        response.status = 401
        with patch.object(service, 'token', return_value='fake-test-token'), \
                patch.object(tf.http.client, 'HTTPSConnection', return_value=connection):
            with self.assertRaisesRegex(tf.DistributionError, '^Apple API returned HTTP 401\\.$'):
                service.apple_get('/v1/apps/123')
        response.read.assert_not_called()

    def test_es256_signature_and_short_read_only_scope_with_ephemeral_test_key(self):
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec, utils
        with tempfile.TemporaryDirectory() as directory:
            service = tf.Service({'key_id': 'EXAMPLEKEY', 'issuer_id': 'test-issuer'}, Path(directory))
            key = ec.generate_private_key(ec.SECP256R1())
            service.key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
            service.key_path.chmod(0o600)
            token = service.token('/v1/apps/123')
            header, payload, signature = token.split('.')
            decode = lambda value: base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))
            claims = json.loads(decode(payload))
            self.assertEqual(claims['exp'] - claims['iat'], 120)
            self.assertEqual(claims['scope'], ['GET /v1/apps/123'])
            raw = decode(signature)
            self.assertEqual(len(raw), 64)
            der = utils.encode_dss_signature(int.from_bytes(raw[:32], 'big'), int.from_bytes(raw[32:], 'big'))
            key.public_key().verify(der, (header + '.' + payload).encode(), ec.ECDSA(hashes.SHA256()))


if __name__ == '__main__':
    unittest.main()
