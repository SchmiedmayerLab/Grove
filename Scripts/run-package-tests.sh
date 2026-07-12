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
    # Linux has no Xcode test plans, and `swift test` compiles the WHOLE package (every target + product) —
    # most of the monorepo is Apple-only and can't build on Linux, so an unscoped `swift test` fails before
    # any test runs. Compute the transitive TARGET closure of this sub-package's tests from the manifest's
    # dependency graph (rooted at packages.toml's `tests`), and hand it to the manifest via
    # SPEZI_LINUX_TEST_KEEP; Package.swift's `#if os(Linux)` then keeps only those targets, so `swift test`
    # builds and RUNS exactly this package's tests. The keep-set is derived, never hardcoded. (dump-package
    # must run with SPEZI_LINUX_TEST_KEEP unset so it reports the full graph — hence compute it first.)
    local tts keep
    tts="$(python3 -c "import tomllib; print(' '.join(tomllib.load(open('packages.toml','rb'))['$1']['tests']))")"
    keep="$(swift package dump-package | python3 -c '
import json, sys, tomllib
targets = {t["name"]: t for t in json.load(sys.stdin)["targets"]}
def deps(t):
    out = set()
    for dep in targets[t].get("dependencies", []):
        for key in ("byName", "target"):
            v = dep.get(key)
            if v and v[0] in targets:
                # Honor `.when(platforms:)`: a Linux `dump-package` still lists such edges, tagged
                # with platformNames — skip the ones that exclude Linux, exactly as SwiftPM would.
                # (`#if canImport(Darwin)` edges are already absent from a Linux dump, so no handling needed.)
                cond = v[1]
                if cond and "linux" not in cond.get("platformNames", []):
                    continue
                out.add(v[0])
    return out
seen, stack = set(), list(tomllib.load(open("packages.toml", "rb"))[sys.argv[1]]["tests"])
while stack:
    n = stack.pop()
    if n in seen or n not in targets: continue
    seen.add(n); stack += deps(n)
print(",".join(sorted(seen)))
' "$1")"
    echo "==> $1 on Linux: swift test (keep=$keep)"
    local filters=()
    for tt in $tts; do filters+=(--filter "$tt"); done
    # Set the keep-set inline (not `export`) so it applies only to this `swift test` — the `dump-package`
    # above must see the FULL graph, and a persistent export could leak into a later package's run.
    SPEZI_LINUX_TEST_KEEP="$keep" swift test "${filters[@]}"
    return
  fi
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
  targets="$(python3 -c "import tomllib; print(' '.join(tomllib.load(open('packages.toml','rb'))['$1']['tests']))")"
  local result="${1}-${2}-Tests.xcresult"
  local parts=()
  for tt in $targets; do
    echo "==> $1 on $2: test bundle $tt"
    local part="${1}-${2}-${tt}.xcresult"
    rm -rf "$part"
    xcodebuild test \
      -scheme Spezi-Tests \
      -testPlan "$1" \
      -only-testing:"$tt" \
      -destination "$(dest "$2")" \
      -resultBundlePath "$part" \
      -skipMacroValidation \
      -skipPackagePluginValidation \
      -derivedDataPath ".derivedData" \
      $TESTING_FLOOR_DEPLOYMENT_TARGETS \
    | beautify || rc=1
    if [ -d "$part" ]; then parts+=("$part"); fi
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
