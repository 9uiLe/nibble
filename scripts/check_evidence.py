#!/usr/bin/env python3
"""Validate local run identity, recorded results, media and review declarations."""

import argparse
from datetime import datetime
import ipaddress
import json
import math
from pathlib import Path
import re
import sys
import subprocess
from urllib.parse import urlsplit

from script_ui import ui
from verification_evidence import differences, digest, inputs, media_hashes, revision_hashes


def remote_url(value):
    if not isinstance(value, str):
        return False
    url = urlsplit(value)
    if url.scheme != 'https' or not url.hostname or url.username or url.password:
        return False
    host = url.hostname.lower()
    if '.' not in host or host.endswith(('.local', '.localhost')) or host == 'localhost':
        return False
    try:
        ipaddress.ip_address(host)
        return False
    except ValueError:
        return not any(key in url.query.lower() for key in ['jwt=', 'x-amz-', 'token='])


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_run(directory, reference_hashes):
    manifest = json.loads((directory / 'manifest.json').read_text())
    require(manifest.get('evidence_version') == 1, 'Run requires evidence_version 1 with start/end source and media hashes')
    require(manifest.get('status') == 'passed', 'Run did not pass')
    project = manifest['project']
    start = inputs(manifest['files_sha256'], project)
    end = inputs(manifest['files_sha256_end'], project)
    expected = inputs(reference_hashes, project)
    require(start and any(name.startswith(str(Path(project['project']).parent) + '/') for name in start), 'Missing target source hashes')
    require(not differences(start, end), 'Sources changed during the run: ' + ', '.join(differences(start, end)))
    require(not differences(start, expected), 'Run does not match reference inputs: ' + ', '.join(differences(start, expected)))
    device = manifest['device']
    require(device['runtime']['version'] == '26.5' and device['runtime'].get('buildversion'), 'Expected iOS 26.5 and OS build')
    require(re.fullmatch(r'[\da-fA-F]{8}(?:-[\da-fA-F]{4}){3}-[\da-fA-F]{12}', device['udid']), 'Expected explicit Simulator UDID')
    require(manifest.get('commands'), 'No commands recorded')
    for event in manifest['commands']:
        handled = event.get('handled_error', {})
        assertions = manifest.get('assertions', {})
        recovered = (event.get('exit_code') == 1 and isinstance(handled, dict) and handled.get('reason')
                     and isinstance(assertions, dict) and assertions.get(handled.get('assertion')) is True)
        require(not event.get('error') and (event.get('exit_code') == 0 or recovered),
                'Unresolved command failure: ' + str(event.get('argv')))
        for key in ['stdout', 'stderr']:
            if key in event:
                path = directory / event[key]
                require(path.resolve().is_relative_to(directory.resolve()) and path.is_file(), 'Missing/outside command log')
    # A screenshot command snapshots today's checkout, not the source of an
    # already installed binary. Only a build in this run establishes provenance.
    def is_target_build(event):
        argv = event.get('argv', [])
        return (bool(argv) and Path(argv[0]).name == 'xcodebuild' and argv[-1] in {'build', 'test'}
                and event.get('exit_code') == 0 and '-scheme' in argv
                and argv[argv.index('-scheme') + 1] == project['scheme']
                and f'platform=iOS Simulator,id={device["udid"]}' in argv)
    require(any(is_target_build(event) for event in manifest['commands']),
            'No successful target build in this run; standalone screenshots/recordings cannot certify installed source')
    if manifest['command'] == 'test' or (directory / 'test-summary.json').exists():
        summary = json.loads((directory / 'test-summary.json').read_text())
        require(summary.get('result') == 'Passed' and summary.get('failedTests') == 0
                and summary.get('passedTests', 0) > 0 and summary.get('totalTestCount', 0) > 0,
                'No executed passing tests or failed test summary')
    actual = media_hashes(directory)
    require(manifest.get('media_sha256') == actual, 'Media added, removed or modified after run completion')
    return manifest


def init_review(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    rows = [{'file': name, 'sha256': sha, 'method': 'sampled' if name.endswith('.mp4') else 'image',
             'seconds': [], 'observations': '', 'url': '',
             'access': {'method': 'browser', 'result': '', 'checked_at': '', 'scope': ''}}
            for name, sha in manifest.get('media_sha256', {}).items()
            if '/' not in name and name.endswith(('.png', '.mp4'))]
    return {'reviewer': '', 'scope': '', 'limitations': [], 'media': rows}


def check_review(directory, manifest, review):
    require(review.get('reviewer') and review.get('scope'), 'Record reviewer and review scope')
    require(isinstance(review.get('limitations'), list), 'Record limitations (empty list only if none)')
    require(isinstance(review.get('media'), list) and review['media'], 'Select media actually reviewed and attached')
    seen = set()
    for row in review['media']:
        name = row['file']
        require(name not in seen and name in manifest['media_sha256'] and '/' not in name, 'Unknown/duplicate media')
        seen.add(name)
        require(row['sha256'] == manifest['media_sha256'][name] == digest(directory / name), 'Review refers to different media bytes')
        require(isinstance(row.get('observations'), str) and row['observations'].strip(), 'Record actual observations')
        require(remote_url(row.get('url')), 'Use a stable HTTPS attachment URL, not a local path or expiring signed URL')
        access = row['access']
        require(access.get('method') == 'browser' and access.get('result') == 'loaded' and access.get('scope'), 'Record browser media loading and signed-in/anonymous scope; HEAD alone is insufficient')
        require(datetime.fromisoformat(access['checked_at']).tzinfo is not None, 'Use an access time with timezone')
        if name.endswith('.png'):
            require(row['method'] == 'image', 'PNG review method must be image')
        elif name.endswith('.mp4'):
            require(row['method'] in {'sampled', 'continuous'}, 'Declare sampled or continuous video review')
            video = json.loads((directory / 'video-frames/video.json').read_text())
            duration = video['duration_seconds']
            require(isinstance(duration, (int, float)) and math.isfinite(duration) and duration > 0, 'Invalid video duration')
            if row['method'] == 'sampled':
                require(row.get('seconds') and all(type(t) in (int, float) and math.isfinite(t) and 0 <= t <= duration for t in row['seconds']), 'Record reviewed timestamps within local video duration')
        else:
            raise ValueError('Only PNG/MP4 review media supported')
    require(any(name.endswith('.png') for name in seen), 'Attach a reviewed screenshot')
    if any(name.endswith('.mp4') for name in manifest['media_sha256']):
        require(any(name.endswith('.mp4') for name in seen), 'Attach a reviewed recording')


def render_review(manifest, review, revision):
    device = manifest['device']
    lines = ['# ローカル検証の証跡', '', f'- 照合先コミット: `{revision}`',
             f'- 実行時コミット: `{manifest["commit"]}`（dirty: {manifest["dirty"]}）',
             f'- 端末: {device.get("name", "Simulator")} / `{device["udid"]}` / iOS 26.5 ({device["runtime"]["buildversion"]})',
             '- 実行情報・終了コード: [manifest.json](manifest.json)',
             f'- 確認者: {review["reviewer"]}', f'- 確認範囲: {review["scope"]}', '',
             '| 証跡 | 確認方法 | 観測 | 閲覧確認 |', '| --- | --- | --- | --- |']
    for row in review['media']:
        def cell(value):
            return str(value).replace('|', '&#124;').replace('\n', '<br>')
        method = row['method'] + (' ' + str(row['seconds']) + '秒' if row['method'] == 'sampled' else '')
        access = row['access']
        lines.append(f'| [{row["file"]}]({row["url"]}) | {cell(method)} | {cell(row["observations"])} | {cell(access["checked_at"])} / {cell(access["scope"])} |')
    lines += ['', '未実施項目・限界：' + (' / '.join(review['limitations']) or '記録なし'), '',
              '自動検査はソース・ファイルの整合性と申告の形式を確認する。目視・閲覧の実施そのものを証明しない。', '']
    return '\n'.join(lines)


def main(argv=None):
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    cli.add_argument('--run', required=True, type=Path)
    cli.add_argument('--ref', default='HEAD')
    cli.add_argument('--init-review', action='store_true', help='Create review.json with empty declarations; never marks a review complete')
    cli.add_argument('--integrity-only', action='store_true', help='Check run identity only; does not certify visual review')
    args = cli.parse_args(argv)
    try:
        if args.init_review:
            with (args.run / 'review.json').open('x') as stream:
                json.dump(init_review(args.run), stream, ensure_ascii=False, indent=2)
                stream.write('\n')
            ui.message('Created review.json; fill only actual observations and access checks.')
        else:
            revision, hashes = revision_hashes(args.root, args.ref)
            manifest = check_run(args.run, hashes)
            if not args.integrity_only:
                review = json.loads((args.run / 'review.json').read_text())
                check_review(args.run, manifest, review)
                (args.run / 'REVIEW.md').write_text(render_review(manifest, review, revision))
            print(json.dumps({'revision': revision, 'run': str(args.run), 'integrity': 'passed',
                              'review_declarations': 'not checked' if args.integrity_only else 'valid'}, ensure_ascii=False))
            ui.result(True, 'Evidence integrity passed' if args.integrity_only else 'Evidence integrity and review declarations passed')
        return 0
    except (OSError, ValueError, KeyError, TypeError, IndexError, subprocess.SubprocessError) as error:
        ui.result(False, f'Evidence check failed: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
