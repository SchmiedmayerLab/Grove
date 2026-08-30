#!/usr/bin/env bash
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

# Emits the selected Swift producer's R4 resources and validates them against the exact
# adapter-inclusive grove-fhir package stack. No resources are uploaded.
#
# Usage: Scripts/validate-fhir-conformance.sh [healthkit|questionnaire|sensor|all]

set -euo pipefail

cd "$(dirname "$0")/.."

./Scripts/check-fhir-canonical-hygiene.sh

COMPONENT="${1:-${GROVE_FHIR_COMPONENT:-healthkit}}"
GUIDES="${GROVE_FHIR_GUIDES:-$(pwd)/.fhir/grove-fhir}"
GROVE_FHIR_REF="${GROVE_FHIR_REF:-90b23e647f1dd728035c64348abede5746375529}"

if [ "$COMPONENT" = "all" ]; then
    for component in healthkit questionnaire sensor; do
        "$0" "$component"
    done
    exit 0
fi

# One guide list per component; package names and ids derive from it below.
case "$COMPONENT" in
    healthkit)     TEST_PACKAGE="GroveHealthKitFHIR"; GUIDE_NAMES=(mobile sensor healthkit) ;;
    questionnaire) TEST_PACKAGE="GroveQuestionnaire"; GUIDE_NAMES=(questionnaire) ;;
    sensor)        TEST_PACKAGE="GroveSensorKitFHIR"; GUIDE_NAMES=(mobile sensor sensorkit) ;;
    *)
        echo "error: unsupported FHIR conformance component '$COMPONENT'" >&2
        exit 2
        ;;
esac

OUT="$(pwd)/.build/conformance-fixtures/$COMPONENT"

if [ ! -d "$GUIDES" ]; then
    echo "==> cloning grove-fhir ref $GROVE_FHIR_REF"
    mkdir -p "$(dirname "$GUIDES")"
    git init "$GUIDES"
    git -C "$GUIDES" remote add origin \
        "${GROVE_FHIR_REMOTE:-https://github.com/SchmiedmayerLab/grove-fhir.git}"
    git -C "$GUIDES" fetch --depth 1 origin "$GROVE_FHIR_REF"
    git -C "$GUIDES" checkout --detach FETCH_HEAD
fi

echo "==> grove-fhir contract"
ACTUAL_GROVE_FHIR_REF="$(git -C "$GUIDES" rev-parse HEAD)"
EXPECTED_GROVE_FHIR_REF="$(git -C "$GUIDES" rev-parse --verify "$GROVE_FHIR_REF^{commit}" 2>/dev/null || true)"
if [ -z "$EXPECTED_GROVE_FHIR_REF" ] || [ "$ACTUAL_GROVE_FHIR_REF" != "$EXPECTED_GROVE_FHIR_REF" ]; then
    echo "error: $GUIDES is not checked out at requested grove-fhir ref $GROVE_FHIR_REF" >&2
    echo "error: actual grove-fhir SHA is $ACTUAL_GROVE_FHIR_REF" >&2
    exit 1
fi
echo "$ACTUAL_GROVE_FHIR_REF"
python3 Scripts/generate-grove-fhir-swift-contract.py \
    --catalog-directory "$GUIDES/catalog" \
    --check
if [ "$COMPONENT" = "healthkit" ]; then
    python3 Scripts/generate-grove-fhir-semantic-vector-fixtures.py \
        --corpus "$GUIDES/Conformance/corpora/mobile-semantics/corpus.json" \
        --check
fi
if [ "$COMPONENT" = "sensor" ]; then
    python3 Scripts/generate-grove-sensor-swift-contract.py \
        --sensor-catalog "$GUIDES/catalog/sensor-catalog.json" \
        --sensorkit-catalog "$GUIDES/catalog/sensorkit-adapter.json" \
        --format-registry "$GUIDES/catalog/format-registry.json" \
        --check
fi

VALIDATOR="${FHIR_VALIDATOR:-$GUIDES/.build/fhir-tools/validator_cli.jar}"
if [ ! -f "$VALIDATOR" ]; then
    echo "==> downloading the validator pinned by grove-fhir"
    (cd "$GUIDES" && ./Scripts/download-fhir-tools.sh .build/fhir-tools)
fi

package_arguments=()
manifest_package_arguments=()
missing_package=false
for guide in "${GUIDE_NAMES[@]}"; do
    package_path="$GUIDES/$guide/output/package.tgz"
    package_arguments+=(--package "$guide=$package_path")
    manifest_package_arguments+=(--package "$guide=org.grovealliance.fhir.$guide")
    if [ ! -f "$package_path" ]; then
        missing_package=true
    fi
done
if [ "$missing_package" = true ]; then
    echo "==> building ${GUIDE_NAMES[*]} implementation guides"
    (cd "$GUIDES" && npm ci && ./Scripts/build-guides.sh "${GUIDE_NAMES[@]}")
fi

mkdir -p "$OUT"
find "$OUT" -type f -delete

echo "==> emitting $COMPONENT resources from Swift"
./Scripts/run-package-tests.sh "$TEST_PACKAGE" macOS >/dev/null

count=$(find "$OUT" -name '*.json' | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
    echo "error: the fixture target wrote no resources to $OUT" >&2
    exit 1
fi
echo "    $count resources"

MANIFEST="$OUT/grove-fhir-producer.json"
# The guides state their own version; reading it here keeps the manifest from naming a stale one.
GUIDE_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' \
    "$GUIDES/catalog/measurement-catalog.json")"

python3 Scripts/generate-grove-fhir-producer-manifest.py \
    --resources "$OUT" \
    --output "$MANIFEST" \
    --producer-revision "$(git rev-parse HEAD)" \
    --package-version "$GUIDE_VERSION" \
    --semantic-vector-corpus "$GUIDES/Conformance/corpora/mobile-semantics/corpus.json" \
    "${manifest_package_arguments[@]}"

echo "==> validating $COMPONENT resources against the grove-fhir guides"
python3 "$GUIDES/Scripts/validate-producer.py" \
    --manifest "$MANIFEST" \
    --validator "$VALIDATOR" \
    "${package_arguments[@]}"

if [ "$COMPONENT" = "questionnaire" ]; then
    echo "==> validating the exact Questionnaire/Response pair"
    python3 "$GUIDES/Scripts/validate-questionnaire.py" \
        --questionnaire "$OUT/questionnaire.json" \
        --response "$OUT/questionnaire-response.json"
fi

echo "OK — all $COMPONENT resources conform to their declared R4 profiles."
