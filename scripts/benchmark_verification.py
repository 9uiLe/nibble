#!/usr/bin/env python3
"""Measure sequential verification cycles from an explicit JSON command list."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import time

from script_ui import ui
from verification_evidence import working_hashes
from verify import execute

ROOT = Path(__file__).resolve().parents[1]


def summarize(rows, elapsed):
    values = [row['seconds'] for row in rows if row['status'] == 'passed']
    return {'attempts': len(rows), 'passed': len(values), 'failed': sum(row['status'] == 'failed' for row in rows),
            'incomplete': sum(row['status'] not in {'passed', 'failed'} for row in rows),
            'median_seconds': statistics.median(values) if values else None,
            'min_seconds': min(values) if values else None, 'max_seconds': max(values) if values else None,
            'range_seconds': max(values) - min(values) if values else None,
            'stdev_seconds': statistics.stdev(values) if len(values) > 1 else None,
            'observed_cycles_per_hour': len(values) * 3600 / elapsed if elapsed else 0,
            'measurement_window_seconds': elapsed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--commands', type=Path, required=True, help='JSON array of argv arrays; run sequentially in each cycle')
    parser.add_argument('--output', type=Path, required=True, help='New directory')
    parser.add_argument('--samples', type=int, default=3)
    parser.add_argument('--condition', required=True, help='Record cache/Simulator/dependency state and representative edit')
    args = parser.parse_args()
    if args.samples < 1:
        parser.error('--samples must be positive')
    commands = json.loads(args.commands.read_text())
    if not commands or not isinstance(commands, list) or any(
            not isinstance(row, list) or not row or any(not isinstance(arg, str) for arg in row) for row in commands):
        parser.error('--commands must contain nonempty argv arrays')
    args.output.mkdir(parents=True, exist_ok=False)
    results = {'condition': args.condition, 'commands': commands, 'samples_requested': args.samples,
               'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
               'source_hashes': working_hashes(ROOT), 'platform': platform.platform(),
               'started_at': datetime.now(timezone.utc).isoformat(), 'cycles': [],
               'review': 'Human media review time is excluded; inspect failed runs before any new attempt.'}
    start = time.monotonic()
    def save():
        elapsed = time.monotonic() - start
        results['summary'] = summarize(results['cycles'], elapsed)
        (args.output / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
    save()
    for index in range(args.samples):
        cycle = {'index': index, 'steps': [], 'status': 'running', 'load_before': os.getloadavg()}
        results['cycles'].append(cycle)
        cycle_start = time.monotonic()
        try:
            for step_index, argv in enumerate(commands):
                before = set((ROOT / 'artifacts/ios').glob('*/manifest.json'))
                step_start = time.monotonic()
                row = {'argv': argv, 'log': f'{index}-{step_index}.log'}
                cycle['steps'].append(row)
                save()
                try:
                    row['exit_code'] = execute(argv, args.output / row['log'], 1800, session=str(args.output.resolve()))
                finally:
                    row['seconds'] = time.monotonic() - step_start
                    row['runs'] = [str(p.parent.relative_to(ROOT)) for p in sorted(
                        set((ROOT / 'artifacts/ios').glob('*/manifest.json')) - before)]
                row['runs'] = [name for name in row['runs'] if json.loads((ROOT / name / 'manifest.json').read_text()).get('session') == str(args.output.resolve())]
                if row['exit_code']:
                    raise ValueError(f'Command exited {row["exit_code"]}; inspect {row["log"]}')
            if working_hashes(ROOT) != results['source_hashes']:
                raise ValueError('Source inputs changed during measurement')
            cycle['status'] = 'passed'
        except (ValueError, OSError, subprocess.SubprocessError, KeyboardInterrupt) as error:
            cycle.update(status='failed', error=str(error) or 'Interrupted')
        finally:
            cycle.update(seconds=time.monotonic() - cycle_start, load_after=os.getloadavg())
            save()
        ui.result(cycle['status'] == 'passed', f'cycle {index + 1}: {cycle["seconds"]:.3f}s')
        if cycle['status'] != 'passed':
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
