#!/usr/bin/env python3
"""Local TestFlight deployment; credentials and native logs never reach stdout."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
from enum import Enum
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import stat
import subprocess
import sys
import uuid


# -I excludes cwd/PYTHONPATH. Load only the reviewed sibling, without widening sys.path.
_ui_spec = importlib.util.spec_from_file_location('nibble_script_ui', Path(__file__).resolve().with_name('script_ui.py'))
_ui_module = importlib.util.module_from_spec(_ui_spec)
_ui_spec.loader.exec_module(_ui_module)
ui = _ui_module.ui


class DistributionError(Exception):
    """Only fixed, non-secret errors are presented to the caller."""


def require(condition, message):
    if not condition:
        raise DistributionError(message)


def archive_info(archive, bundle_id='nibble.9uiLe.com', extension_id='nibble.9uiLe.com.share',
                 keyboard_id='nibble.9uiLe.com.keyboard'):
    app = archive / 'Products/Applications/Nibble.app'
    extension = app / 'PlugIns/NibbleShare.appex'
    keyboard = app / 'PlugIns/NibbleKeyboard.appex'
    require(sorted(p.name for p in (archive / 'Products/Applications').iterdir()) == ['Nibble.app'],
            'Archive must contain only Nibble.app.')
    require(sorted(p.name for p in (app / 'PlugIns').iterdir()) == ['NibbleKeyboard.appex', 'NibbleShare.appex'],
            'Archive must contain exactly the share and keyboard extensions.')
    values = []
    for path, identifier, kind in [(app, bundle_id, 'APPL'), (extension, extension_id, 'XPC!'),
                                   (keyboard, keyboard_id, 'XPC!')]:
        with (path / 'Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        require(info.get('CFBundleIdentifier') == identifier, 'Unexpected bundle identifier.')
        require(info.get('CFBundlePackageType') == kind, 'Unexpected bundle type.')
        require(info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], 'Device archive required.')
        require(info.get('MinimumOSVersion') == '26.0', 'Minimum iOS must remain 26.0.')
        require(info.get('DTPlatformName') == 'iphoneos', 'Device SDK required.')
        require(info.get('DTPlatformVersion') == '26.5', 'Use the verified iOS 26.5 SDK.')
        require(info.get('ITSAppUsesNonExemptEncryption') is False,
                'App and extension must declare no non-exempt encryption with a Boolean false.')
        executable = info.get('CFBundleExecutable', '')
        require(bool(executable) and Path(executable).name == executable and (path / executable).is_file(),
                'Missing bundle executable.')
        with (path / 'PrivacyInfo.xcprivacy').open('rb') as stream:
            require(isinstance(plistlib.load(stream), dict), 'Missing privacy manifest.')
        values.append(info)
    app_info, share_info, keyboard_info = values
    for key in ['CFBundleShortVersionString', 'CFBundleVersion']:
        require(bool(app_info.get(key)) and all(app_info[key] == info.get(key) for info in values[1:]),
                'App and extension versions must match.')
        require(isinstance(app_info[key], str) and re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', app_info[key]),
                'Use numeric release and build versions.')
    require(share_info.get('NSExtension', {}).get('NSExtensionPointIdentifier') == 'com.apple.share-services',
            'Share extension configuration is missing.')
    keyboard_config = keyboard_info.get('NSExtension', {})
    require(keyboard_config.get('NSExtensionPointIdentifier') == 'com.apple.keyboard-service'
            and keyboard_config.get('NSExtensionAttributes', {}).get('RequestsOpenAccess') is True,
            'Keyboard extension configuration is missing.')
    require(bool(app_info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconName')),
            'App icon configuration is missing.')
    return {'bundle_id': bundle_id, 'extension_bundle_id': extension_id, 'keyboard_bundle_id': keyboard_id,
            'version': app_info['CFBundleShortVersionString'], 'build': app_info['CFBundleVersion'],
            'minimum_ios': '26.0', 'sdk': '26.5', 'uses_non_exempt_encryption': False}


def private_path(path, directory=False):
    info = path.lstat()
    require(info.st_uid == os.geteuid() and not info.st_mode & 0o077
            and not stat.S_ISLNK(info.st_mode), '認証設定の所有者・権限を本人が確認してください。')
    require(stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
            '認証設定のファイル形式を本人が確認してください。')


class CredentialStep(Enum):
    DIRECTORY = '認証ディレクトリの存在・所有者・権限'
    CONFIG_FILE = 'nibble.envの存在・所有者・権限・読み取り'
    CONFIG_FORMAT = 'nibble.envの代入書式・必須項目'
    KEY_ID = 'ASC_KEY_IDの書式'
    TEAM_ID = 'ASC_TEAM_IDの書式'
    ISSUER_ID = 'ASC_ISSUER_IDの書式'
    KEY_PATH = 'ASC_KEY_PATHの配置規則'
    KEY_FILE = 'API鍵ファイルの存在・所有者・権限'


class CredentialError(DistributionError):
    def __init__(self, step):
        # Only predefined check names reach the caller, never values or exception text.
        if not isinstance(step, CredentialStep):
            raise ValueError('Unknown credential check')
        super().__init__('認証設定（' + step.value + '）: 失敗。本人がdocs/testflight.mdの初回設定を確認してください。')


@contextmanager
def credential_step(step):
    try:
        yield
    except (OSError, ValueError, DistributionError):
        raise CredentialError(step) from None


def load_credentials(home):
    directory = home / '.appstoreconnect'
    with credential_step(CredentialStep.DIRECTORY):
        private_path(directory, directory=True)
    path = directory / 'nibble.env'
    with credential_step(CredentialStep.CONFIG_FILE):
        private_path(path)
        contents = path.read_text()
    values = {}
    required = {'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY_PATH', 'ASC_TEAM_ID'}
    names = set()
    with credential_step(CredentialStep.CONFIG_FORMAT):
        for line in contents.splitlines():
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            assignment = re.sub(r'^export[ \t]+', '', line.strip())
            name, separator, value = assignment.partition('=')
            name = name.strip()
            require(separator and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name)
                    and name not in names, 'Invalid assignment.')
            names.add(name)
            require('$(' not in value and '`' not in value, 'Shell evaluation is not supported.')
            words = shlex.split(value, comments=True)
            require(len(words) <= 1, 'Invalid value format.')
            if name in required:
                require(len(words) == 1, 'Missing required value.')
                values[name] = words[0]
        require(set(values) == required, 'Missing fields.')
    for name, step in [('ASC_KEY_ID', CredentialStep.KEY_ID), ('ASC_TEAM_ID', CredentialStep.TEAM_ID)]:
        with credential_step(step):
            require(re.fullmatch('[A-Z0-9]{10}', values[name]), 'Invalid identifier format.')
    with credential_step(CredentialStep.ISSUER_ID):
        require(re.fullmatch('[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', values['ASC_ISSUER_ID']),
                'Invalid issuer format.')
    with credential_step(CredentialStep.KEY_PATH):
        raw = values['ASC_KEY_PATH']
        for prefix in ('$HOME/', '${HOME}/', '~/'):
            if raw.startswith(prefix):
                raw = str(home / raw[len(prefix):])
                break
        key = directory / ('AuthKey_' + values['ASC_KEY_ID'] + '.p8')
        require(raw == str(key), 'Unexpected key path.')
    with credential_step(CredentialStep.KEY_FILE):
        private_path(key)
    values['ASC_KEY_PATH'] = str(key)
    # The private key bytes are read by Xcode only; this parser never executes shell expressions.
    return values


def authentication_arguments(values):
    return ['-allowProvisioningUpdates', '-authenticationKeyPath', values['ASC_KEY_PATH'],
            '-authenticationKeyID', values['ASC_KEY_ID'], '-authenticationKeyIssuerID', values['ASC_ISSUER_ID']]


def apple_environment():
    values = {'HOME': str(Path.home()), 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'en_US.UTF-8'}
    if 'DEVELOPER_DIR' in os.environ:
        values['DEVELOPER_DIR'] = os.environ['DEVELOPER_DIR']
    return values


def source_commit(root):
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, stderr=subprocess.DEVNULL, text=True).strip()
    changed = subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, stderr=subprocess.DEVNULL)
    require(not changed, '変更をcommitしてから配布してください。')
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root, stderr=subprocess.DEVNULL).decode().split('\0')
    forbidden = {'.p8', '.p12', '.pfx', '.mobileprovision', '.provisionprofile'}
    require(not any(Path(name).suffix.lower() in forbidden
                    or Path(name).name in {'.env', 'nibble.env'}
                    or Path(name).name.startswith(('AuthKey_', '.env.')) for name in names),
            '認証・署名ファイルがGit管理されています。配布を停止しました。')
    return commit


def build_number(value=None):
    value = value or datetime.now(timezone.utc).strftime('%Y%m%d%H%M')
    require(len(value) <= 18 and re.fullmatch(r'[1-9][0-9]*(?:\.(?:0|[1-9][0-9]*)){0,2}', value),
            'build番号には18文字以内の正の整数、またはピリオドで区切った整数を指定してください。')
    return value


def export_options(team, dry_run):
    return {'method': 'app-store-connect', 'destination': 'export' if dry_run else 'upload',
            'signingStyle': 'automatic', 'teamID': team, 'manageAppVersionAndBuildNumber': False,
            'testFlightInternalTestingOnly': True, 'uploadSymbols': True}


class Deployment:
    def __init__(self, root, home, values, build, dry_run):
        self.root, self.values, self.build, self.dry_run = root, values, build, dry_run
        self.commit = source_commit(root)
        self.path = root / 'artifacts/testflight' / build
        try:
            self.path.mkdir(parents=True, mode=0o700)
        except FileExistsError:
            raise DistributionError('このbuild番号の実行記録があります。送信状況を確認し、未使用の番号を指定してください。') from None
        self.archive = self.path / 'Nibble.xcarchive'
        self.logs = home / '.appstoreconnect/logs'
        self.logs.mkdir(mode=0o700, exist_ok=True)
        private_path(self.logs, directory=True)
        self.logs = self.logs / ('nibble-' + build + '-' + uuid.uuid4().hex[:8])
        self.logs.mkdir(mode=0o700)
        self.manifest = {'commit': self.commit, 'build': build, 'configuration': 'Release',
                         'destination': 'export' if dry_run else 'upload', 'stage': 'prepared', 'completed': False}
        self.save()

    def save(self):
        (self.path / 'manifest.json').write_text(json.dumps(self.manifest, ensure_ascii=False, indent=2) + '\n')

    def native(self, stage, command, timeout):
        self.manifest['stage'] = stage
        self.save()
        with ui.step(stage), (self.logs / (stage + '.log')).open('xb') as log:
            os.chmod(log.name, 0o600)
            try:
                result = subprocess.run(command, cwd=self.root, env=apple_environment(),
                                        stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
            except (OSError, subprocess.TimeoutExpired):
                raise DistributionError(stage + 'を完了できませんでした。本人が保護されたログと送信状況を確認してください。') from None
            require(result.returncode == 0, stage + 'に失敗しました。本人が保護されたログを確認してください。')

    def unchanged(self):
        require(source_commit(self.root) == self.commit, '実行中にソースが変わりました。配布を停止しました。')

    def execute(self):
        nix = shutil.which('nix')
        require(nix is not None, 'Nix環境で実行してください。')
        self.native('checks', [nix, 'flake', 'check', '--no-update-lock-file', '--print-build-logs'], 1800)
        self.unchanged()
        sdk = subprocess.check_output(['/usr/bin/xcrun', '--sdk', 'iphoneos', '--show-sdk-version'],
                                      env=apple_environment(), stderr=subprocess.DEVNULL, text=True).strip()
        require(sdk == '26.5', 'iPhoneOS 26.5 SDKを選択してください。')
        self.native('prepare-rive-runtime', [nix, 'develop', '--command',
                    'python3', 'scripts/rive_runtime.py', 'prepare'], 3600)
        self.unchanged()
        cache = self.root / 'artifacts/SourcePackages'
        self.native('resolve', ['/usr/bin/xcodebuild', '-resolvePackageDependencies',
                    '-project', 'app/Nibble.xcodeproj', '-scheme', 'Nibble',
                    '-clonedSourcePackagesDirPath', str(cache), '-onlyUsePackageVersionsFromResolvedFile'], 900)
        self.unchanged()
        self.native('archive', ['/usr/bin/xcodebuild', 'archive', '-project', 'app/Nibble.xcodeproj',
                    '-scheme', 'Nibble', '-configuration', 'Release', '-destination', 'generic/platform=iOS',
                    '-archivePath', str(self.archive), '-derivedDataPath', str(self.path / 'DerivedData'),
                    '-clonedSourcePackagesDirPath', str(cache), '-disableAutomaticPackageResolution',
                    '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates',
                    'DEVELOPMENT_TEAM=' + self.values['ASC_TEAM_ID'], 'CURRENT_PROJECT_VERSION=' + self.build,
                    'ENABLE_TESTABILITY=NO', *authentication_arguments(self.values)], 3600)
        self.unchanged()
        info = archive_info(self.archive)
        require(info['build'] == self.build, 'archiveのbuild番号が指定と一致しません。')
        self.manifest['archive'] = info
        # Export options contain the team ID; retain them with the protected native logs.
        options = self.logs / 'ExportOptions.plist'
        options.write_bytes(plistlib.dumps(export_options(self.values['ASC_TEAM_ID'], self.dry_run)))
        exported = self.path / 'export'
        self.native('export' if self.dry_run else 'upload', ['/usr/bin/xcodebuild', '-exportArchive',
                    '-archivePath', str(self.archive), '-exportPath', str(exported),
                    '-exportOptionsPlist', str(options), *authentication_arguments(self.values)], 1800)
        if self.dry_run:
            require(any(exported.glob('*.ipa')), 'export成功後のIPAがありません。本人がログを確認してください。')
        self.manifest['completed'] = True
        self.save()
        ui.result(True, '完了: version=' + info['version'] + ' build=' + self.build)
        ui.message('IPA書き出しのみ。Appleへは送信していません。' if self.dry_run else
              'アップロード成功。App Store Connectで処理完了と「本人用」への自動配信を確認してください。')


@contextmanager
def deployment_lock(root):
    directory = root / 'artifacts/testflight'
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise DistributionError('別の配布処理が実行中です。完了を待ってください。') from None
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    check = commands.add_parser('archive-check', help='Inspect an archive without credentials')
    check.add_argument('archive', type=Path)
    deploy = commands.add_parser('deploy', help='Archive and export/upload using local Apple credentials')
    modes = deploy.add_mutually_exclusive_group()
    modes.add_argument('--dry-run', action='store_true', help='Sign and export an IPA without uploading')
    modes.add_argument('--check-config', action='store_true', help='Report configuration readiness without values or network')
    deploy.add_argument('--build-number', help='Unused CFBundleVersion; default UTC YYYYMMDDHHmm')
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.command == 'archive-check':
            print(json.dumps({'metadata': archive_info(args.archive),
                              'scope': 'Metadata only; signing and Apple validation are unverified.'}, indent=2))
            return 0
        require(sys.platform == 'darwin', '配布にはローカルMacが必要です。')
        try:
            values = load_credentials(Path.home())
        except CredentialError:
            raise
        except (OSError, ValueError, DistributionError):
            raise DistributionError('認証設定は利用できません。本人がdocs/testflight.mdの初回設定を確認してください。') from None
        if args.check_config:
            ui.result(True, '認証設定: 利用可能（値・鍵の内容は非表示。Appleへの接続は未確認）')
            return 0
        root = Path(__file__).resolve().parents[1]
        with deployment_lock(root):
            Deployment(root, Path.home(), values, build_number(args.build_number), args.dry_run).execute()
        return 0
    except DistributionError as error:
        ui.result(False, str(error))
    except (Exception, KeyboardInterrupt):
        ui.result(False, '配布を完了できませんでした。本人が設定・保護されたログ・送信状況を確認してください。')
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
