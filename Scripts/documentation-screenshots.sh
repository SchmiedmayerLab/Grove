#!/bin/zsh
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
# Regenerates the documentation screenshots of one or more targets.
#
# Every UI test bundle that documents its target carries a `DocumentationScreenshots` test. It walks the test app
# and prints `CAPTURE <Name>` at each state worth showing; this script runs it, in light and dark appearance, and
# shoots the simulator through RocketSim whenever a marker appears. The walk skips itself in a regular test run;
# only this script sets `GROVE_DOCUMENTATION_SCREENSHOTS` for the test runner. The capture lands in the target's DocC
# resources as `<Name>.png` and `<Name>~dark.png`, framed by a device bezel on a transparent background.
#
# Requirements: Xcode with an iOS simulator runtime, and RocketSim (https://www.rocketsim.app) running with its
# command line tool installed. The status bar is set to 9:41 with a full battery for every capture. With pngquant
# installed (`brew install pngquant`), every capture is reduced to a 256-color palette, which keeps the full
# resolution and takes a picture from roughly 800 KB to under 200 KB without a visible difference at the size the
# documentation shows it.
#
# Usage:
#   Scripts/documentation-screenshots.sh [--parallel N] [--device "iPhone 17 Pro"] [--keep-simulators] [Target ...]
#
#   Target       A target with a `DocumentationScreenshots` test, such as GroveChat. Without targets, every
#                target that has one is regenerated.
#   --parallel   How many simulators run at once (default 3). Each job gets a simulator of its own.
#   --device     The simulator device type (default "iPhone 17 Pro").
#   --keep-simulators
#                Leave the simulators the script created in place, for another run soon after.
#
# A test declares launch arguments with a comment, read by this script:
#   // documentation-screenshots: launch-arguments --drawOnLaunch
# can install into another module's resources when one test bundle documents several targets:
#   // documentation-screenshots: resources Sources/GroveLLMOpenAI/GroveLLMOpenAI.docc/Resources
# and can ask for a capture to be copied elsewhere, which the umbrella documentation uses:
#   // documentation-screenshots: copy Conversation Sources/Grove/Grove.docc/Resources/Chat.png
# A view that only a snapshot test renders takes its picture from the test's reference image, installed as
# `<Name>.png` (no dark variant) in the target's resources or at an optional repo-relative destination:
#   // documentation-screenshots: snapshot Tests/GroveViewsTests/__Snapshots__/SnapshotTests+Lists/listRow.iphone-regular.png ListRow
#   // documentation-screenshots: snapshot Tests/GroveHealthKitTests/__Snapshots__/GroveHealthKitUITests/multiEntryHealthChartViewSnapshot.1.png HealthChart Sources/Grove/Grove.docc/Resources/HealthChart.png

set -euo pipefail

ROOT=${0:A:h:h}
ROCKETSIM=/Applications/RocketSim.app/Contents/Helpers/rocketsim
DEVICE_TYPE="iPhone 17 Pro"
PARALLEL=3
KEEP_SIMULATORS=false
DERIVED_DATA="$ROOT/.derivedData/documentation-screenshots"
SIMULATOR_PREFIX="Documentation Screenshots"

typeset -a TARGETS
while (( $# > 0 )); do
  case $1 in
    --parallel) PARALLEL=$2; shift 2;;
    --device) DEVICE_TYPE=$2; shift 2;;
    --keep-simulators) KEEP_SIMULATORS=true; shift;;
    -h|--help) sed -n '9,42p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) TARGETS+=("$1"); shift;;
  esac
done

log() { print -u2 -- "[$(date +%H:%M:%S)] $*"; }
fail() { log "error: $*"; exit 1; }

command -v xcrun >/dev/null || fail "Xcode command line tools are required."
[[ -x $ROCKETSIM ]] || fail "RocketSim is not installed; its CLI is expected at $ROCKETSIM."
$ROCKETSIM status >/dev/null 2>&1 || fail "RocketSim.app is not running; open it before regenerating screenshots."

test_file_for() { print -- "$ROOT/Tests/${1}Tests/UITests/TestAppUITests/DocumentationScreenshots.swift"; }
resources_for() {
  local resources=$(sed -n 's|^// documentation-screenshots: resources ||p' "$(test_file_for "$1")")
  print -- "$ROOT/${resources:-Sources/$1/$1.docc/Resources}"
}
device_state() {
  xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for device in devices:
        if device['udid'] == '$1':
            print(device['state']); sys.exit()
"
}

if (( ${#TARGETS} == 0 )); then
  for file in "$ROOT"/Tests/*Tests/UITests/TestAppUITests/DocumentationScreenshots.swift; do
    [[ -f $file ]] || continue
    target=${file#$ROOT/Tests/}; target=${target%%Tests/*}
    TARGETS+=("$target")
  done
fi
(( ${#TARGETS} > 0 )) || fail "No target has a DocumentationScreenshots test."
for target in "${TARGETS[@]}"; do
  [[ -f $(test_file_for "$target") ]] || fail "$target has no DocumentationScreenshots test."
done

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(sorted(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])[-1]["identifier"])')

# One simulator per parallel job, created on demand and reused across runs.
typeset -a SIMULATORS
for (( i = 1; i <= PARALLEL; i++ )); do
  name="$SIMULATOR_PREFIX $i"
  udid=$(xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for device in devices:
        if device['name'] == '$name' and device['isAvailable']:
            print(device['udid']); sys.exit()
")
  [[ -n $udid ]] || udid=$(xcrun simctl create "$name" "$DEVICE_TYPE" "$RUNTIME")
  SIMULATORS+=("$udid")
done

# Builds the test app and its UI tests once; the captures reuse the products.
build() {
  local target=$1 udid=$2
  log "$target: building"
  (cd "$ROOT/Tests/${target}Tests/UITests" && xcodebuild build-for-testing \
    -project UITests.xcodeproj -scheme TestApp \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$DERIVED_DATA/$target" \
    -skipPackagePluginValidation -skipMacroValidation \
    -quiet 2>&1 | grep -E "error:" || true)
  [[ -d "$DERIVED_DATA/$target/Build/Products/Debug-iphonesimulator/TestApp.app" ]] || fail "$target: build failed"
}

# Shoots the simulator through RocketSim into a file, trying again when it answers with an empty file, which it
# does for a moment after a launch.
shoot() {
  local udid=$1 file=$2 attempt capture=$(mktemp)
  for attempt in 1 2 3; do
    $ROCKETSIM screenshot --udid "$udid" --bezel device --background transparent > "$capture" 2>/dev/null
    if [[ -s $capture ]]; then
      # Only a picture replaces the previous one; a miss must not leave the target without an image.
      mv "$capture" "$file"
      return 0
    fi
    sleep 2
  done
  rm -f "$capture"
  return 1
}

# Reduces a capture to a 256-color palette at its full resolution; the bezel and UI take it without visible loss.
compress() {
  if command -v pngquant >/dev/null; then
    pngquant --quality 85-100 --speed 1 --strip --force --output "$1" -- "$1"
  elif [[ -z ${WARNED_ABOUT_PNGQUANT:-} ]]; then
    log "pngquant is not installed; captures stay at their full size (brew install pngquant)"
    WARNED_ABOUT_PNGQUANT=1
  fi
}

# Kills a test run whose log has not grown for five minutes; the runner then reports it and the queue continues.
watchdog() {
  local pid=$1 file=$2 size=-1 current
  while kill -0 "$pid" 2>/dev/null; do
    sleep 30
    current=$(stat -f %z "$file" 2>/dev/null || echo 0)
    if [[ $current -eq $size ]]; then
      log "no output for five minutes; stopping the stalled test run"
      pkill -P "$pid" 2>/dev/null || true
      kill "$pid" 2>/dev/null || true
      return
    fi
    size=$current
    sleep 270
  done
}

# Runs the DocumentationScreenshots test in one appearance and installs every capture it announces.
capture() {
  local target=$1 udid=$2 appearance=$3
  local project_dir="$ROOT/Tests/${target}Tests/UITests"
  local app="$DERIVED_DATA/$target/Build/Products/Debug-iphonesimulator/TestApp.app"
  local bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
  local test_file=$(test_file_for "$target")
  local resources=$(resources_for "$target")
  local launch_arguments=$(sed -n 's|^// documentation-screenshots: launch-arguments ||p' "$test_file")
  local suffix=""
  [[ $appearance == dark ]] && suffix="~dark"
  mkdir -p "$resources"

  # A fresh boot, so no previous app leaves its "back to app" breadcrumb in the status bar. Not an erase: RocketSim
  # loses track of an erased device and answers with an empty picture.
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  until [[ $(device_state "$udid") == Shutdown ]]; do sleep 1; done
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance "$appearance"
  # The keyboard's swipe-to-type introduction would otherwise cover the first keyboard of a fresh simulator.
  xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true >/dev/null 2>&1 || true
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --operatorName ''
  xcrun simctl install "$udid" "$app"
  # No "--" before the arguments: it would reach the app, where an argument parser treats it as the end of its flags.
  xcrun simctl launch "$udid" "$bundle_id" ${=launch_arguments} >/dev/null
  sleep 4

  log "$target: capturing $appearance"
  # A walk that fails still yields the captures before the failure; the log says what went wrong. A walk that
  # goes quiet for minutes has stalled in the test runner and is killed, so the queue moves on.
  local test_log=$(mktemp)
  # The walks skip themselves unless this reaches the test runner; a regular test run must not shoot pictures.
  (cd "$project_dir" && TEST_RUNNER_GROVE_DOCUMENTATION_SCREENSHOTS=1 xcodebuild test-without-building \
    -project UITests.xcodeproj -scheme TestApp \
    -only-testing:TestAppUITests/DocumentationScreenshots \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$DERIVED_DATA/$target" \
    -parallel-testing-enabled NO > "$test_log" 2>&1 || true) &
  local test_pid=$!
  watchdog "$test_pid" "$test_log" &
  local watchdog_pid=$!
  # The reader follows the log in the background; once the test run has ended it gets a moment for the last lines
  # and is then released, since `tail -f` would wait forever on its own.
  tail -n +1 -f "$test_log" 2>/dev/null | while read -r line; do
    case "$line" in
      *"CAPTURE "*)
        name=${line##*CAPTURE }; name=${name%% *}
        sleep 1
        shoot "$udid" "$resources/$name$suffix.png" || { log "$target: RocketSim returned nothing for $name$suffix"; continue; }
        compress "$resources/$name$suffix.png"
        log "$target: $name$suffix.png"
        sed -n "s|^// documentation-screenshots: copy $name ||p" "$test_file" | while read -r destination; do
          cp "$resources/$name$suffix.png" "$ROOT/${destination%.png}$suffix.png"
        done;;
      *" error: "*|*"Failing tests:"*|*"failed ("*) log "$target: $line";;
    esac
  done &
  local reader_pid=$!
  wait "$test_pid" 2>/dev/null || true
  kill "$watchdog_pid" 2>/dev/null || true
  sleep 8
  pkill -f "tail -n \+1 -f $test_log" 2>/dev/null || true
  wait "$reader_pid" 2>/dev/null || true
  rm -f "$test_log"

  xcrun simctl status_bar "$udid" clear
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
}

# Installs the snapshot-test references a walk names, for views that only a snapshot test renders.
install_snapshots() {
  local target=$1 resources=$(resources_for "$1") source name destination
  sed -n 's|^// documentation-screenshots: snapshot ||p' "$(test_file_for "$target")" | while read -r source name destination; do
    destination=${destination:+$ROOT/$destination}
    destination=${destination:-$resources/$name.png}
    mkdir -p "${destination:h}"
    cp "$ROOT/$source" "$destination"
    compress "$destination"
    log "$target: ${destination:t} from ${source:t}"
  done
}

run_target() {
  local target=$1 udid=$2
  install_snapshots "$target"
  build "$target" "$udid"
  capture "$target" "$udid" light
  capture "$target" "$udid" dark
  log "$target: done"
}

# Targets are dealt out to the simulators; each simulator works through its share in sequence.
typeset -a pids
for (( i = 1; i <= ${#SIMULATORS}; i++ )); do
  (
    for (( j = i; j <= ${#TARGETS}; j += ${#SIMULATORS} )); do
      run_target "${TARGETS[$j]}" "${SIMULATORS[$i]}"
    done
  ) &
  pids+=($!)
done
exit_status=0
for pid in "${pids[@]}"; do
  wait "$pid" || exit_status=1
done

if [[ $KEEP_SIMULATORS == false ]]; then
  for udid in "${SIMULATORS[@]}"; do
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
  done
fi
exit $exit_status
