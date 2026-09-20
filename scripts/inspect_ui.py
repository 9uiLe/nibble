#!/usr/bin/env python3
"""Prepare accessibility summaries and PNG previews from saved Simulator observations.

Results are JSON on stdout. Processing status uses script_ui and hamio on stderr.
Review observations are recorded by the caller after viewing the prepared data.
"""

import argparse
import json
from pathlib import Path
import sys

from script_ui import ui
from ui_observation import summarize
from ui_preview import create_preview


def parser():
    cli = argparse.ArgumentParser(description=__doc__)
    sub = cli.add_subparsers(dest='command', required=True)
    tree = sub.add_parser('tree', help='Summarize saved sim-use accessibility data')
    tree.add_argument('source', type=Path, help='sim-use JSON envelope or Run.ui data object')
    tree.add_argument('--before', type=Path, help='Compare complete selected values and counts; ignore order')
    tree.add_argument('--id', action='append', default=[], help='Select this exact uniqueId; repeatable')
    tree.add_argument('--frames', action='store_true', help='Include and compare frames in point units')
    tree.add_argument('--limit', type=int, default=30, help='Element limit per result group (default: 30)')
    tree.add_argument('--text-limit', type=int, default=160, help='Characters per label/value (default: 160); 0 for full text')
    picture = sub.add_parser('image', help='Create a PNG viewing artifact outside recorded runs (macOS)')
    picture.add_argument('source', type=Path, help='Original PNG screenshot or extracted video frame')
    picture.add_argument('--output', type=Path, required=True, help='New directory under artifacts/ui-review/')
    picture.add_argument('--max-edge', type=int, default=960, help='Longest edge in pixels (default: 960); no upscaling')
    picture.add_argument('--crop', nargs=4, type=int, metavar=('X', 'Y', 'WIDTH', 'HEIGHT'),
                         help='Crop before resizing, in original pixels from the top-left corner')
    return cli


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        if args.command == 'tree':
            report = summarize(args.source, before=args.before, identifiers=args.id, frames=args.frames,
                               limit=args.limit, text_limit=args.text_limit)
        else:
            report = create_preview(args.source, args.output, max_edge=args.max_edge, crop=args.crop)
        print(json.dumps(report, ensure_ascii=False, separators=(',', ':'), allow_nan=False))
        ui.result(True, 'Viewing data prepared; visual review is separate')
        return 0
    except (OSError, ValueError, KeyboardInterrupt) as error:
        ui.message(str(error) or 'Interrupted', 'error')
        return 1


if __name__ == '__main__':
    sys.exit(main())
