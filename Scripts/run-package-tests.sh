#!/usr/bin/env bash
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
# Reproduces the union CI testing matrix of the original input packages using Xcode test plans.
# Each former package has a test plan under Tests/TestPlans/<Package>.xctestplan, all hosted by the
# single "Grove-Tests" scheme. This script runs a given package's tests on a given platform (or on
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

# Log the toolchain environment, so CI logs carry the context needed to interpret and reproduce a run.
# Must stay OS-agnostic: the Linux legs run this script too, and under `set -e` a missing
# macOS-only tool would abort the run before any test starts.
echo "==> environment"
if [ "$(uname -s)" = "Darwin" ]; then
  sw_vers
  xcodebuild -version
else
  uname -srm
  # PRETTY_NAME identifies the distro + version on any systemd-era Linux.
  grep PRETTY_NAME /etc/os-release || true
fi
swift --version

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
export GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS=1

# DocC catalogs are never needed to compile or run the tests. Excluding them from the test build
# (the manifest's targetExcludes() honors this flag) avoids unnecessary work; doc builds set it to 0
# so DocC can still resolve their articles and assets. (`.license` files are excluded unconditionally
# by the manifest to suppress SwiftPM unhandled-file warnings, independent of this flag.)
export GROVE_EXCLUDE_DOCC_CATALOGS="${GROVE_EXCLUDE_DOCC_CATALOGS:-1}"

# Keep Xcode's high-churn build output outside the package checkout in CI. Xcode 26 can otherwise
# observe its own DerivedData/result writes as package-graph changes and invalidate a running test bundle.
DERIVED_DATA_PATH="${RUNNER_TEMP:+$RUNNER_TEMP/grove}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/.derivedData}"

# One bare-repo cache shared by every leg, deliberately outside DERIVED_DATA_PATH so cleaning build
# output does not force a re-clone. Safe to share: keyed by repository URL and only appended to.
PACKAGE_CACHE_PATH="${PACKAGE_CACHE_PATH:-${RUNNER_TEMP:-$PWD}/.packageCache}"
mkdir -p "$PACKAGE_CACHE_PATH"

PACKAGES="FHIRModelsExtensions ResearchKitOnFHIR Grove GroveAccessGuard GroveAccount GroveBluetooth GroveChat GroveConsent GroveContact GroveDevices GroveFHIR GroveFileFormats GroveFirebase GroveFoundation GroveHealthKit GroveHealthKitFHIR GroveLLM GroveLicense GroveLocation GroveNetworking GroveNotifications GroveOnboarding GroveQuestionnaire GroveScheduler GroveSensorKit GroveSensorKitFHIR GroveSpeech GroveStorage GroveStudy GroveViews ThreadLocal XCTHealthKit RuntimeAssertions XCTestExtensions"

test_targets_for() {
  python3 - "$1" "$2" <<'PY'
import sys
import tomllib

package, platform = sys.argv[1:]
config = tomllib.load(open("packages.toml", "rb"))[package]
platforms_by_target = config.get("testPlatforms", {})
targets = config.get("linuxTargets") if platform == "Linux" else None
print(" ".join(
    target
    for target in targets or config["tests"]
    if platform in platforms_by_target.get(target, [platform])
))
PY
}

# package -> the platforms it was tested on upstream (the union CI matrix)
platforms_for() { case "$1" in
    FHIRModelsExtensions) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
    ResearchKitOnFHIR) echo "iOS" ;;
    Grove) echo "iOS visionOS macOS tvOS watchOS macCatalyst" ;;
    GroveAccessGuard) echo "iOS" ;;
    GroveAccount) echo "macOS" ;;
    GroveBluetooth) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
    GroveChat) echo "iOS macOS visionOS" ;;
    GroveConsent) echo "iOS macOS visionOS" ;;
    GroveContact) echo "iOS" ;;
    GroveDevices) echo "iOS macOS macCatalyst visionOS" ;;
    GroveFHIR) echo "iOS macOS" ;;
    GroveFileFormats) echo "iOS watchOS visionOS tvOS macOS" ;;
    GroveFirebase) echo "iOS" ;;
    GroveFoundation) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
    GroveHealthKit) echo "iOS watchOS macOS macCatalyst visionOS" ;;
    GroveHealthKitFHIR) echo "iOS macOS watchOS" ;;
    GroveLLM) echo "iOS visionOS macOS" ;;
    GroveLicense) echo "iOS" ;;
    GroveLocation) echo "iOS watchOS" ;;
    GroveNetworking) echo "iOS watchOS visionOS tvOS macOS" ;;
    GroveNotifications) echo "iOS macOS watchOS visionOS tvOS" ;;
    GroveOnboarding) echo "iOS macOS visionOS" ;;
    GroveQuestionnaire) echo "iOS macOS" ;;
    GroveScheduler) echo "iOS macOS visionOS watchOS" ;;
    GroveSensorKit) echo "iOS" ;;
    GroveSensorKitFHIR) echo "iOS macOS" ;;
    GroveSpeech) echo "iOS visionOS macOS" ;;
    GroveStorage) echo "iOS macOS macCatalyst watchOS visionOS" ;;
    GroveStudy) echo "iOS macOS macCatalyst watchOS visionOS" ;;
    GroveViews) echo "iOS visionOS tvOS watchOS macOS" ;;
    ThreadLocal) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
    XCTHealthKit) echo "iOS" ;;
    RuntimeAssertions) echo "iOS macOS macCatalyst watchOS visionOS tvOS" ;;
    XCTestExtensions) echo "iOS watchOS visionOS macOS" ;;
    *) echo "" ;;
  esac; }

dest() { case "$1" in
  iOS)          echo "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" ;;
  iPadOS)       echo "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" ;;
  macOS)        echo "platform=macOS,arch=arm64" ;;
  macCatalyst)  echo "platform=macOS,arch=arm64,variant=Mac Catalyst" ;;
  watchOS)      echo "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" ;;
  visionOS)     echo "platform=visionOS Simulator,name=Apple Vision Pro" ;;
  tvOS)         echo "platform=tvOS Simulator,name=Apple TV 4K (3rd generation)" ;;
  *) echo "unknown platform: $1" >&2; exit 2 ;;
esac; }

# Pretty-print xcodebuild output via xcbeautify; emit GitHub annotations when running in CI.
beautify() { if [ -n "${GITHUB_ACTIONS:-}" ]; then xcbeautify --renderer github-actions; else xcbeautify; fi; }

# HealthKit and keychain state lives in the device container, not the app's, so uninstalling the test
# apps leaves it behind and every leg inherits what the previous ones wrote. Erase the device instead.
# Set GROVE_SKIP_SIM_RESET to keep a leg running against the current simulator state.
reset_simulator() { # <platform>
  local name os udid
  case "$1" in iOS|iPadOS) ;; *) return 0 ;; esac
  [ -z "${GROVE_SKIP_SIM_RESET:-}" ] || return 0
  name="$(dest "$1" | sed -n 's/.*name=\([^,]*\).*/\1/p')"
  os="$(dest "$1" | sed -n 's/.*OS=\([0-9.]*\).*/\1/p')"
  udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
want_name = sys.argv[1]; want_os = sys.argv[2]
for rt, devs in json.load(sys.stdin)["devices"].items():
    if want_os and want_os.replace(".", "-") not in rt:
        continue
    for d in devs:
        if d["name"] == want_name:
            print(d["udid"]); sys.exit(0)
' "$name" "$os")"
  [ -n "$udid" ] || return 0
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  if ! xcrun simctl erase "$udid"; then
    echo "::warning::could not erase $udid; leg runs against inherited simulator state"
  fi
  xcrun simctl bootstatus "$udid" -b
  return 0
}

run() { # <package> <platform> [mode: "ui"]
  if [ "${3:-}" = "ui" ]; then
    # UI tests: build+run the package's embedded TestApp (Tests/<Pkg>Tests/UITests/UITests.xcodeproj),
    # scheme "TestApp", on the platform's destination. Debug only for now (Release is a later add).
    # Writes an .xcresult bundle that the test-ui CI job uploads as an artifact (even on test failure).
    local result="${1}-${2}-UITests.xcresult"
    local uidir="Tests/${1}Tests/UITests"
    rm -rf "$result"   # self-hosted runners reuse the workspace — avoid a stale bundle path
    reset_simulator "$2"
    echo "==> $1 UI tests on $2"
    if [ -f "$uidir/firebase.json" ]; then
      # This package's UITests need the Firebase emulator (e.g. GroveFirebase). Run the test inside
      # `firebase emulators:exec` from the UITests dir (so firebase.json/.firebaserc/rules resolve),
      # writing the .xcresult back to the repo root (absolute path) so the test-ui upload step finds it.
      # Requires the `firebase` CLI (firebase-tools) on the runner — as the upstream CI also relied on.
      local root; root="$(pwd)"
      ( cd "$uidir" \
        && firebase emulators:exec "xcodebuild test -project UITests.xcodeproj -scheme TestApp -configuration Debug -destination '$(dest "$2")' -parallel-testing-enabled NO -resultBundlePath '$root/$result' -derivedDataPath '$DERIVED_DATA_PATH' -skipMacroValidation -skipPackagePluginValidation $TESTING_FLOOR_DEPLOYMENT_TARGETS" ) \
      | beautify
      return
    fi
    xcodebuild test \
      -project "$uidir/UITests.xcodeproj" \
      -scheme TestApp \
      -configuration Debug \
      -destination "$(dest "$2")" \
      -parallel-testing-enabled "${UI_PARALLEL:-NO}" \
      -maximum-concurrent-test-simulator-destinations "${UI_WORKERS:-4}" \
      -resultBundlePath "$result" \
      -skipMacroValidation \
      -skipPackagePluginValidation \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -packageCachePath "$PACKAGE_CACHE_PATH" \
      $TESTING_FLOOR_DEPLOYMENT_TARGETS \
    | beautify
    return
  fi
  if [ "$2" = "Linux" ]; then
    # Linux has no Xcode test plans, and `swift test` compiles the WHOLE monorepo package (every target
    # AND every library product) before running — most of the monorepo is Apple-only and can't build on
    # Linux, so a combined test build fails before any test runs. Actually RUNNING a single sub-package's
    # tests on Linux needs more work (tracked separately); for now, compile-check each of the package's
    # test targets (scoped via --target, which SwiftPM resolves natively) to verify they still build.
    # A package whose test target is itself Apple-only names the source targets to check via
    # `linuxTargets` instead.
    local tts
    tts="$(test_targets_for "$1" "$2")"
    for tt in $tts; do
      echo "==> $1 on Linux: swift build --target $tt (compile-check)"
      swift build --target "$tt"
    done
    return
  fi
  reset_simulator "$2"
  echo "==> $1 on $2"
  # Xcode 26 SIGABRTs (exit 134, DVTInvalidation "message sent to invalidated object") when a single
  # `xcodebuild test` launches a SECOND .xctest bundle: in-checkout writes during the run (DerivedData,
  # the .xcresult, and Xcode's own .swiftpm user-state/scheme files) make Xcode re-resolve the package
  # graph mid-action, which invalidates the test-bundle blueprints; messaging the next bundle's blueprint
  # then crashes. So we run EACH test target in its OWN invocation via -only-testing:, so only one bundle
  # is ever launched per process (a single-target package is simply a one-iteration loop). The build is
  # shared through the common -derivedDataPath, so later targets reuse the first's build, and the per-bundle
  # .xcresults are collapsed into one <Package>-<Platform>-Tests.xcresult so the output matches a plain run.
  # The test-target list is the curated mapping in packages.toml — the same source the xctestplans are
  # generated from (and that the Linux path above uses) — not a re-parse of the generated test plan.
  local targets rc=0
  targets="$(test_targets_for "$1" "$2")"
  local result="${1}-${2}-Tests.xcresult"
  local parts=()
  for tt in $targets; do
    echo "==> $1 on $2: test bundle $tt"
    local part="${1}-${2}-${tt}.xcresult"
    local part_path="$part"
    if [ -n "${RUNNER_TEMP:-}" ]; then
      part_path="$RUNNER_TEMP/$part"
    fi
    rm -rf "$part" "$part_path"
    xcodebuild test \
      -scheme Grove-Tests \
      -testPlan "$1" \
      -only-testing:"$tt" \
      -destination "$(dest "$2")" \
      -resultBundlePath "$part_path" \
      -skipMacroValidation \
      -skipPackagePluginValidation \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -packageCachePath "$PACKAGE_CACHE_PATH" \
      $TESTING_FLOOR_DEPLOYMENT_TARGETS \
    | beautify || rc=1
    if [ -d "$part_path" ]; then
      if [ "$part_path" != "$part" ]; then mv "$part_path" "$part"; fi
      parts+=("$part")
    fi
  done
  # Collapse the per-bundle .xcresults into the single <Package>-<Platform>-Tests.xcresult the CI uploads,
  # so the artifact is shaped identically regardless of how many bundles ran. (merge needs >=2 inputs; a
  # single bundle is just renamed.)
  rm -rf "$result"
  if [ "${#parts[@]}" -ge 2 ]; then
    if xcrun xcresulttool merge "${parts[@]}" --output-path "$result"; then
      rm -rf "${parts[@]}"
    else
      echo "::warning::xcresulttool merge failed for $1/$2; leaving per-bundle .xcresults in place"
    fi
  elif [ "${#parts[@]}" -eq 1 ]; then
    mv "${parts[0]}" "$result"
  fi
  return "$rc"
}

case "${1:-}" in
  --list)
    for p in $PACKAGES; do printf '%-24s %s\n' "$p" "$(platforms_for "$p")"; done ;;
  --all-ios)
    echo "==> entire package on iOS Simulator"
    xcodebuild test -scheme Grove-Package -destination "$(dest iOS)" \
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
