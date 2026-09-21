#!/usr/bin/env python3
"""Plan and execute verification for changed files; retain scope, failures and elapsed time."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import uuid

from script_ui import ui
from verification_evidence import differences, working_hashes
from verification_catalog import (STAGES, REGRESSION_STEPS, PERFORMANCE_STEPS,
                                  PRODUCT_STEPS, OFFLINE_STEPS, SCOPES)

ROOT = Path(__file__).resolve().parents[1]
STATIC_SCRIPTS = {
    'scripts/check_docs.py', 'scripts/check_swift_policy.py', 'scripts/check_ui_design.py',
    'scripts/check_workflows.py', 'scripts/check_pr.py', 'scripts/swift_equatable_policy.py',
    'scripts/swift_task_boundary.py', 'scripts/swift_view_structure.py', 'scripts/benchmark_docs.py', 'scripts/ui_observation.py',
}


def changed_files(root, base):
    revision = subprocess.check_output(['git', 'rev-parse', '--verify', base + '^{commit}'], cwd=root, text=True).strip()
    changed = subprocess.check_output(['git', 'diff', '--name-only', '-z', revision, '--'], cwd=root)
    added = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '-z'], cwd=root)
    return revision, sorted(set((changed + added).decode().split('\0')) - {''})


def changes_since(path, current):
    previous = json.loads(path.read_text())
    if (previous.get('status') != 'passed' or not previous.get('steps')
            or any(step.get('status') != 'passed' for step in previous['steps'])
            or previous.get('source_start') != previous.get('source_end')
            or not isinstance(previous.get('source_end'), dict)):
        raise ValueError('--since requires a successful, source-stable result')
    return differences(previous['source_end'], current)


def plan(paths, scope='auto'):
    """Select complete target suites; never infer individual test names from filenames."""
    selected = {}
    manual = []
    def select(name, reason):
        selected.setdefault(name, []).append(reason)
    select('static', '仕上げの共通検査')
    for path in paths:
        if path.endswith('.md') or path.startswith('docs/') or path.startswith('.agents/'):
            continue
        if path.startswith(('app/NibblePerformanceTests/', 'app/TestSupport/')) or path in {
                'app/performance-project.json', 'app/Nibble.xcodeproj/xcshareddata/xcschemes/NibblePerformance.xcscheme'}:
            manual.append('再生の時間・メモリ: --scope performance（' + path + '）')
            if path.startswith('app/TestSupport/'):
                select('product-test', path + ': 共有する画面ホスト')
        elif path.startswith('app/NibbleTests/'):
            select('product-test', path + ': 製品テスト')
        elif path.startswith('validation/VerificationAppTests/'):
            select('fixture-test', path + ': fixtureテスト')
        elif path in {'scripts/inspect_ui.py', 'scripts/ui_preview.py'} or path.startswith('scripts/tests/macos/'):
            select('preview-native', path + ': macOSのPNGデコード・切出し・縮小')
        elif path in STATIC_SCRIPTS or path.startswith(('scripts/tests/', 'scripts/examples/', 'tools/ui-design/', '.github/')):
            continue
        elif path.startswith('app/'):
            for name in PRODUCT_STEPS:
                select(name, path + ': 製品の表示・操作へ影響')
            if path.startswith(('app/Shared/', 'app/NibbleShare/', 'app/NibbleKeyboard/', 'app/Nibble.xcodeproj/')):
                manual.append('共有拡張・キーボードのOS導線: docs/ios-verification.md（' + path + '）')
        elif path == 'scripts/check_library_ui.py':
            select('library-ui', path)
        elif path == 'scripts/check_notice_ui.py':
            select('notice-ui', path)
        elif path == 'scripts/check_controls_ui.py':
            select('controls-ui', path)
        elif path == 'scripts/check_interface_ui.py':
            select('interface-ui', path)
        elif path == 'scripts/check_about_ui.py':
            select('about-ui', path)
            select('keyboard-guide-ui', path)
        elif path in {'validation/StoreBenchmark.swift', 'scripts/benchmark_store.py'}:
            manual.append('保存層の性能: docs/performance-verification.md（' + path + '）')
        elif path.startswith('validation/'):
            for name in ('fixture-test', 'fixture-smoke'):
                select(name, path + ': 実行基盤のfixture')
        else:
            for name in REGRESSION_STEPS[1:]:
                select(name, path + ': 共通基盤・設定・未知の変更は通常回帰を検査')
    all_steps = REGRESSION_STEPS + PERFORMANCE_STEPS
    if scope != 'auto':
        selected = {name: ['明示したscope: ' + scope] for name in SCOPES[scope] | {'static'}}
    omitted = [{'id': name, 'reason': ('測定条件を決めて明示的に実行する' if name in PERFORMANCE_STEPS else
                                               '変更から自動選択されない' if scope == 'auto' else '明示したscopeの対象外')}
               for name in all_steps if name not in selected]
    return {'scope': scope, 'changed_files': paths,
            'steps': [{'id': name, 'reasons': selected[name]} for name in all_steps if name in selected],
            'excluded': omitted, 'manual_review': sorted(set(manual)),
            'preconditions': [],
            'coverage': '選択したローカル工程・targetの全テスト・UI導線。手動確認・媒体の目視は別途必要'}


def command_for(name, device):
    if name == 'static':
        return ['nix', 'flake', 'check', '--no-update-lock-file', '--print-build-logs']
    if name == 'preview-native':
        return [sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/tests/macos', '-v']
    if not device:
        raise ValueError('iOSの計画には専用Simulatorの --device UDID が必要です')
    stage = STAGES[name]
    if stage.project:
        return [sys.executable, 'scripts/ios.py', stage.command,
                '--project-config', stage.project, '--configuration', 'Release', '--device', device]
    return [sys.executable, 'scripts/' + stage.script, '--device', device, *stage.arguments]


def execute(argv, log, timeout, session=None):
    """Interrupt the whole command group and wait for cleanup before the next step."""
    with log.open('wb') as stream:
        process = subprocess.Popen(argv, cwd=ROOT, stdout=stream, stderr=stream, start_new_session=True,
                                   env={**os.environ, 'NIBBLE_UI_FORMAT': 'json', 'NIBBLE_VERIFICATION_SESSION': session or ''})
        try:
            return process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            try:
                os.killpg(process.pid, signal.SIGINT)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise


def run_plan(selected, directory, device, timeout=1800):
    # All commands are materialized first: missing device must not leave partial work.
    steps = [{**step, 'argv': command_for(step['id'], device), 'status': 'pending'} for step in selected['steps']]
    directory.mkdir(parents=True, exist_ok=False)
    start = time.monotonic()
    report = {**selected, 'steps': steps, 'status': 'running',
              'started_at': datetime.now(timezone.utc).isoformat(), 'source_start': working_hashes(ROOT)}
    def save():
        (directory / 'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    save()
    try:
        if selected.get('planning_source', report['source_start']) != report['source_start']:
            raise ValueError('Sources changed after planning')
        for step in steps:
            if differences(report['source_start'], working_hashes(ROOT)):
                raise ValueError('計画中にソースが変更されました。新しいrunで再計画してください')
            step_start = time.monotonic()
            before = set((ROOT / 'artifacts/ios').glob('*/manifest.json'))
            step.update(status='running', log=step['id'] + '.log')
            save()
            try:
                with ui.step(step['id']):
                    step['exit_code'] = execute(step['argv'], directory / step['log'], timeout, session=str(directory.resolve()))
                    if step['exit_code']:
                        raise ValueError(step['id'] + ' failed; inspect ' + str(directory / step['log']))
                step['status'] = 'passed'
            finally:
                step['seconds'] = round(time.monotonic() - step_start, 6)
                step['runs'] = [str(path.parent.relative_to(ROOT)) for path in sorted(
                    set((ROOT / 'artifacts/ios').glob('*/manifest.json')) - before)]
                step['runs'] = [name for name in step['runs'] if json.loads((ROOT / name / 'manifest.json').read_text()).get('session') == str(directory.resolve())]
                if step['status'] == 'running':
                    step['status'] = 'failed'
                save()
            if step['id'] not in OFFLINE_STEPS:
                from check_evidence import check_run
                if not step['runs']:
                    step['status'] = 'failed'
                    raise ValueError('iOS command did not produce a run')
                for name in step['runs']:
                    try:
                        manifest = check_run(ROOT / name, report['source_start'])
                        if manifest['device']['udid'] != device:
                            raise ValueError('Evidence device differs from the plan')
                        if manifest.get('environment', {}).get('configuration') != 'Release':
                            raise ValueError('Evidence configuration differs from the plan')
                        stage = STAGES[step['id']]
                        if manifest['project']['scheme'] != stage.scheme:
                            raise ValueError('Evidence target differs from the plan')
                        if manifest['command'] != stage.command:
                            raise ValueError('Planned verification did not run')
                    except (ValueError, OSError, KeyError):
                        step['status'] = 'failed'
                        raise
                step['integrity'] = 'passed'
                save()
        report['status'] = 'passed'
    except (ValueError, OSError, KeyError, subprocess.SubprocessError, KeyboardInterrupt) as error:
        report.update(status='failed', error=str(error) or 'Interrupted')
    finally:
        report['source_end'] = working_hashes(ROOT)
        if differences(report['source_start'], report['source_end']):
            report.update(status='failed', error='Sources changed during verification')
        report.update(elapsed_seconds=round(time.monotonic() - start, 6),
                      finished_at=datetime.now(timezone.utc).isoformat())
        save()
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('plan', 'run'))
    parser.add_argument('--base', default='origin/main', help='Compare this revision with the working tree, including untracked files')
    parser.add_argument('--since', type=Path, help='Only changes since this successful result; failed results cannot suppress work')
    parser.add_argument('--scope', choices=('auto', *SCOPES), default='auto')
    parser.add_argument('--device')
    parser.add_argument('--output', type=Path, help='New directory; existing results are never overwritten')
    args = parser.parse_args(argv)
    try:
        before = working_hashes(ROOT)
        revision, paths = changed_files(ROOT, args.base)
        if args.since:
            paths = changes_since(args.since, before)
        if before != working_hashes(ROOT):
            raise ValueError('Sources changed while planning')
        selected = {'base': revision, 'since': str(args.since) if args.since else None,
                    'planning_source': before, **plan(paths, args.scope)}
        if args.action == 'plan':
            print(json.dumps({key: value for key, value in selected.items() if key != 'planning_source'}, ensure_ascii=False, indent=2))
            return 0
        directory = args.output or ROOT / 'artifacts/verify' / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:6])
        report = run_plan(selected, directory, args.device)
        print(json.dumps({'status': report['status'], 'result': str(directory / 'result.json'),
                          'elapsed_seconds': report['elapsed_seconds'], 'manual_review': report['manual_review']}, ensure_ascii=False))
        ui.result(report['status'] == 'passed', str(directory / 'result.json'))
        return 0 if report['status'] == 'passed' else 1
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        ui.message(str(error), 'error')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
