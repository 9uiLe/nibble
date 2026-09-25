#!/usr/bin/env python3
"""Check PR structure and reuse verified CI work for metadata-only edits."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

from check_evidence import remote_url
from script_ui import ui

SECTIONS = ['目的・背景', 'アウトカム', '変更内容', 'スクリーンショット・画面録画', '検証結果', 'レビュー前の確認']
SHA = r'[a-f0-9]{40}'
LINK = re.compile(r'(!?)\[[^\]\n]*\]\((https?://[^\s)]+)\)')
CHECK_STEP = 'Check repository with locked tools'
JOB_NAME = 'workflow-policy'
WORKFLOW = '.github/workflows/workflow-policy.yml'


def sections(body):
    # Comments, including the blank template's guidance, are not evidence.
    text = re.sub(r'<!--.*?-->', '', body, flags=re.S)
    # Examples cannot satisfy required fields or conceal duplicate headings.
    text = re.sub(r'(?ms)^(`{3,}|~{3,})[^\n]*\n.*?^\1\s*$', '', text)
    result = {}
    parts = re.split(r'^##\s+(.+?)\s*$', text, flags=re.M)
    for index in range(1, len(parts), 2):
        title = parts[index]
        if title in result:
            raise ValueError(f'Duplicate PR section: {title}')
        result[title] = parts[index + 1].strip()
    return result


def changes_ui(files):
    for name in files:
        path = Path(name)
        if path.suffix == '.md' or any(part.endswith('Tests') or part == 'TestSupport' for part in path.parts):
            continue
        if name.startswith(('app/', 'validation/VerificationApp/')):
            return True
        if name.startswith(('validation/VerificationApp.xcodeproj/')):
            return True
    return False


def check(snapshot, complete=False, expected_head=None, check_ci=False):
    errors = []
    if snapshot.get('draft') is not False:
        errors.append('PR must be ready for review, not a draft')
    body = snapshot['body'] or ''
    content = sections(body)
    if expected_head and snapshot['head'] != expected_head:
        errors.append('PR head changed; collect a new snapshot and rerun checks')
    if not re.fullmatch(SHA, snapshot['head']):
        errors.append('Missing full PR head SHA')
    for heading in SECTIONS:
        if not content.get(heading):
            errors.append(f'Fill required section: {heading}')
    if errors:
        return errors
    # Every table row must contain exactly one full commit ID and an explanation.
    recorded = []
    for line in content['変更内容'].splitlines():
        if not line.startswith('|'):
            continue
        cells = [cell.strip() for cell in line.strip('|').split('|')]
        if len(cells) != 2:
            errors.append('Commit table needs two columns')
            continue
        if cells[0] == 'コミットハッシュ' or re.fullmatch(r'[-: ]+', cells[0]):
            continue
        ids = set(re.findall(SHA, cells[0]))
        if len(ids) != 1 or not cells[1]:
            errors.append('Commit row needs a full SHA and description')
        else:
            recorded.append(ids.pop())
    actual = snapshot['commits']
    if not actual or len(recorded) != len(set(recorded)) or set(recorded) != set(actual):
        errors.append('Commit table differs from all actual PR commits (missing/extra/duplicate SHA)')
    evidence = content['スクリーンショット・画面録画']
    links = LINK.findall(evidence)
    if any(not remote_url(url) for _, url in links):
        errors.append('Evidence links need stable HTTPS URLs')
    if re.search(r'\]\((?:artifacts/|/Users/|file:|localhost)', evidence):
        errors.append('Local paths cannot be PR attachments')
    needs_ui = changes_ui(snapshot['files']) or '対象外' not in evidence
    if needs_ui:
        images = {url for image, url in links if image == '!' and remote_url(url)}
        if len(images) < 2 and not (len(images) == 1 and re.search(r'変更前[：:]\s*対象外[^\n]*新規画面', evidence)):
            errors.append('UI change needs before/after screenshots (new screen: explain why no before image)')
        video_section = re.split(r'画面録画[：:]', evidence, maxsplit=1)
        if len(video_section) != 2 or not any(not kind and remote_url(url) and url not in images for kind, url in LINK.findall(video_section[1])):
            errors.append('UI change needs a recording link after 画面録画：')
        for label in ['対象コミット', '端末', '操作']:
            if not re.search(label + r'[^\n：:]*[：:]\s*\S', evidence):
                errors.append('Fill evidence field: ' + label)
        if not re.search(r'iOS\s*26\.5(?![\d.])', evidence):
            errors.append('Identify iOS 26.5 in evidence')
        if not re.search(r'\b[a-f0-9]{7,40}\b', evidence):
            errors.append('Identify evidence source commit')
    elif not re.search(r'対象外[^\n]*[：:（(]\s*[^\s）)]', evidence):
        errors.append('Explain UI evidence being out of scope: 対象外：理由')
    validation = content['検証結果']
    for label in ['性能', '未実施項目・残る制約']:
        if not re.search(label + r'[：:]\s*\S', validation):
            errors.append('Fill validation field: ' + label)
    if complete and re.search(r'^\s*- \[ \]', content['レビュー前の確認'], re.M):
        errors.append('Review checklist has unfinished items; keep the PR unmerged')
    if not re.search(r'^\s*- \[[ xX]\]', content['レビュー前の確認'], re.M):
        errors.append('Review checklist is missing')
    if check_ci:
        checks = snapshot.get('checks', [])
        latest = {}
        for row in checks:
            key = ((row.get('app') or {}).get('slug'), row.get('name'))
            if not isinstance(row.get('id'), int) or not all(key):
                errors.append('Current-head check run is missing its identity')
                break
            if key not in latest or row['id'] > latest[key]['id']:
                latest[key] = row
        if not latest or any(row.get('status') != 'completed' or row.get('conclusion') != 'success'
                             for row in latest.values()):
            errors.append('All checks on the current PR head must succeed')
    return errors


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()


def local_snapshot(root, base, body):
    base_sha = git(root, 'rev-parse', '--verify', base + '^{commit}')
    return {'head': git(root, 'rev-parse', 'HEAD'), 'body': body, 'draft': False,
            'commits': git(root, 'rev-list', '--reverse', base_sha + '..HEAD').splitlines(),
            'files': git(root, 'diff', '--no-renames', '--name-only', base_sha + '...HEAD').splitlines()}


def api(endpoint, paged=False):
    args = ['gh', 'api', endpoint]
    if paged:
        args += ['--paginate', '--slurp']
    value = json.loads(subprocess.check_output(args, text=True))
    return [row for page in value for row in page] if paged else value


def reusable(runs, jobs_for_run, head, base, number, current_run):
    """Trust only the latest completed, actually executed locked-tools step."""
    for run in sorted(runs, key=lambda row: row['id'], reverse=True):
        if (run.get('id') == current_run or run.get('head_sha') != head
                or run.get('path') != WORKFLOW or run.get('event') != 'pull_request'
                or not any(pr.get('number') == number and pr.get('base', {}).get('sha') == base
                           for pr in run.get('pull_requests', []))):
            continue
        if run.get('status') != 'completed':
            return False
        jobs = [job for job in jobs_for_run(run['id']) if job.get('name') == JOB_NAME]
        if len(jobs) != 1:
            return False
        steps = [step for step in jobs[0].get('steps', []) if step.get('name') == CHECK_STEP]
        if len(steps) != 1:
            return False
        if steps[0].get('conclusion') != 'skipped':
            return steps[0].get('conclusion') == 'success'
    return False


def can_reuse(event, current_run, get=api):
    if event.get('action') != 'edited':
        return False
    repository = event['repository']['full_name']
    head = event['pull_request']['head']['sha']
    base = event['pull_request']['base']['sha']
    number = event['number']
    if (not re.fullmatch(r'[\w.-]+/[\w.-]+', repository)
            or not re.fullmatch(r'[a-f0-9]{40}', head)
            or not re.fullmatch(r'[a-f0-9]{40}', base)
            or not isinstance(number, int) or number < 1 or current_run < 1):
        return False
    prefix = 'repos/' + repository + '/actions'
    data = get(prefix + '/workflows/workflow-policy.yml/runs?head_sha=' + head
               + '&event=pull_request&per_page=100')
    if not isinstance(data.get('total_count'), int) or data['total_count'] != len(data.get('workflow_runs', [])):
        return False

    def jobs(run_id):
        result = get(prefix + '/runs/' + str(run_id) + '/jobs?per_page=100')
        if not isinstance(result.get('total_count'), int) or result['total_count'] != len(result.get('jobs', [])):
            raise ValueError('Incomplete job history')
        return result['jobs']

    return reusable(data['workflow_runs'], jobs, head, base, number, current_run)


def remote_snapshot(repo, number, ci=False):
    if not re.fullmatch(r'[\w.-]+/[\w.-]+', repo) or number < 1:
        raise ValueError('Specify owner/repo and a positive PR number')
    endpoint = f'repos/{repo}/pulls/{number}'
    pr = api(endpoint)
    if not isinstance(pr.get('draft'), bool):
        raise ValueError('GitHub did not report the PR draft state')
    commits = api(endpoint + '/commits?per_page=100', paged=True)
    files = api(endpoint + '/files?per_page=100', paged=True)
    # GitHub limits these REST endpoints; fail rather than certify a partial list.
    if len(commits) != pr['commits'] or len(files) != pr['changed_files']:
        raise ValueError('Incomplete GitHub commit/file listing; split the PR or inspect API limits')
    snapshot = {'head': pr['head']['sha'], 'body': pr['body'], 'draft': pr['draft'],
                'commits': [c['sha'] for c in commits],
                'files': [name for row in files for name in [row['filename'], row.get('previous_filename')] if name]}
    if ci:
        pages = json.loads(subprocess.check_output(['gh', 'api', f'repos/{repo}/commits/{snapshot["head"]}/check-runs?per_page=100', '--paginate', '--slurp'], text=True))
        snapshot['checks'] = [row for page in pages for row in page['check_runs']]
    # Detect edits or pushes while assembling the read-only snapshot.
    current = api(endpoint)
    if (current['head']['sha'] != pr['head']['sha'] or current['body'] != pr['body']
            or current.get('draft') != pr['draft']):
        raise ValueError('PR changed during collection; rerun')
    return snapshot


def main(argv=None):
    cli = argparse.ArgumentParser(description=__doc__)
    sub = cli.add_subparsers(dest='command', required=True)
    for command in ['commits', 'local']:
        parser = sub.add_parser(command)
        parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
        parser.add_argument('--base', required=True, help='Fetched base ref, e.g. origin/main')
        if command == 'local':
            parser.add_argument('--body-file', type=Path, required=True)
            parser.add_argument('--complete', action='store_true')
    remote = sub.add_parser('remote')
    remote.add_argument('--repo')
    remote.add_argument('--number', type=int)
    remote.add_argument('--event', type=Path, help='GitHub pull_request event; repo/number/head are read as data')
    remote.add_argument('--expected-head')
    remote.add_argument('--complete', action='store_true')
    remote.add_argument('--check-ci', action='store_true', help='Final read-only check; do not use inside the running CI job')
    remote.add_argument('--snapshot-out', type=Path)
    reuse = sub.add_parser('reuse-locked-checks', help='Return true only after a prior full check on the same PR/head/base')
    reuse.add_argument('--event', type=Path, required=True)
    reuse.add_argument('--run-id', type=int, required=True)
    args = cli.parse_args(argv)
    if args.command == 'reuse-locked-checks':
        try:
            result = can_reuse(json.loads(args.event.read_text()), args.run_id)
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
            result = False
        print('true' if result else 'false')
        return 0
    try:
        if args.command in {'commits', 'local'}:
            if args.command == 'local' and git(args.root, 'status', '--porcelain'):
                raise ValueError('Commit the working changes before validating the PR body')
            snapshot = local_snapshot(args.root, args.base, args.body_file.read_text() if args.command == 'local' else '')
            if args.command == 'commits':
                print('| コミットハッシュ | 変更の説明 |\n| --- | --- |')
                for sha in snapshot['commits']:
                    subject = git(args.root, 'show', '-s', '--format=%s', sha).replace('|', '&#124;')
                    print(f'| `{sha}` | {subject} |')
                return 0
        else:
            if args.event:
                event = json.loads(args.event.read_text())
                args.repo, args.number = event['repository']['full_name'], event['number']
                args.expected_head = event['pull_request']['head']['sha']
            if not args.repo or not args.number:
                raise ValueError('Specify --repo and --number, or --event')
            snapshot = remote_snapshot(args.repo, args.number, args.check_ci)
            if args.snapshot_out:
                args.snapshot_out.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + '\n')
        errors = check(snapshot, args.complete, getattr(args, 'expected_head', None), getattr(args, 'check_ci', False))
        ui.check('PR policy', errors, f'{len(snapshot["commits"])} commits; body and evidence structure checked')
        return int(bool(errors))
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        ui.result(False, f'PR policy failed: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
