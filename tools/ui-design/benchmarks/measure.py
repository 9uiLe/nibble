"""Measure the public check Interface with fixed inputs; print JSON, write only temp files."""

import argparse
import gc
import json
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time
import tracemalloc


def fixture(root, source_count, rows, asset_mib):
    (root / 'src').mkdir()
    (root / 'design').mkdir()
    for index in range(source_count):
        (root / 'src' / f'view-{index:04}.txt').write_text('sample source\n' * 160)
    if asset_mib:
        with (root / 'src' / 'asset.bin').open('wb') as stream:
            for _ in range(asset_mib):
                stream.write(b'x' * 1024 * 1024)
    table = '| ID | Purpose | Reason | Evaluation |\n| --- | --- | --- | --- |\n'
    table += ''.join(f'| C{index:02} Item | Show content | Reading order | S01 |\n'
                     for index in range(1, rows + 1))
    (root / 'design/components.md').write_text(table)
    (root / 'design/screens.md').write_text(f'## S01 Library\n\nC01〜C{min(rows, 999):02}\n')
    policy = {
        'version': 1, 'record': 'design/review.json',
        'inputs': [{'path': 'src', 'kind': 'tree'}, {'path': 'design', 'kind': 'tree', 'references': True}],
        'registries': [
            {'prefix': 'C', 'path': 'design/components.md', 'format': 'table', 'columns': 4},
            {'prefix': 'S', 'path': 'design/screens.md', 'format': 'heading'},
        ],
    }
    (root / 'policy.json').write_text(json.dumps(policy))


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--toolkit', type=Path, required=True)
    cli.add_argument('--samples', type=int, default=7)
    args = cli.parse_args()
    if args.samples < 3:
        cli.error('Use at least three samples')
    sys.path.insert(0, str(args.toolkit.resolve()))
    from ui_design import check, snapshot
    report = {'python': sys.version, 'platform': platform.platform(), 'samples': args.samples,
              'runtime_source_bytes': sum(p.stat().st_size for p in (args.toolkit / 'ui_design').glob('*.py')),
              'scenarios': {}}
    for name, sources, rows, asset in [('small', 16, 40, 0), ('catalog', 256, 1500, 0), ('asset', 16, 40, 32)]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture(root, sources, rows, asset)
            record = snapshot(root, 'policy.json', 'Benchmark fixture contracts.', ['design/components.md'])
            (root / 'design/review.json').write_text(json.dumps(record))
            def operation():
                result = check(root, 'policy.json')
                if result['errors']:
                    raise RuntimeError(result['errors'])
            operation()  # Warm filesystem and parser imports outside the samples.
            samples = []
            for _ in range(args.samples):
                gc.collect()
                start = time.perf_counter()
                operation()
                samples.append((time.perf_counter() - start) * 1000)
            gc.collect()
            tracemalloc.start()
            operation()
            _, peak = tracemalloc.get_traced_memory()
            tracemalloc.stop()
            command = [sys.executable, '-m', 'ui_design', '--root', str(root), '--config', 'policy.json', 'check']
            cli_samples = []
            for _ in range(args.samples):
                start = time.perf_counter()
                subprocess.run(command, cwd=args.toolkit.resolve(), capture_output=True, check=True)
                cli_samples.append((time.perf_counter() - start) * 1000)
            report['scenarios'][name] = {
                'sources': sources, 'rows': rows, 'asset_mib': asset,
                'milliseconds': samples, 'median_ms': statistics.median(samples),
                'peak_python_bytes': peak, 'cli_milliseconds': cli_samples,
                'cli_median_ms': statistics.median(cli_samples),
            }
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
