#!/usr/bin/env bash
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
# SPDX-License-Identifier: MIT
#
# A runner's newest installed version is not necessarily the current stable release.
set -euo pipefail
actual="$(xcodebuild -version)"
expected=$'Xcode 27.2\nBuild version 27B52'
printf '%s\n' "$actual"
if [[ "$actual" != "$expected" ]]; then
  echo 'Expected stable Xcode 27.2 (27B52); install/select it before verification.' >&2
  exit 1
fi
