#!/usr/bin/env bash
set -xeuo pipefail

if [[ "$(id --user)" != 0 ]]; then
  echo This script must be run as root! Exiting. >&2
  exit 1
fi

if [ -z "${SETUP_LOG_FILE:-}" ]; then
  SETUP_LOG_FILE=/tmp/setup.log
fi
echo Writing output to log file $SETUP_LOG_FILE

(
  if ! which python &>/dev/null || ! which pip &>/dev/null; then
    apt-get update
    apt-get install --assume-yes python python-pip
  fi

  pip install --requirement requirements.txt

  ANSIBLE_FORCE_COLOR=true ansible-playbook playbook.yaml "$@"
) |& tee "$SETUP_LOG_FILE"
