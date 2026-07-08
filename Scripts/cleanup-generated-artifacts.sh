#!/usr/bin/env bash
#
# This source file is part of the Stanford Spezi open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf .build .xcodebuild .derivedData .derivedData-* DerivedData

find . -maxdepth 1 -name "*.xcresult" -exec rm -rf {} +
find . -maxdepth 1 -name "*.xccovarchive" -exec rm -rf {} +
find . -maxdepth 1 -name "*.xccovreport" -exec rm -rf {} +
find . -maxdepth 1 -name "*.profraw" -exec rm -rf {} +
find . -maxdepth 1 -name "*.profdata" -exec rm -rf {} +
find . -name "__pycache__" -type d -prune -exec rm -rf {} +
