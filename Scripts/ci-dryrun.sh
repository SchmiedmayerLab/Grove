#!/usr/bin/env bash
#
# This source file is part of the Stanford Spezi open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
# Local dry-run of the Tests workflow's scheduling + detection (.github/workflows/tests.yml),
# WITHOUT running any tests. It reproduces the workflow's two non-trivial steps exactly:
#   1. determine changed files (same git diff logic as the `detect` job)
#   2. Scripts/affected-test-matrix.py  (the IDENTICAL script the CI runs)
# then enumerates the jobs the generated matrices (strategy.matrix: fromJSON(...)) would spawn.
#
# Usage:
#   Scripts/ci-dryrun.sh                 # your current uncommitted changes (working tree vs HEAD + untracked)
#   Scripts/ci-dryrun.sh <gitRefOrRange> # e.g. main, abc123, origin/main...HEAD
#   Scripts/ci-dryrun.sh --files a.swift b.swift
#   Scripts/ci-dryrun.sh --all           # simulate a global change (everything)
set -euo pipefail
cd "$(dirname "$0")/.."

changed_files() {
  case "${1:-}" in
    --all)   echo "__ALL__" ;;
    --files) shift; printf '%s\n' "$@" ;;
    "")      { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u ;;
    *)       if printf '%s' "$1" | grep -q '\.\.'; then git diff --name-only "$1"; else git diff --name-only "$1"...HEAD; fi ;;
  esac
}

echo "=== changed files (detect job input) ==="
changed_files "$@" | sed 's/^/  /'
echo

OUT="$(changed_files "$@" | python3 Scripts/affected-test-matrix.py - 2>/dev/null)"
MATRIX="$(printf '%s\n' "$OUT" | sed -n 's/^matrix=//p')"
UI_MATRIX="$(printf '%s\n' "$OUT" | sed -n 's/^ui_matrix=//p')"
TRAIT_MATRIX="$(printf '%s\n' "$OUT" | sed -n 's/^trait_matrix=//p')"
HAS_JOBS="$(printf '%s\n' "$OUT" | sed -n 's/^has_jobs=//p')"
HAS_UI_JOBS="$(printf '%s\n' "$OUT" | sed -n 's/^has_ui_jobs=//p')"
HAS_TRAIT_JOBS="$(printf '%s\n' "$OUT" | sed -n 's/^has_trait_jobs=//p')"
AFFECTED="$(printf '%s\n' "$OUT" | sed -n 's/^affected=//p')"

echo "=== detect job outputs ==="
echo "  affected = $AFFECTED"
echo "  has_jobs = $HAS_JOBS"
echo "  has_ui_jobs = $HAS_UI_JOBS"
echo "  has_trait_jobs = $HAS_TRAIT_JOBS"
echo

if [ "$HAS_JOBS" != "true" ] && [ "$HAS_UI_JOBS" != "true" ] && [ "$HAS_TRAIT_JOBS" != "true" ]; then
  echo "=== scheduling ==="
  echo "  test, test-ui, and package_trait_builds jobs are SKIPPED — no package checks would run."
  exit 0
fi

echo "=== scheduling: GH Actions would create these 'test' jobs ==="
if [ "$HAS_JOBS" = "true" ]; then
  printf '%s' "$MATRIX" | python3 -c '
import json,sys
inc=json.load(sys.stdin)["include"]
for e in inc:
    print("  - test (%s / %s)  ->  Scripts/run-package-tests.sh %s %s" % (e["package"], e["platform"], e["package"], e["platform"]))
print("\n  total jobs scheduled: %d" % len(inc))
'
else
  echo "  test job is SKIPPED."
fi

echo
echo "=== scheduling: GH Actions would create these 'test-ui' jobs ==="
if [ "$HAS_UI_JOBS" = "true" ]; then
  printf '%s' "$UI_MATRIX" | python3 -c '
import json,sys
inc=json.load(sys.stdin)["include"]
for e in inc:
    print("  - test-ui (%s / %s)  ->  Scripts/run-package-tests.sh %s %s ui" % (e["package"], e["platform"], e["package"], e["platform"]))
print("\n  total UI jobs scheduled: %d" % len(inc))
'
else
  echo "  test-ui job is SKIPPED."
fi

echo
echo "=== scheduling: GH Actions would create these 'package_trait_builds' jobs ==="
if [ "$HAS_TRAIT_JOBS" = "true" ]; then
  printf '%s' "$TRAIT_MATRIX" | python3 -c '
import json,sys
inc=json.load(sys.stdin)["include"]
for e in inc:
    print("  - package_trait_builds (%s)  ->  Scripts/check-package-traits.py %s" % (e["package"], e["package"]))
print("\n  total package trait jobs scheduled: %d" % len(inc))
'
else
  echo "  package_trait_builds job is SKIPPED."
fi
