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
GROVE_FHIR_REF="${GROVE_FHIR_REF:-0.8.0}"
GUIDE_SOURCE="${GROVE_FHIR_GUIDE_SOURCE:-}"

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
    # A tag is fetched into its own ref, so the check below can resolve it; a commit is fetched as is.
    git -C "$GUIDES" fetch --depth 1 origin "+refs/tags/$GROVE_FHIR_REF:refs/tags/$GROVE_FHIR_REF" 2>/dev/null \
        || git -C "$GUIDES" fetch --depth 1 origin "$GROVE_FHIR_REF"
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

FHIR_HOME="${GROVE_FHIR_HOME_OVERRIDE:-$GUIDES/.build/fhir-home}"
VALIDATOR="${FHIR_VALIDATOR:-$GUIDES/.build/fhir-tools/validator_cli.jar}"
# The validator resolves packages from the cache the download seeds; a validator supplied from elsewhere brings none.
if [ ! -f "$VALIDATOR" ] || [ ! -d "$FHIR_HOME/.fhir/packages" ]; then
    echo "==> downloading the validator pinned by grove-fhir"
    # The download seeds the validator's package cache with grove-fhir's Node helper, which needs its packages.
    (cd "$GUIDES" && npm ci && ./Scripts/download-fhir-tools.sh .build/fhir-tools)
fi

# Where the guide packages come from: `release` installs the ones the grove-fhir release built from this tag, `build`
# builds them from source, and `compare` builds them and checks that they match the release. Building takes most of an
# hour, so a tag defaults to its release; a commit has no release and is built.
if [ -z "$GUIDE_SOURCE" ]; then
    if [ "$(git -C "$GUIDES" rev-parse -q --verify "refs/tags/$GROVE_FHIR_REF^{commit}" || true)" = "$ACTUAL_GROVE_FHIR_REF" ]; then
        GUIDE_SOURCE=release
    else
        GUIDE_SOURCE=build
    fi
fi

package_arguments=()
manifest_package_arguments=()
for guide in "${GUIDE_NAMES[@]}"; do
    package_arguments+=(--package "$guide=$GUIDES/$guide/output/package.tgz")
    manifest_package_arguments+=(--package "$guide=org.grovealliance.fhir.$guide")
done
release_packages=(
    python3 Scripts/fetch-grove-fhir-release-packages.py
    --guides "$GUIDES" --release "$GROVE_FHIR_REF" --commit "$ACTUAL_GROVE_FHIR_REF"
)
case "$GUIDE_SOURCE" in
    release)
        echo "==> installing the ${GUIDE_NAMES[*]} guide packages from the grove-fhir $GROVE_FHIR_REF release"
        if [ ! -d "$GUIDES/node_modules" ]; then
            (cd "$GUIDES" && npm ci)
        fi
        "${release_packages[@]}" --fhir-home "$FHIR_HOME" "${GUIDE_NAMES[@]}"
        ;;
    build|compare)
        # A package installed from a release carries a marker, so it is rebuilt rather than passed off as a build. A
        # comparison always builds afresh, since a package in place may predate edits to the guide sources; only the
        # workflow, whose packages come from this commit's build, declares them current.
        rebuild=false
        if [ "$GUIDE_SOURCE" = compare ] && [ "${GROVE_FHIR_GUIDES_CURRENT:-0}" != 1 ]; then
            rebuild=true
        fi
        for guide in "${GUIDE_NAMES[@]}"; do
            if [ ! -f "$GUIDES/$guide/output/package.tgz" ] || [ -e "$GUIDES/$guide/output/package.tgz.release" ]; then
                rebuild=true
            fi
        done
        if [ "$rebuild" = true ]; then
            echo "==> building ${GUIDE_NAMES[*]} implementation guides"
            (cd "$GUIDES" && npm ci && ./Scripts/build-guides.sh "${GUIDE_NAMES[@]}")
        fi
        if [ "$GUIDE_SOURCE" = compare ]; then
            echo "==> checking that the built ${GUIDE_NAMES[*]} packages match the grove-fhir $GROVE_FHIR_REF release"
            "${release_packages[@]}" --compare "${GUIDE_NAMES[@]}"
        fi
        ;;
    *)
        echo "error: GROVE_FHIR_GUIDE_SOURCE must be release, build, or compare, not '$GUIDE_SOURCE'" >&2
        exit 2
        ;;
esac
# The content corpus converts the HealthKit guide's generated examples, read from its built package.
if [ "$COMPONENT" = "healthkit" ]; then
    python3 Scripts/generate-grove-fhir-guide-example-fixtures.py --guides "$GUIDES" --check
fi

# The catalog's vector suites skip without a grove-fhir checkout, so they run here, the one place that has it. Every
# component runs them: which components a change selects says nothing about whether it touched the shared contract.
echo "==> checking the exchange protocol vectors"
./Scripts/run-package-tests.sh GroveFHIR macOS >/dev/null

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

echo "==> checking that the paired $COMPONENT guide examples are contained in Grove's output"
python3 Scripts/check-ig-example-containment.py --guides "$GUIDES" --component "$COMPONENT"

if [ "$COMPONENT" = "questionnaire" ]; then
    echo "==> validating the exact Questionnaire/Response pair"
    python3 "$GUIDES/Scripts/validate-questionnaire.py" \
        --questionnaire "$OUT/questionnaire.json" \
        --response "$OUT/questionnaire-response.json"
fi

echo "OK — all $COMPONENT resources conform to their declared R4 profiles."
