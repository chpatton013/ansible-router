#!/usr/bin/env bash
set -euo pipefail

tmpfile="$(mktemp)"

# Download the current listing of leap seconds from IETF to a temp file.
wget --no-cache --output-document="$tmpfile" {{ntp.leap_seconds_url}}

# Ensure the temp file is not empty.
test -s "$tmpfile"

# Make the temp file usable by the ntp user.
chown ntp:ntp "$tmpfile"
chmod 644 "$tmpfile"

# Overwrite the old leap seconds listing.
mv "$tmpfile" {{ntp.leap_seconds_file}}
