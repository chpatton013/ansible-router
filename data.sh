#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id --user)" != 0 ]]; then
  echo This script must be run as root! Exiting. >&2
  exit 1
fi

script_dir="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp --recursive "$script_dir/data/"* /opt/router
