#!/usr/bin/env bash
set -xeuo pipefail

if [[ "$(id --user)" != 0 ]]; then
  echo This script must be run as root! Exiting. >&2
  exit 1
fi

if ! which python &>/dev/null || ! which pip &>/dev/null; then
  apt-get update
  apt-get install --assume-yes python python-pip
fi

pip install --requirement requirements.txt

ansible-playbook playbook.yaml "$@"
