#!/usr/bin/env bash
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
# Every .swift.gyb template has its rendered .swift committed beside it, and nothing regenerated
# them, so a template edit could ship without its output. This regenerates each one and fails on
# any difference.

set -euo pipefail

# Rendering must not leave a __pycache__ beside the sources; SwiftPM reports it as an
# unhandled file in the target.
export PYTHONDONTWRITEBYTECODE=1

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PACKAGE_ROOT
cd "$PACKAGE_ROOT"

GYB="${GYB:-}"
if [[ -z "$GYB" ]]; then
    # Homebrew ships gyb with a python2.7 shebang; the module itself runs under python3.
    for candidate in /opt/homebrew/bin/gyb.py /usr/local/bin/gyb.py; do
        [[ -f "$candidate" ]] && GYB="$candidate" && break
    done
fi
if [[ -z "$GYB" ]]; then
    echo "gyb.py not found; set GYB to its path" >&2
    exit 2
fi
readonly GYB

status=0
count=0
while IFS= read -r -d '' template; do
    rendered="${template%.gyb}"
    if [[ ! -f "$rendered" ]]; then
        echo "missing generated output for $template" >&2
        status=1
        continue
    fi
    actual="$(mktemp)"
    python3 "$GYB" --line-directive '' "$template" > "$actual"
    if ! diff -q "$rendered" "$actual" > /dev/null; then
        echo "generated output is stale: $rendered" >&2
        diff -u "$rendered" "$actual" | head -40 >&2
        status=1
    fi
    rm -f "$actual"
    count=$((count + 1))
done < <(find Sources -name '*.swift.gyb' -print0)

# Zero templates means the search broke, not that everything is in order.
if [[ $count -eq 0 ]]; then
    echo "found no .swift.gyb templates; the check would pass vacuously" >&2
    exit 1
fi
if [[ $status -eq 0 ]]; then
    echo "Verified $count generated Swift file(s) match their gyb templates."
fi
exit $status
