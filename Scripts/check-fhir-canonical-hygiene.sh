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

if rg -n --no-heading "$retired_fhir_canonicals" Sources Tests; then
    echo "error: retired FHIR canonical found; v0.2 has no alias or fallback layer" >&2
    exit 1
fi

echo "OK — no retired Grove, Stanford, or Spezi FHIR canonicals are present."
