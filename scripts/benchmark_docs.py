#!/usr/bin/env python3
"""Measure documentation checks against a fixed corpus, without writing project files."""

import argparse
import gc
import json
from pathlib import Path
import statistics
import sys
import time
import tracemalloc


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--scripts', type=Path, required=True, help='Implementation directory to measure')
    cli.add_argument('--root', type=Path, required=True, help='Fixed documentation corpus')
    cli.add_argument('--samples', type=int, default=7)
    args = cli.parse_args()
    if args.samples < 3:
        cli.error('Use at least three samples')
    sys.path.insert(0, str(args.scripts.resolve()))
    import check_docs
    def operation():
        result = check_docs.check(args.root.resolve())
        if result['errors']:
            raise RuntimeError(result['errors'])
        return result
    report = operation()
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
    print(json.dumps({'result': report, 'milliseconds': samples,
                      'median_ms': statistics.median(samples), 'peak_python_bytes': peak}, indent=2))


if __name__ == '__main__':
    main()
