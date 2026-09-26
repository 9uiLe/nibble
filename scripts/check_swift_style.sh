#!/bin/sh
set -eu

repo_root=$(
  unset CDPATH
  cd -- "$(dirname -- "$0")/.."
  pwd
)
cd "$repo_root"

swiftlint lint --strict --quiet --no-cache --config .swiftlint.yml
swiftformat --lint --config .swiftformat --cache ignore app runtime scripts validation
