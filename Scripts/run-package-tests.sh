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

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.derivedData}"
enable_default_package_traits() {
  case "${SPEZI_ENABLE_DEFAULT_PACKAGE_TRAITS:-1}" in
    0|false|FALSE|no|NO)
      export SPEZI_ENABLE_DEFAULT_PACKAGE_TRAITS=0
      ;;
    *)
      export SPEZI_ENABLE_DEFAULT_PACKAGE_TRAITS=1
      ;;
  esac
}

default_package_traits_enabled() {
  case "${SPEZI_ENABLE_DEFAULT_PACKAGE_TRAITS:-1}" in
    0|false|FALSE|no|NO) return 1 ;;
    *) return 0 ;;
  esac
}

current_deployment_target() { case "$1" in
  iOS|iPadOS|macCatalyst) echo "18.0" ;;
  macOS) echo "15.0" ;;
  watchOS) echo "11.0" ;;
  tvOS) echo "18.0" ;;
  visionOS) echo "2.0" ;;
  *) echo "" ;;
esac; }

deployment_target_build_setting() {
  local platform="$1"
  local deployment_target="$2"

  if [ -z "$deployment_target" ]; then
    return
  fi

  case "$platform" in
    iOS|iPadOS|macCatalyst) echo "IPHONEOS_DEPLOYMENT_TARGET=$deployment_target" ;;
    macOS) echo "MACOSX_DEPLOYMENT_TARGET=$deployment_target" ;;
    watchOS) echo "WATCHOS_DEPLOYMENT_TARGET=$deployment_target" ;;
    tvOS) echo "TVOS_DEPLOYMENT_TARGET=$deployment_target" ;;
    visionOS) echo "XROS_DEPLOYMENT_TARGET=$deployment_target" ;;
  esac
}

ci_deployment_target_argument() {
  if default_package_traits_enabled; then
    deployment_target_build_setting "$1" "$(current_deployment_target "$1")"
  fi
  return 0
}

cleanup_derived_data() {
  case "${CLEAN_DERIVED_DATA:-}" in
    0|false|FALSE|no|NO)
      return
      ;;
  esac

  case "$DERIVED_DATA_PATH" in
    .derivedData|.derivedData/*|.derivedData-*|"$PWD"/.derivedData|"$PWD"/.derivedData/*|"$PWD"/.derivedData-*)
      rm -rf "$DERIVED_DATA_PATH"
      ;;
  esac
}
if [ "${CLEAN_DERIVED_DATA:-1}" != "0" ]; then
  trap cleanup_derived_data EXIT
fi

PACKAGES="FHIRModelsExtensions HealthKitOnFHIR ResearchKitOnFHIR Spezi SpeziAccessGuard SpeziAccount SpeziBluetooth SpeziChat SpeziConsent SpeziContact SpeziDevices SpeziFHIR SpeziFileFormats SpeziFirebase ThreadLocal SpeziFoundation SpeziHealthKit SpeziLLM SpeziLicense SpeziLocation SpeziNetworking SpeziNotifications SpeziOnboarding SpeziQuestionnaire SpeziScheduler SpeziSensorKit SpeziSpeech SpeziStorage SpeziStudy SpeziViews XCTHealthKit XCTRuntimeAssertions XCTestExtensions"

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
    ThreadLocal) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
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
    XCTHealthKit) echo "iOS" ;;
    XCTRuntimeAssertions) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
    XCTestExtensions) echo "iOS watchOS visionOS macOS" ;;
    *) echo "" ;;
  esac; }

simulator_os() {
  local runtime_identifier="$1"
  local major_version="$2"
  local override_variable="$3"
  local override_value="${!override_variable:-}"

  if [ -n "$override_value" ]; then
    echo "$override_value"
    return
  fi

  xcrun simctl list runtimes --json | python3 -c '
import json
import sys

runtime_identifier = sys.argv[1]
major_version = sys.argv[2]
data = json.load(sys.stdin)

def version_key(runtime):
    return tuple(int(part) for part in runtime["version"].split("."))

runtimes = [
    runtime
    for runtime in data.get("runtimes", [])
    if runtime.get("isAvailable", True)
    and runtime.get("identifier", "").startswith(runtime_identifier)
    and runtime.get("version", "").split(".", maxsplit=1)[0] == major_version
]

if not runtimes:
    raise SystemExit(f"No available {runtime_identifier} {major_version}.x simulator runtime found.")

print(max(runtimes, key=version_key)["version"])
' "$runtime_identifier" "$major_version"
}

ios_simulator_os() {
  simulator_os "com.apple.CoreSimulator.SimRuntime.iOS" "${IOS_SIMULATOR_MAJOR:-26}" "IOS_SIMULATOR_OS"
}

watchos_simulator_os() {
  simulator_os "com.apple.CoreSimulator.SimRuntime.watchOS" "${WATCHOS_SIMULATOR_MAJOR:-26}" "WATCHOS_SIMULATOR_OS"
}

tvos_simulator_os() {
  simulator_os "com.apple.CoreSimulator.SimRuntime.tvOS" "${TVOS_SIMULATOR_MAJOR:-26}" "TVOS_SIMULATOR_OS"
}

visionos_simulator_os() {
  simulator_os "com.apple.CoreSimulator.SimRuntime.xrOS" "${VISIONOS_SIMULATOR_MAJOR:-26}" "VISIONOS_SIMULATOR_OS"
}

absolute_path() {
  case "$1" in
    /*) echo "$1" ;;
    *) echo "$(pwd)/$1" ;;
  esac
}

ui_test_deployment_target() { case "$1" in
  ResearchKitOnFHIR|SpeziLLM|SpeziQuestionnaire) echo "18.0" ;;
  *) echo "" ;;
esac; }

ui_deployment_target_argument() {
  local package="$1"
  local platform="$2"
  local deployment_target; deployment_target="$(ui_test_deployment_target "$package")"

  if [ -z "$deployment_target" ] && default_package_traits_enabled; then
    deployment_target="$(current_deployment_target "$platform")"
  fi

  deployment_target_build_setting "$platform" "$deployment_target"
}

dest() { case "$1" in
  iOS)          echo "platform=iOS Simulator,name=iPhone 17 Pro,OS=$(ios_simulator_os)" ;;
  iPadOS)       echo "platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=$(ios_simulator_os)" ;;
  macOS)        echo "platform=macOS,arch=arm64" ;;
  macCatalyst)  echo "platform=macOS,arch=arm64,variant=Mac Catalyst" ;;
  watchOS)      echo "platform=watchOS Simulator,name=Apple Watch Series 11 (42mm),OS=$(watchos_simulator_os)" ;;
  visionOS)     echo "platform=visionOS Simulator,name=Apple Vision Pro,OS=$(visionos_simulator_os)" ;;
  tvOS)         echo "platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=$(tvos_simulator_os)" ;;
  *) echo "unknown platform: $1" >&2; exit 2 ;;
esac; }

# Pretty-print xcodebuild output via xcbeautify; emit GitHub annotations when running in CI.
beautify() { if [ -n "${GITHUB_ACTIONS:-}" ]; then xcbeautify --renderer github-actions; else xcbeautify; fi; }

run() { # <package> <platform> [mode: "ui"]
  if [ "${3:-}" = "ui" ]; then
    enable_default_package_traits
    # UI tests: build+run the package's embedded TestApp (Tests/<Pkg>Tests/UITests/UITests.xcodeproj),
    # scheme "TestApp", on the platform's destination. Debug only for now (Release is a later add).
    # Writes an .xcresult bundle that the test-ui CI job uploads as an artifact (even on test failure).
    local result="${1}-${2}-UITests.xcresult"
    local uidir="Tests/${1}Tests/UITests"
    local deployment_target_argument; deployment_target_argument="$(ui_deployment_target_argument "$1" "$2")"
    local root; root="$(pwd)"
    local derived_data_path_absolute; derived_data_path_absolute="$(absolute_path "$DERIVED_DATA_PATH")"
    rm -rf "$result"   # self-hosted runners reuse the workspace — avoid a stale bundle path
    echo "==> $1 UI tests on $2"
    if [ -f "$uidir/firebase.json" ]; then
      # This package's UITests need the Firebase emulator (e.g. SpeziFirebase). Run the test inside
      # `firebase emulators:exec` from the UITests dir (so firebase.json/.firebaserc/rules resolve),
      # writing the .xcresult back to the repo root (absolute path) so the test-ui upload step finds it.
      # Requires the `firebase` CLI (firebase-tools) on the runner — as the upstream CI also relied on.
      ( cd "$uidir" \
        && firebase emulators:exec "xcodebuild test -project UITests.xcodeproj -scheme TestApp -configuration Debug -destination '$(dest "$2")' -resultBundlePath '$root/$result' -derivedDataPath '$derived_data_path_absolute' -skipMacroValidation -skipPackagePluginValidation -skipPackageUpdates${deployment_target_argument:+ $deployment_target_argument}" ) \
      | beautify
      return
    fi

    local xcodebuild_arguments=(
      test
      -project "$uidir/UITests.xcodeproj"
      -scheme TestApp
      -configuration Debug
      -destination "$(dest "$2")"
      -resultBundlePath "$result"
      -skipMacroValidation
      -skipPackagePluginValidation
      -skipPackageUpdates
      -derivedDataPath "$derived_data_path_absolute"
    )
    if [ -n "$deployment_target_argument" ]; then
      xcodebuild_arguments+=("$deployment_target_argument")
    fi
    xcodebuild "${xcodebuild_arguments[@]}" | beautify
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
  enable_default_package_traits
  # Writes an .xcresult bundle that the `test` CI job uploads as an artifact on failure.
  local result="${1}-${2}-Tests.xcresult"
  local deployment_target_argument; deployment_target_argument="$(ci_deployment_target_argument "$2")"
  rm -rf "$result"
  local xcodebuild_arguments=(
    test
    -scheme Spezi-Tests
    -testPlan "$1"
    -destination "$(dest "$2")"
    -resultBundlePath "$result"
    -skipMacroValidation
    -skipPackagePluginValidation
    -skipPackageUpdates
    -derivedDataPath "$DERIVED_DATA_PATH"
  )
  if [ -n "$deployment_target_argument" ]; then
    xcodebuild_arguments+=("$deployment_target_argument")
  fi
  xcodebuild "${xcodebuild_arguments[@]}" | beautify
}

case "${1:-}" in
  --list)
    for p in $PACKAGES; do printf '%-24s %s\n' "$p" "$(platforms_for "$p")"; done ;;
  --all-ios)
    echo "==> entire package on iOS Simulator"
    enable_default_package_traits
    all_ios_arguments=(
      test
      -scheme Spezi-Package
      -destination "$(dest iOS)"
      -skipMacroValidation
      -skipPackagePluginValidation
      -skipPackageUpdates
      -derivedDataPath "$DERIVED_DATA_PATH"
    )
    deployment_target_argument="$(ci_deployment_target_argument iOS)"
    if [ -n "$deployment_target_argument" ]; then
      all_ios_arguments+=("$deployment_target_argument")
    fi
    xcodebuild "${all_ios_arguments[@]}" | beautify ;;
  "")
    echo "usage: $0 <Package> [Platform] [ui] | --all-ios | --list" >&2; exit 1 ;;
  *)
    PKG="$1"
    PLATS="$(platforms_for "$PKG")"
    [ -n "$PLATS" ] || { echo "unknown package: $PKG (see --list)" >&2; exit 1; }
    if [ "${2:-}" ]; then run "$PKG" "$2" "${3:-}"
    else for plat in $PLATS; do run "$PKG" "$plat"; done; fi ;;
esac
