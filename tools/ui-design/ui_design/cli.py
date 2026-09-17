"""Portable CLI: explicit project root and project-relative policy; JSON on stdout."""

import argparse
import json
from pathlib import Path
import sys

from . import check, snapshot


def main(argv=None):
    cli = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    cli.add_argument('--root', type=Path, required=True)
    cli.add_argument('--config', required=True, help='Policy path relative to project root')
    sub = cli.add_subparsers(dest='command', required=True)
    sub.add_parser('check', help='Read-only check; never changes the review record')
    candidate = sub.add_parser('snapshot', help='Print a candidate record after reviewing design impact')
    candidate.add_argument('--summary', required=True)
    candidate.add_argument('--reference', action='append', required=True, dest='references')
    args = cli.parse_args(argv)
    try:
        report = check(args.root, args.config) if args.command == 'check' else snapshot(
            args.root, args.config, args.summary, args.references)
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return bool(report.get('errors'))
    except (OSError, ValueError, TypeError) as error:
        print(f'UI design check failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
