#!/bin/bash
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

# Validates resources Grove actually produces against the profiles Grove publishes.
#
# The unit tests check the converter and the IG Publisher checks the guide's hand-written
# examples; neither crosses the gap between them. This does: it runs the conformance
# fixture target, which writes one resource per shape into .build/conformance-fixtures,
# then puts those bytes through the HL7 validator with both implementation guide packages
# loaded.
#
# Usage: Scripts/validate-fhir-conformance.sh
#
# With nothing installed, this clones the grove-fhir guides into .fhir, downloads the
# validator the guides pin, and builds the two packages there — a first run therefore needs
# git, java, node, and ruby, and takes the better part of an hour. Set FHIR_VALIDATOR,
# GROVE_IG_CORE, and GROVE_IG_PLATFORMS to skip all of that and point at what you already
# have; grove-fhir's own cross-repository job does exactly that.

set -euo pipefail

cd "$(dirname "$0")/.."

# The fixture tests derive this from their own #filePath, because xcodebuild does not forward
# the shell's environment into the test process.
OUT="$(pwd)/.build/conformance-fixtures"
GUIDES="${GROVE_FHIR_GUIDES:-$(pwd)/.fhir/grove-fhir}"
VALIDATOR="${FHIR_VALIDATOR:-$GUIDES/.build/fhir-tools/validator_cli.jar}"
CORE_PACKAGE="${GROVE_IG_CORE:-$GUIDES/ig/output/package.tgz}"
PLATFORMS_PACKAGE="${GROVE_IG_PLATFORMS:-$GUIDES/platforms/output/package.tgz}"

if [ ! -d "$GUIDES" ]; then
    echo "==> cloning the guides into ${GUIDES#"$(pwd)/"}"
    git clone --depth 1 "${GROVE_FHIR_REMOTE:-https://github.com/SchmiedmayerLab/grove-fhir.git}" "$GUIDES"
fi

if [ ! -f "$VALIDATOR" ]; then
    echo "==> downloading the validator the guides pin"
    (cd "$GUIDES" && ./Scripts/download-fhir-tools.sh .build/fhir-tools)
fi

if [ ! -e "$CORE_PACKAGE" ] || [ ! -e "$PLATFORMS_PACKAGE" ]; then
    echo "==> building the guides (the IG Publisher takes a while)"
    (cd "$GUIDES" && npm ci && ./Scripts/build-guides.sh platforms ig)
fi


echo "==> emitting resources from the converter"
./Scripts/run-package-tests.sh GroveHealthKitFHIR macOS >/dev/null
./Scripts/run-package-tests.sh GroveQuestionnaire macOS >/dev/null
./Scripts/run-package-tests.sh GroveSensorKit iOS >/dev/null

count=$(find "$OUT" -name '*.json' | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
    echo "error: the fixture target wrote no resources to $OUT" >&2
    exit 1
fi
echo "    $count resources"

echo "==> validating against the published profiles"
java -jar "$VALIDATOR" -version 4.0.1 \
    -ig "$CORE_PACKAGE" -ig "$PLATFORMS_PACKAGE" \
    "$OUT"/*.json 2>&1 | tee "$OUT/validation.txt"

if grep -q '\*FAILURE\*' "$OUT/validation.txt"; then
    echo
    echo "FAILED — Grove produced resources that violate the profiles Grove publishes:"
    grep -E '^\s*Error @' "$OUT/validation.txt" | sed 's/, validating against.*//' | sort -u
    exit 1
fi

echo "OK — every produced resource conforms to its declared profile."
