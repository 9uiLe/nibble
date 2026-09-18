#!/usr/bin/env python3
"""nibble adapter: bind the product policy to the portable UI design API and CLI."""

from script_ui import ui
from pathlib import Path
import sys

_TOOLKIT = Path(__file__).resolve().parents[1] / 'tools' / 'ui-design'
sys.path.insert(0, str(_TOOLKIT))

from ui_design import check as _check
from ui_design.cli import main as _main

_POLICY = 'docs/design/policy.json'


def check(root):
    return _check(root, _POLICY)


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    if any(arg == '--config' or arg.startswith('--config=') for arg in args):
        ui.result(False, 'This adapter uses docs/design/policy.json; use the shared CLI for other policies.')
        return 2
    # The shared CLI takes an explicit root. This adapter owns the repository default.
    if '--root' not in args and not any(arg.startswith('--root=') for arg in args):
        args = ['--root', str(Path(__file__).resolve().parents[1])] + args
    code = _main(['--config', _POLICY] + args)
    ui.result(not code, 'UI design: ' + ('failed' if code else 'completed; see stdout JSON'))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
