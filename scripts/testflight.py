#!/usr/bin/env python3
"""Inspect archives and request a narrowly scoped, separate-user TestFlight service."""

import argparse
import base64
import ctypes
import hashlib
import http.client
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import shutil
import socket
import ssl
import stat
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlencode

SOCKET = Path('/Users/Shared/nibble-testflight/control.sock')
MAX_MESSAGE = 4096


class DistributionError(Exception):
    """Only fixed, non-secret messages may cross the service boundary."""


def require(condition, message):
    if not condition:
        raise DistributionError(message)


def archive_info(archive, bundle_id='dev.nibble.app', extension_id='dev.nibble.app.share'):
    app = archive / 'Products/Applications/Nibble.app'
    extension = app / 'PlugIns/NibbleShare.appex'
    require(sorted(p.name for p in (archive / 'Products/Applications').iterdir()) == ['Nibble.app'],
            'Archive must contain only Nibble.app.')
    require(sorted(p.name for p in (app / 'PlugIns').iterdir()) == ['NibbleShare.appex'],
            'Archive must contain only the expected share extension.')
    values = []
    for path, identifier, kind in [(app, bundle_id, 'APPL'), (extension, extension_id, 'XPC!')]:
        with (path / 'Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        require(info.get('CFBundleIdentifier') == identifier, 'Unexpected bundle identifier.')
        require(info.get('CFBundlePackageType') == kind, 'Unexpected bundle type.')
        require(info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], 'Device archive required.')
        require(info.get('MinimumOSVersion') == '26.0', 'Minimum iOS must remain 26.0.')
        require(info.get('DTPlatformName') == 'iphoneos', 'Device SDK required.')
        require(info.get('DTPlatformVersion') == '26.5', 'Use the verified iOS 26.5 SDK.')
        executable = info.get('CFBundleExecutable', '')
        require(bool(executable) and Path(executable).name == executable and (path / executable).is_file(),
                'Missing bundle executable.')
        with (path / 'PrivacyInfo.xcprivacy').open('rb') as stream:
            require(isinstance(plistlib.load(stream), dict), 'Missing privacy manifest.')
        values.append(info)
    app_info, share_info = values
    for key in ['CFBundleShortVersionString', 'CFBundleVersion']:
        require(bool(app_info.get(key)) and app_info[key] == share_info.get(key),
                'App and extension versions must match.')
        require(isinstance(app_info[key], str) and re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', app_info[key]),
                'Use numeric release and build versions.')
    require(share_info.get('NSExtension', {}).get('NSExtensionPointIdentifier') == 'com.apple.share-services',
            'Share extension configuration is missing.')
    require(bool(app_info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconName')),
            'App icon configuration is missing.')
    return {'bundle_id': bundle_id, 'extension_bundle_id': extension_id,
            'version': app_info['CFBundleShortVersionString'], 'build': app_info['CFBundleVersion'],
            'minimum_ios': '26.0', 'sdk': '26.5'}


def owned_path(path, uid, private=False):
    info = path.lstat()
    require(not stat.S_ISLNK(info.st_mode) and info.st_uid == uid,
            'Service paths must be owned by the distribution user and cannot be symlinks.')
    require(not info.st_mode & (0o077 if private else 0o022),
            'Service path permissions are too broad.')
    return info


def archive_digest(archive, uid):
    """Hash names and bytes; reject links/special files and client-writable inputs."""
    owned_path(archive, uid)
    digest = hashlib.sha256()
    for path in sorted(archive.rglob('*')):
        info = owned_path(path, uid)
        require(stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode), 'Special archive files are forbidden.')
        if stat.S_ISREG(info.st_mode):
            require(info.st_nlink == 1, 'Hard links are forbidden in the staged archive.')
            with path.open('rb') as stream:
                value = hashlib.file_digest(stream, 'sha256').digest()
            digest.update(path.relative_to(archive).as_posix().encode() + b'\0' + value)
    return digest.hexdigest()


def peer_uid(connection):
    if sys.platform == 'darwin':
        uid, gid = ctypes.c_uint(), ctypes.c_uint()
        libc = ctypes.CDLL(None, use_errno=True)
        require(libc.getpeereid(connection.fileno(), ctypes.byref(uid), ctypes.byref(gid)) == 0,
                'Cannot verify the local peer.')
        return uid.value
    if sys.platform.startswith('linux'):
        import struct
        return struct.unpack('3i', connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))[1]
    raise DistributionError('Peer identity is unsupported on this OS.')


def read_message(connection, limit):
    data = bytearray()
    while b'\n' not in data:
        part = connection.recv(min(4096, limit + 1 - len(data)))
        require(bool(part), 'Incomplete request.')
        data.extend(part)
        require(len(data) <= limit, 'Message is too large.')
    require(data.endswith(b'\n') and data.count(b'\n') == 1, 'One JSON message is required.')
    value = json.loads(data)
    require(isinstance(value, dict), 'JSON object required.')
    return value


def validate_request(request):
    require(request == {'action': 'status'} or (
        set(request) == {'action', 'release'} and request['action'] == 'upload'
        and isinstance(request['release'], str) and re.fullmatch('[0-9a-f]{64}', request['release'])),
        'Only status or upload of an approved release is allowed.')


def load_config(path):
    uid = os.geteuid()
    require(uid != 0, 'Run as the dedicated standard user, never root.')
    home = Path(pwd.getpwuid(uid).pw_dir)
    require(path.is_absolute() and path.is_relative_to(home), 'Keep service state in the dedicated home.')
    current = home
    owned_path(current, uid, private=True)
    for part in path.relative_to(home).parts[:-1]:
        current = current / part
        owned_path(current, uid, private=True)
    owned_path(path, uid, private=True)
    config = json.loads(path.read_text())
    require(set(config) == {'client_uid', 'team_id', 'key_id', 'issuer_id', 'app_id',
                            'bundle_id', 'extension_bundle_id'}, 'Invalid service configuration fields.')
    require(type(config['client_uid']) is int and config['client_uid'] > 0 and config['client_uid'] != uid,
            'The client and distribution users must be different.')
    for key in ['team_id', 'key_id']:
        require(isinstance(config[key], str) and re.fullmatch('[A-Z0-9]{10}', config[key]),
                'Invalid Apple identifier.')
    require(isinstance(config['issuer_id'], str)
            and re.fullmatch('[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', config['issuer_id']),
            'Invalid issuer identifier.')
    require(isinstance(config['app_id'], str) and re.fullmatch('[0-9]+', config['app_id']), 'Invalid app ID.')
    for key in ['bundle_id', 'extension_bundle_id']:
        require(isinstance(config[key], str) and re.fullmatch('[A-Za-z0-9.-]+', config[key]), 'Invalid bundle ID.')
    return config


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=')


def save_journal(path, value):
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


class Service:
    def __init__(self, config, directory):
        self.config = config
        self.directory = directory
        self.key_path = directory / f'AuthKey_{config["key_id"]}.p8'
        self.archive = directory / 'release.xcarchive'

    def token(self, path):
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec, utils
        owned_path(self.key_path, os.geteuid(), private=True)
        key = serialization.load_pem_private_key(self.key_path.read_bytes(), password=None)
        require(isinstance(key, ec.EllipticCurvePrivateKey) and isinstance(key.curve, ec.SECP256R1),
                'An ES256 App Store Connect key is required.')
        now = int(time.time())
        header = {'alg': 'ES256', 'kid': self.config['key_id'], 'typ': 'JWT'}
        payload = {'iss': self.config['issuer_id'], 'iat': now, 'exp': now + 120,
                   'aud': 'appstoreconnect-v1', 'scope': ['GET ' + path]}
        message = b'.'.join(b64(json.dumps(v, separators=(',', ':')).encode()) for v in [header, payload])
        r, s = utils.decode_dss_signature(key.sign(message, ec.ECDSA(hashes.SHA256())))
        return (message + b'.' + b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))).decode()

    def apple_get(self, path):
        # Fixed host, no proxy/environment credentials, no redirects or response-body errors.
        connection = http.client.HTTPSConnection('api.appstoreconnect.apple.com', timeout=20,
                                                  context=ssl.create_default_context())
        try:
            connection.request('GET', path, headers={'Authorization': 'Bearer ' + self.token(path)})
            response = connection.getresponse()
            require(response.status == 200, f'Apple API returned HTTP {response.status}.')
            data = response.read(1024 * 1024 + 1)
            require(len(data) <= 1024 * 1024, 'Apple response is too large.')
            return json.loads(data)
        finally:
            connection.close()

    def verify_app(self):
        app = self.apple_get('/v1/apps/' + self.config['app_id'] + '?fields[apps]=bundleId')['data']
        require(app['attributes']['bundleId'] == self.config['bundle_id'], 'Apple app and bundle ID differ.')

    def local_release(self):
        digest = archive_digest(self.archive, os.geteuid())
        return {**archive_info(self.archive, self.config['bundle_id'], self.config['extension_bundle_id']),
                'release': digest}

    def status(self):
        self.verify_app()
        query = urlencode({'filter[app]': self.config['app_id'], 'sort': '-uploadedDate', 'limit': '10',
                           'fields[builds]': 'version,processingState,expired'})
        response = self.apple_get('/v1/builds?' + query)
        builds = []
        for build in response['data']:
            attributes = build['attributes']
            state = attributes.get('processingState')
            version = attributes.get('version')
            require(state in {'PROCESSING', 'FAILED', 'INVALID', 'VALID'}
                    and isinstance(version, str) and re.fullmatch('[0-9.]+', version),
                    'Unexpected Apple build response.')
            builds.append({'build': version, 'processing': state, 'expired': attributes.get('expired') is True})
        return {'builds': builds, 'staged_release': self.local_release() if self.archive.exists() else None}

    def upload(self, expected):
        release = self.local_release()
        require(release['release'] == expected, 'Staged archive differs from the approved release.')
        journal_path = self.directory / 'uploads.json'
        if journal_path.exists():
            owned_path(journal_path, os.geteuid(), private=True)
        journal = json.loads(journal_path.read_text()) if journal_path.exists() else {}
        require(expected not in journal, 'This release already has an upload attempt; check App Store Connect.')
        self.verify_app()
        owned_path(self.key_path, os.geteuid(), private=True)
        export = self.directory / 'exports' / expected
        export.mkdir(parents=True, mode=0o700)
        snapshot = export / 'Nibble.xcarchive'
        shutil.copytree(self.archive, snapshot, symlinks=True)
        require(archive_digest(snapshot, os.geteuid()) == expected, 'Archive changed while staging the upload.')
        options = export / 'ExportOptions.plist'
        options.write_bytes(plistlib.dumps({'method': 'app-store-connect', 'destination': 'upload',
            'signingStyle': 'automatic', 'teamID': self.config['team_id'],
            'manageAppVersionAndBuildNumber': False, 'testFlightInternalTestingOnly': True,
            'uploadSymbols': True}))
        journal[expected] = 'started'
        save_journal(journal_path, journal)
        command = ['/usr/bin/xcodebuild', '-exportArchive', '-archivePath', str(snapshot),
                   '-exportPath', str(export), '-exportOptionsPlist', str(options),
                   '-allowProvisioningUpdates', '-authenticationKeyPath', str(self.key_path),
                   '-authenticationKeyID', self.config['key_id'],
                   '-authenticationKeyIssuerID', self.config['issuer_id']]
        environment = {'HOME': pwd.getpwuid(os.geteuid()).pw_dir,
                       'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'en_US.UTF-8'}
        result = subprocess.run(command, env=environment, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=1800)
        journal[expected] = 'uploaded' if result.returncode == 0 else 'check_required'
        save_journal(journal_path, journal)
        require(result.returncode == 0, 'Upload was not confirmed; inspect it in the distribution account.')
        return {'upload': 'accepted', 'build': release['build'], 'version': release['version'],
                'processing': 'Check status before adding the build to your internal group.'}

    def handle(self, request):
        validate_request(request)
        return self.status() if request['action'] == 'status' else self.upload(request['release'])


def handle_connection(connection, service, client_uid):
    connection.settimeout(5)
    try:
        require(peer_uid(connection) == client_uid, 'Client user is not authorized.')
        request = read_message(connection, MAX_MESSAGE)
        result = {'ok': True, 'result': service.handle(request)}
    except DistributionError as error:
        result = {'ok': False, 'error': str(error)}
    except Exception:
        # Exception text, Apple bodies and native tool output may contain credentials.
        result = {'ok': False, 'error': 'Operation failed; inspect the distribution account.'}
    try:
        connection.sendall(json.dumps(result).encode() + b'\n')
    except OSError:
        pass


def serve(config_path):
    require(sys.platform == 'darwin', 'The distribution service requires macOS.')
    os.umask(0o077)
    config = load_config(config_path)
    # Install this reviewed file in the dedicated private home, never run a shared checkout.
    source = Path(__file__).absolute()
    require(source.is_relative_to(Path(pwd.getpwuid(os.geteuid()).pw_dir)),
            'Install the reviewed service in the dedicated home.')
    current = source
    while current != Path(pwd.getpwuid(os.geteuid()).pw_dir):
        owned_path(current, os.geteuid())
        current = current.parent
    owned_path(SOCKET.parent, os.geteuid())
    require(not SOCKET.exists(), 'Socket already exists; stop the old service before removing it.')
    service = Service(config, config_path.parent)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
        listener.bind(str(SOCKET))
        os.chmod(SOCKET, 0o666)  # Authorization uses the kernel peer UID, never a client-supplied UID.
        listener.listen(4)
        try:
            while True:
                connection, _ = listener.accept()
                with connection:
                    handle_connection(connection, service, config['client_uid'])
        finally:
            SOCKET.unlink(missing_ok=True)


def request_service(request, user):
    validate_request(request)
    uid = pwd.getpwnam(user).pw_uid
    require(uid not in {0, os.geteuid()}, 'Use a separate standard distribution user.')
    owned_path(SOCKET.parent, uid)
    require(SOCKET.lstat().st_uid == uid and stat.S_ISSOCK(SOCKET.lstat().st_mode),
            'Unexpected service socket.')
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(1850)
        connection.connect(str(SOCKET))
        require(peer_uid(connection) == uid, 'Unexpected service user.')
        connection.sendall(json.dumps(request).encode() + b'\n')
        return read_message(connection, 65536)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    check = sub.add_parser('archive-check', help='Inspect a local archive without credentials')
    check.add_argument('archive', type=Path)
    service = sub.add_parser('serve', help='Run only in the dedicated distribution account')
    service.add_argument('--config', required=True, type=Path)
    for name in ['status', 'upload']:
        client = sub.add_parser(name)
        client.add_argument('--service-user', default='nibble-release')
        if name == 'upload':
            client.add_argument('--release', required=True, help='Approved staged archive SHA-256 from status')
    args = parser.parse_args()
    try:
        if args.action == 'serve':
            serve(args.config)
            return 0
        if args.action == 'archive-check':
            result = {'ok': True, 'result': archive_info(args.archive),
                      'scope': 'Bundle metadata only; signing, Apple validation and installation are unverified.'}
        else:
            request = {'action': args.action}
            if args.action == 'upload':
                request['release'] = args.release
            result = request_service(request, args.service_user)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result['ok'] else 1
    except DistributionError as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
    except Exception:
        print(json.dumps({'ok': False, 'error': 'Check the service setup or archive; no sensitive details returned.'}))
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
