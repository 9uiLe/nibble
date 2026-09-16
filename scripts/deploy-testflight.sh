#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec nix develop --command python3 -I scripts/testflight.py deploy "$@"
