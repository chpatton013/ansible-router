#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id --user)" != 0 ]]; then
  echo This script must be run as root! Exiting. >&2
  exit 1
fi

script_dir="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${SETUP_LOG_FILE:-}" ]; then
  SETUP_LOG_FILE=/tmp/setup.log
fi
echo Writing output to log file $SETUP_LOG_FILE

function get_python() {
  if which python &>/dev/null; then
    return
  fi
  echo Installing Python...
  apt-get update
  apt-get install --assume-yes python
}

function _get_pip_major_version() {
  pip --version | sed --regexp-extended --expression='s#^pip ([0-9]+)\..*$#\1#'
}

function get_pip() {
  if which pip &>/dev/null && [[ "$(_get_pip_major_version)" -ge 19 ]]; then
    return
  fi
  echo Installing Pip...
  wget --quiet --output-document=- https://bootstrap.pypa.io/get-pip.py | python
}

function get_dependencies() {
  echo Installing dependencies...
  pip install --requirement "$script_dir/requirements.txt"
}

function run_playbook() {
  ANSIBLE_FORCE_COLOR=true ansible-playbook "$script_dir/playbook.yaml" \
    --inventory-file="$script_dir/inventory/hosts" \
    "$@"
}

(
  get_python
  get_pip
  get_dependencies
  run_playbook "$@"
) |& tee "$SETUP_LOG_FILE"
