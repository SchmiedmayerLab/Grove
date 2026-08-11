#!/usr/bin/env bash
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "${RUNNER_TEMP:-}" ]; then
  DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$RUNNER_TEMP/spezi-docs-derivedData}"
  DOC_OUTPUT_DIR="${DOC_OUTPUT_DIR:-$RUNNER_TEMP/spezi-documentation}"
else
  DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.derivedData-docs}"
  DOC_OUTPUT_DIR="${DOC_OUTPUT_DIR:-.build/documentation}"
fi

DOC_SCHEME="${DOC_SCHEME:-Grove-Package}"
DOC_DESTINATION="${DOC_DESTINATION:-generic/platform=iOS Simulator}"
DOC_DEPLOYMENT_TARGET="${DOC_DEPLOYMENT_TARGET:-18.0}"
DOC_LOG_PATH="${DOC_LOG_PATH:-$DOC_OUTPUT_DIR/docbuild.log}"
COMBINED_ARCHIVE="${COMBINED_ARCHIVE:-$DOC_OUTPUT_DIR/Grove.doccarchive}"
STATIC_ARCHIVE="${STATIC_ARCHIVE:-$DOC_OUTPUT_DIR/Grove-static.doccarchive}"

documentation_targets() {
  python3 - <<'PY'
import pathlib
import sys

lines = pathlib.Path(".spi.yml").read_text(encoding="utf-8").splitlines()

for index, line in enumerate(lines):
    stripped = line.strip()
    if stripped.startswith("- "):
        stripped = stripped[2:].strip()
    if not stripped.startswith("documentation_targets:"):
        continue

    _, value = stripped.split(":", maxsplit=1)
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        targets = [
            target.strip().strip("'\"")
            for target in value[1:-1].split(",")
            if target.strip()
        ]
    else:
        targets = []
        parent_indent = len(line) - len(line.lstrip())
        for child in lines[index + 1:]:
            child_stripped = child.strip()
            if not child_stripped or child_stripped.startswith("#"):
                continue
            child_indent = len(child) - len(child.lstrip())
            if child_indent <= parent_indent:
                break
            if child_stripped.startswith("- "):
                targets.append(child_stripped[2:].strip().strip("'\""))

    if not targets:
        sys.exit("Could not find documentation_targets in .spi.yml")
    print("\n".join(targets))
    sys.exit(0)

sys.exit("Could not find documentation_targets in .spi.yml")
PY
}

collect_repo_documentation_warnings() {
  python3 - "$PWD" "$DOC_LOG_PATH" <<'PY'
import pathlib
import sys

repo = pathlib.Path(sys.argv[1]).resolve()
log_path = pathlib.Path(sys.argv[2])
repo_prefix = f"{repo}/"
ignored_markers = (
    f"{repo}/.build/",
    f"{repo}/.derivedData",
    "/SourcePackages/",  # dependency checkouts — never this repository's own docs
)

warnings = []
for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
    if ": warning:" not in line or repo_prefix not in line:
        continue
    if any(marker in line for marker in ignored_markers):
        continue
    is_documentation_warning = (
        "/Sources/" in line and "/.docc/" in line
    ) or any(
        marker in line
        for marker in (
            " doesn't exist at ",
            " is ambiguous at ",
            "Parameter '" ,
            " not found in ",
        )
    )
    if not is_documentation_warning:
        continue
    warnings.append(line)

if warnings:
    print("Documentation warnings from this repository:")
    print("\n".join(warnings))
    sys.exit(1)
PY
}

targets=()
while IFS= read -r target; do
  targets+=("$target")
done < <(documentation_targets)

mkdir -p "$DOC_OUTPUT_DIR"
rm -rf "$COMBINED_ARCHIVE" "$STATIC_ARCHIVE"

export GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS="${GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS:-1}"
export GROVE_EXCLUDE_DOCC_CATALOGS=0
export LLVM_PROFILE_FILE="${LLVM_PROFILE_FILE:-$DOC_OUTPUT_DIR/default-%p.profraw}"

echo "Building DocC documentation for scheme '$DOC_SCHEME' with all default package traits enabled."
if ! xcodebuild \
    -scheme "$DOC_SCHEME" \
    -destination "$DOC_DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -skipPackageUpdates \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    IPHONEOS_DEPLOYMENT_TARGET="$DOC_DEPLOYMENT_TARGET" \
    docbuild \
    >"$DOC_LOG_PATH" 2>&1; then
  tail -n 200 "$DOC_LOG_PATH"
  exit 1
fi

collect_repo_documentation_warnings

archives=()
missing_targets=()
for target in "${targets[@]}"; do
  archive="$(find "$DERIVED_DATA_PATH/Build/Products" -maxdepth 3 -name "$target.doccarchive" -type d -print -quit)"
  if [ -z "$archive" ]; then
    missing_targets+=("$target")
  else
    archives+=("$archive")
  fi
done

if [ "${#missing_targets[@]}" -gt 0 ]; then
  printf 'Missing DocC archives for targets:\n' >&2
  printf '  %s\n' "${missing_targets[@]}" >&2
  exit 1
fi

xcrun docc merge \
  "${archives[@]}" \
  --output-path "$COMBINED_ARCHIVE" \
  --synthesized-landing-page-name Grove \
  --synthesized-landing-page-kind Package \
  --synthesized-landing-page-topics-style compactGrid

xcrun docc process-archive transform-for-static-hosting \
  "$COMBINED_ARCHIVE" \
  --output-path "$STATIC_ARCHIVE" \
  --hosting-base-path "${DOC_HOSTING_BASE_PATH:-/Spezi}"

echo "Built combined DocC archive at $COMBINED_ARCHIVE"
echo "Built static-hosting DocC archive at $STATIC_ARCHIVE"
