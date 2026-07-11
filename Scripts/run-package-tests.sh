#!/usr/bin/env bash
#
# This source file is part of the Stanford Spezi open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
# Reproduces the union CI testing matrix of the original input packages using Xcode test plans.
# Each former package has a test plan under Tests/TestPlans/<Package>.xctestplan, all hosted by the
# single "Spezi-Tests" scheme. This script runs a given package's tests on a given platform (or on
# every platform that package was tested on upstream), or runs the whole suite on iOS.
#
# Usage:
#   Scripts/run-package-tests.sh <Package> [Platform]   # one package on one platform (default: all its platforms)
#   Scripts/run-package-tests.sh --all-ios              # the entire package's tests on the iOS Simulator
#   Scripts/run-package-tests.sh --list                 # print the package -> platforms matrix
#
# Platforms: iOS macOS macCatalyst watchOS visionOS tvOS
set -euxo pipefail
cd "$(dirname "$0")/.."

# The package's deployment floor is iOS 15 (so iOS-15 apps can depend on it), but the TEST targets
# cannot compile at iOS 15: swift-testing's @Suite macro rejects an @available attribute, and the test
# fixtures use newer APIs held as stored properties (which can't be gated). Tests only ever run on the
# current-OS-wave simulators (OS 26), so we build them at that deployment target — every API is then
# available, so no test needs an availability annotation. The library products' iOS-15 compilation is
# verified by the regular (non-test) package build, not here. Each override only affects the matching
# platform's build, so passing all of them to every invocation is safe.
TESTING_FLOOR_DEPLOYMENT_TARGETS="IPHONEOS_DEPLOYMENT_TARGET=26.0 MACOSX_DEPLOYMENT_TARGET=26.0 WATCHOS_DEPLOYMENT_TARGET=26.0 TVOS_DEPLOYMENT_TARGET=26.0 XROS_DEPLOYMENT_TARGET=26.0"

# The optional integrations (Textual, MLX, ResearchKit) are behind default-off package traits so that
# an iOS-15 consumer's default graph stays lean. Tests exercise the FULL feature set, so enable all
# traits for the test build (the manifest reads this env var; per-platform `.when(platforms:)`
# conditions still keep watchOS-/macOS-incompatible deps out of those platforms' graphs).
export SPEZI_ENABLE_DEFAULT_PACKAGE_TRAITS=1

PACKAGES="FHIRModelsExtensions HealthKitOnFHIR ResearchKitOnFHIR Spezi SpeziAccessGuard SpeziAccount SpeziBluetooth SpeziChat SpeziConsent SpeziContact SpeziDevices SpeziFHIR SpeziFileFormats SpeziFirebase SpeziFoundation SpeziHealthKit SpeziLLM SpeziLicense SpeziLocation SpeziNetworking SpeziNotifications SpeziOnboarding SpeziQuestionnaire SpeziScheduler SpeziSensorKit SpeziSpeech SpeziStorage SpeziStudy SpeziViews ThreadLocal XCTHealthKit XCTRuntimeAssertions XCTestExtensions"

# package -> the platforms it was tested on upstream (the union CI matrix)
platforms_for() { case "$1" in
    FHIRModelsExtensions) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
    HealthKitOnFHIR) echo "iOS macOS watchOS" ;;
    ResearchKitOnFHIR) echo "iOS" ;;
    Spezi) echo "iOS visionOS macOS tvOS watchOS macCatalyst" ;;
    SpeziAccessGuard) echo "iOS" ;;
    SpeziAccount) echo "macOS" ;;
    SpeziBluetooth) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
    SpeziChat) echo "iOS macOS visionOS" ;;
    SpeziConsent) echo "iOS macOS visionOS" ;;
    SpeziContact) echo "iOS" ;;
    SpeziDevices) echo "iOS macOS macCatalyst visionOS" ;;
    SpeziFHIR) echo "iOS" ;;
    SpeziFileFormats) echo "iOS watchOS visionOS tvOS macOS" ;;
    SpeziFirebase) echo "iOS" ;;
    SpeziFoundation) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
    SpeziHealthKit) echo "iOS watchOS macOS macCatalyst visionOS" ;;
    SpeziLLM) echo "iOS visionOS macOS" ;;
    SpeziLicense) echo "iOS" ;;
    SpeziLocation) echo "iOS watchOS" ;;
    SpeziNetworking) echo "iOS watchOS visionOS tvOS macOS" ;;
    SpeziNotifications) echo "iOS macOS watchOS visionOS tvOS" ;;
    SpeziOnboarding) echo "iOS macOS visionOS" ;;
    SpeziQuestionnaire) echo "iOS" ;;
    SpeziScheduler) echo "iOS macOS visionOS watchOS" ;;
    SpeziSensorKit) echo "iOS" ;;
    SpeziSpeech) echo "iOS visionOS macOS" ;;
    SpeziStorage) echo "iOS macOS macCatalyst watchOS visionOS" ;;
    SpeziStudy) echo "iOS macOS macCatalyst watchOS visionOS" ;;
    SpeziViews) echo "iOS visionOS tvOS watchOS macOS" ;;
    ThreadLocal) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
    XCTHealthKit) echo "iOS" ;;
    XCTRuntimeAssertions) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
    XCTestExtensions) echo "iOS watchOS visionOS macOS" ;;
    *) echo "" ;;
  esac; }

dest() { case "$1" in
  iOS)          echo "platform=iOS Simulator,name=iPhone 17 Pro" ;;
  iPadOS)       echo "platform=iOS Simulator,name=iPad Pro 13-inch (M4)" ;;
  macOS)        echo "platform=macOS,arch=arm64" ;;
  macCatalyst)  echo "platform=macOS,arch=arm64,variant=Mac Catalyst" ;;
  watchOS)      echo "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" ;;
  visionOS)     echo "platform=visionOS Simulator,name=Apple Vision Pro" ;;
  tvOS)         echo "platform=tvOS Simulator,name=Apple TV 4K (3rd generation)" ;;
  *) echo "unknown platform: $1" >&2; exit 2 ;;
esac; }

# Pretty-print xcodebuild output via xcbeautify; emit GitHub annotations when running in CI.
beautify() { if [ -n "${GITHUB_ACTIONS:-}" ]; then xcbeautify --renderer github-actions; else xcbeautify; fi; }

run() { # <package> <platform> [mode: "ui"]
  if [ "${3:-}" = "ui" ]; then
    # UI tests: build+run the package's embedded TestApp (Tests/<Pkg>Tests/UITests/UITests.xcodeproj),
    # scheme "TestApp", on the platform's destination. Debug only for now (Release is a later add).
    # Writes an .xcresult bundle that the test-ui CI job uploads as an artifact (even on test failure).
    local result="${1}-${2}-UITests.xcresult"
    local uidir="Tests/${1}Tests/UITests"
    rm -rf "$result"   # self-hosted runners reuse the workspace — avoid a stale bundle path
    echo "==> $1 UI tests on $2"
    if [ -f "$uidir/firebase.json" ]; then
      # This package's UITests need the Firebase emulator (e.g. SpeziFirebase). Run the test inside
      # `firebase emulators:exec` from the UITests dir (so firebase.json/.firebaserc/rules resolve),
      # writing the .xcresult back to the repo root (absolute path) so the test-ui upload step finds it.
      # Requires the `firebase` CLI (firebase-tools) on the runner — as the upstream CI also relied on.
      local root; root="$(pwd)"
      ( cd "$uidir" \
        && firebase emulators:exec "xcodebuild test -project UITests.xcodeproj -scheme TestApp -configuration Debug -destination '$(dest "$2")' -resultBundlePath '$root/$result' -derivedDataPath '$root/.derivedData' -skipMacroValidation -skipPackagePluginValidation $TESTING_FLOOR_DEPLOYMENT_TARGETS" ) \
      | beautify
      return
    fi
    xcodebuild test \
      -project "$uidir/UITests.xcodeproj" \
      -scheme TestApp \
      -configuration Debug \
      -destination "$(dest "$2")" \
      -resultBundlePath "$result" \
      -skipMacroValidation \
      -skipPackagePluginValidation \
      -derivedDataPath ".derivedData" \
      $TESTING_FLOOR_DEPLOYMENT_TARGETS \
    | beautify
    return
  fi
  if [ "$2" = "Linux" ]; then
    # Linux has no Xcode test plans, and SwiftPM builds ONE combined <Package>PackageTests.xctest
    # per package (so a subset can't be run). Instead compile-check each of the package's test
    # targets (scoped via --target) on GitHub-hosted Linux — verifies the package still builds there.
    local tts
    tts="$(python3 -c "import tomllib; print(' '.join(tomllib.load(open('packages.toml','rb'))['$1']['tests']))")"
    for tt in $tts; do
      echo "==> $1 on Linux: swift build --target $tt (compile-check)"
      swift build --target "$tt"
    done
    return
  fi
  echo "==> $1 on $2"
  # Writes an .xcresult bundle that the `test` CI job uploads as an artifact on failure.
  local result="${1}-${2}-Tests.xcresult"
  rm -rf "$result"
  xcodebuild test \
    -scheme Spezi-Tests \
    -testPlan "$1" \
    -destination "$(dest "$2")" \
    -resultBundlePath "$result" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    -derivedDataPath ".derivedData" \
    $TESTING_FLOOR_DEPLOYMENT_TARGETS \
  | beautify
}

case "${1:-}" in
  --list)
    for p in $PACKAGES; do printf '%-24s %s\n' "$p" "$(platforms_for "$p")"; done ;;
  --all-ios)
    echo "==> entire package on iOS Simulator"
    xcodebuild test -scheme Spezi-Package -destination "$(dest iOS)" \
      -skipMacroValidation -skipPackagePluginValidation $TESTING_FLOOR_DEPLOYMENT_TARGETS | beautify ;;
  "")
    echo "usage: $0 <Package> [Platform] [ui] | --all-ios | --list" >&2; exit 1 ;;
  *)
    PKG="$1"
    PLATS="$(platforms_for "$PKG")"
    [ -n "$PLATS" ] || { echo "unknown package: $PKG (see --list)" >&2; exit 1; }
    if [ "${2:-}" ]; then run "$PKG" "$2" "${3:-}"
    else for plat in $PLATS; do run "$PKG" "$plat"; done; fi ;;
esac
