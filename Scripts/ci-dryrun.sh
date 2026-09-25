#!/usr/bin/env bash
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
# Local dry-run of the Tests workflow's scheduling + detection (.github/workflows/tests.yml),
# WITHOUT running any tests. It reproduces the workflow's two non-trivial steps exactly:
#   1. determine changed files (same git diff logic as the `detect` job)
#   2. Scripts/affected-test-matrix.py  (the IDENTICAL script the CI runs)
# then enumerates the jobs the `test` matrix (strategy.matrix: fromJSON(...)) would spawn.
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

base_ref() {
  case "${1:-}" in
    --all|--files) return 0 ;;
    "") git rev-parse HEAD ;;
    *...*)
      local left="${1%%...*}" right="${1#*...}"
      git merge-base "$left" "$right"
      ;;
    *..*) git rev-parse "${1%%..*}" ;;
    *) git merge-base "$1" HEAD ;;
  esac
}

TMP="$(mktemp -d)"
trap 'git worktree remove --force "$TMP/base" 2>/dev/null || true; rm -rf "$TMP"' EXIT
changed_files "$@" > "$TMP/changed.txt"

echo "=== changed files (detect job input) ==="
sed 's/^/  /' "$TMP/changed.txt"
echo

ARGS=("$TMP/changed.txt")
BASE_REF="$(base_ref "$@")"
if [ -n "$BASE_REF" ] && { grep -Fxq "Package.swift" "$TMP/changed.txt" || grep -Fxq "packages.toml" "$TMP/changed.txt"; }; then
  git worktree add --detach "$TMP/base" "$BASE_REF" >/dev/null
  cp "$TMP/base/packages.toml" "$TMP/base-packages.toml"
  ARGS+=(--base-packages "$TMP/base-packages.toml")
  if grep -Fxq "Package.swift" "$TMP/changed.txt"; then
    swift package --package-path "$TMP/base" dump-package > "$TMP/base-package.json"
    swift package dump-package > "$TMP/head-package.json"
    ARGS+=(--base-package-dump "$TMP/base-package.json" --head-package-dump "$TMP/head-package.json")
  fi
fi

OUT="$(python3 Scripts/affected-test-matrix.py "${ARGS[@]}" 2>/dev/null)"
MATRIX="$(printf '%s\n' "$OUT" | sed -n 's/^matrix=//p')"
HAS_JOBS="$(printf '%s\n' "$OUT" | sed -n 's/^has_jobs=//p')"
HAS_FHIR_CONFORMANCE="$(printf '%s\n' "$OUT" | sed -n 's/^has_fhir_conformance=//p')"
AFFECTED="$(printf '%s\n' "$OUT" | sed -n 's/^affected=//p')"

echo "=== detect job outputs ==="
echo "  affected = $AFFECTED"
echo "  has_jobs = $HAS_JOBS"
echo "  has_fhir_conformance = $HAS_FHIR_CONFORMANCE"
echo

if [ "$HAS_JOBS" != "true" ]; then
  echo "=== scheduling ==="
  echo "  test job is SKIPPED (if: has_jobs == 'true' is false) — no tests would run."
  exit 0
fi

echo "=== scheduling: GH Actions would create these 'test' jobs (from strategy.matrix: fromJSON) ==="
printf '%s' "$MATRIX" | python3 -c '
import json,sys
inc=json.load(sys.stdin)["include"]
for e in inc:
    print("  - test (%s / %s)  ->  Scripts/run-package-tests.sh %s %s" % (e["package"], e["platform"], e["package"], e["platform"]))
print("\n  total jobs scheduled: %d" % len(inc))
'
