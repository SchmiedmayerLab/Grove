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

# These patterns identify retired FHIR namespaces only. Unrelated application URLs and
# lifecycle deep links are intentionally outside this gate.
retired_fhir_canonicals='grovealliance\.org/fhir/core|https?://spezi\.health/fhir|bdh\.stanford|spezi\.stanford[^"[:space:]]*/fhir'

# grep rather than rg: the runners carry no ripgrep, and a missing binary inside an `if`
# condition is exempt from `set -e`, so the gate used to report OK without having searched.
set +e
matches="$(grep -rEn "$retired_fhir_canonicals" Sources Tests)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    printf '%s\n' "$matches"
    echo "error: retired FHIR canonical found; Grove FHIR 0.6.0 has no alias or fallback layer" >&2
    exit 1
fi

# 1 means "searched, found nothing". Anything else means the search itself failed.
if [ "$status" -ne 1 ]; then
    echo "error: the canonical scan did not run (grep exited $status)" >&2
    exit 1
fi

echo "OK — no retired Grove, Stanford, or Spezi FHIR canonicals are present."
