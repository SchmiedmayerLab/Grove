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
# Requirements: Xcode with an iOS simulator runtime, RocketSim (https://www.rocketsim.app) with its command line
# tool installed, and Pillow for python3 (`pip3 install pillow`), which checks the captures; the script starts
# RocketSim itself. The status bar is set to 9:41 with a full battery for
# every capture. With pngquant installed (`brew install pngquant`), every capture is reduced to a 256-color
# palette, which keeps the full resolution and takes a picture from roughly 800 KB to under 200 KB without a
# visible difference at the size the documentation shows it.
#
# Usage:
#   Scripts/documentation-screenshots.sh [--parallel N] [--build-parallel N] [--device "iPhone 17 Pro"]
#                                        [--keep-simulators] [--capture Name ...] [Target ...]
#
# Every target is built first. The first build compiles the package; its build directory is then cloned for each
# build job, so the targets that follow only link against what is already there. Each build's products are cloned
# aside for its walk, and the walks run afterwards, on as many simulators as asked for.
#
#   Target       A target with a `DocumentationScreenshots` test, such as GroveChat. Without targets, every
#                target that has one is regenerated.
#   --parallel   How many simulators run at once (default 3). Each job gets a simulator of its own.
#   --build-parallel
#                How many targets are built at once (default 4), once the first build has compiled the package.
#   --device     The simulator device type (default "iPhone 17 Pro").
#   --keep-simulators
#                Leave the simulators the script created in place, for another run soon after.
#   --capture    Keep only the named capture(s), such as `--capture Queue`; every other picture the walk announces
#                is left as it is. The walk still runs in full, since that is how the state is reached.
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
BUILD_PARALLEL=4
KEEP_SIMULATORS=false
DERIVED_DATA="$ROOT/.derivedData/documentation-screenshots"
# One build directory for every target, and the products of each build cloned out of it before the next one.
BUILD_DIR="$DERIVED_DATA/build"
# The package checkouts and their download cache, shared by every build: they are read-only inputs, and resolving
# and checking them out again in each build directory is what the package-plugin targets spend their minutes on.
SOURCE_PACKAGES="$DERIVED_DATA/SourcePackages"
PACKAGE_CACHE="$DERIVED_DATA/PackageCache"
SIMULATOR_PREFIX="Documentation Screenshots"
# Every capture that never settled is noted here, so a run that produced a picture of a moving screen ends red.
UNSETTLED=$(mktemp)
# When this run began, so a picture an earlier run left behind is told apart from one taken now.
RUN_STARTED=$(mktemp)

typeset -a TARGETS CAPTURES
while (( $# > 0 )); do
  case $1 in
    --capture) CAPTURES+=("$2"); shift 2;;
    --parallel) PARALLEL=$2; shift 2;;
    --build-parallel) BUILD_PARALLEL=$2; shift 2;;
    --device) DEVICE_TYPE=$2; shift 2;;
    --keep-simulators) KEEP_SIMULATORS=true; shift;;
    -h|--help) awk 'NR >= 9 && !/^#/ { exit } NR >= 9 { print }' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) TARGETS+=("$1"); shift;;
  esac
done

log() { print -u2 -- "[$(date +%H:%M:%S)] $*"; }
fail() { log "error: $*"; exit 1; }

command -v xcrun >/dev/null || fail "Xcode command line tools are required."
[[ -x $ROCKETSIM ]] || fail "RocketSim is not installed; its CLI is expected at $ROCKETSIM."

# The CLI exits 0 whether or not the app is running; only the report says.
rocketsim_running() { $ROCKETSIM status 2>/dev/null | grep -q '"rocket_sim_running":true'; }

# RocketSim learns the simulators when it starts; asked about one it does not know, it answers with a picture of
# another one. After a device boots, RocketSim is started again so the device is one it knows. The jobs take
# turns at this: a restart in the middle of another job's shot only costs that job a retry.
ROCKETSIM_LOCK="$DERIVED_DATA/rocketsim.lock"
mkdir -p "$DERIVED_DATA"
rm -rf "$ROCKETSIM_LOCK" # a run killed mid-restart leaves the lock behind
rocketsim_restart() {
  # A job killed while it held the lock would hold up every other job for the rest of the run; a lock older
  # than any restart takes is treated as abandoned, and no job waits on one for longer than that either.
  local waited=0
  while ! mkdir "$ROCKETSIM_LOCK" 2>/dev/null; do
    if (( $(date +%s) - $(stat -f %m "$ROCKETSIM_LOCK" 2>/dev/null || print 0) > 90 )); then
      rm -rf "$ROCKETSIM_LOCK"
      continue
    fi
    (( waited++ >= 90 )) && break
    sleep 1
  done
  osascript -e 'tell application "RocketSim" to quit' >/dev/null 2>&1 || true
  local attempt
  for attempt in {1..15}; do
    rocketsim_running || break
    sleep 1
  done
  rocketsim_up
  rm -rf "$ROCKETSIM_LOCK"
}

# RocketSim quits when a device it is showing shuts down; whoever needs it next starts it again.
rocketsim_up() {
  rocketsim_running && return 0
  open -g -a RocketSim
  local attempt
  for attempt in {1..30}; do
    sleep 1
    rocketsim_running && return 0
  done
  fail "RocketSim did not start."
}

test_file_for() { print -- "$ROOT/Tests/${1}Tests/UITests/TestAppUITests/DocumentationScreenshots.swift"; }
resources_for() {
  local resources=$(sed -n 's|^// documentation-screenshots: resources ||p' "$(test_file_for "$1")")
  print -- "$ROOT/${resources:-Sources/$1/$1.docc/Resources}"
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

# An idle simulator from an earlier run is what RocketSim hands back for a device it does not know; none stays up.
xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for device in devices:
        if device['name'].startswith('$SIMULATOR_PREFIX') and device['state'] == 'Booted':
            print(device['udid'])
" | while read -r udid; do
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
done

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

# Every simulator stays booted for the whole run: RocketSim learns the devices when it starts and quits when one
# it shows shuts down, so devices that come and go mean restarts, and restarts in the middle of a walk mean
# pictures taken after the walk has moved on. The status bar override also hides the breadcrumb a launch from
# another app would leave, which is what a reboot between passes used to be for.
prepare_simulator() {
  local udid=$1
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  # The keyboard's swipe-to-type introduction would otherwise cover the first keyboard of a fresh simulator, and
  # its spell check would underline a typed address in red.
  xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true >/dev/null 2>&1 || true
  xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences KeyboardCheckSpelling -bool false >/dev/null 2>&1 || true
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --operatorName ''
}

# The derived data a target's walk runs against: its own copy of the products the shared build left.
walk_data_for() {
  print "$DERIVED_DATA/walk/$1"
}

# Builds the test app and its UI tests once, for any simulator, and clones the products aside: the next target
# builds into the same directory, over this target's `TestApp.app`. A clone on APFS costs no space.
build() {
  local target=$1 build_dir=${2:-$BUILD_DIR}
  log "$target: building"
  local build_log=$(mktemp)
  (cd "$ROOT/Tests/${target}Tests/UITests" && xcodebuild build-for-testing \
    -project UITests.xcodeproj -scheme TestApp \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$build_dir" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
    -packageCachePath "$PACKAGE_CACHE" \
    -skipPackagePluginValidation -skipMacroValidation \
    -quiet > "$build_log" 2>&1) || { grep -E "error:" "$build_log" | grep -v "^error: the following command failed" >&2; rm -f "$build_log"; fail "$target: build failed"; }
  rm -f "$build_log"
  local walk_data=$(walk_data_for "$target")
  # A walk that is still winding down can be writing here; the second attempt finds it gone.
  rm -rf "$walk_data" 2>/dev/null || { sleep 3; rm -rf "$walk_data"; }
  mkdir -p "$walk_data/Build"
  cp -Rc "$build_dir/Build/Products" "$walk_data/Build/Products" 2>/dev/null \
    || cp -R "$build_dir/Build/Products" "$walk_data/Build/Products"
  print $walk_data/Build/Products/*.xctestrun(N) | read -r _ || fail "$target: the build left no xctestrun behind."
}

# Shoots the simulator through RocketSim into a file, trying again when it answers with an empty file, which it
# does for a moment after a launch.
shoot() {
  local udid=$1 file=$2 attempt capture=$(mktemp)
  for attempt in 1 2 3; do
    rocketsim_up
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

# Whether two captures show the same screen, give or take the pixels a caret blink moves.
same_screen() {
  python3 - "$1" "$2" <<'PYTHON'
import sys, warnings
warnings.simplefilter("ignore")
from PIL import Image, ImageChops
first, second = (Image.open(path).convert("RGB") for path in sys.argv[1:3])
if first.size != second.size:
    sys.exit(1)
difference = ImageChops.difference(first, second).convert("L").point(lambda value: 255 if value > 24 else 0)
changed = difference.histogram()[255] / (first.size[0] * first.size[1])
sys.exit(0 if changed < 0.005 else 1)
PYTHON
}

# Whether a framed capture shows the same screen the simulator itself reports: RocketSim hands back a picture of
# another device for one it does not know, and only the device's own screenshot can tell.
shows_device() {
  local udid=$1 file=$2 own=$(mktemp).png
  xcrun simctl io "$udid" screenshot "$own" >/dev/null 2>&1 || { rm -f "$own"; return 0; }
  python3 - "$file" "$own" <<'PYTHON'
import sys, warnings
warnings.simplefilter("ignore")
from PIL import Image, ImageChops
framed, own = (Image.open(path).convert("RGB") for path in sys.argv[1:3])
def middle(image):
    width, height = image.size
    return image.crop((width // 4, height // 4, width * 3 // 4, height * 3 // 4)).resize((48, 48))
difference = ImageChops.difference(middle(framed), middle(own)).convert("L")
mean = sum(index * count for index, count in enumerate(difference.histogram())) / (48 * 48)
sys.exit(0 if mean < 40 else 1)
PYTHON
  local matched=$?
  rm -f "$own"
  return $matched
}

# A capture taken while the screen is still moving shows a sheet half-presented, a menu still open, or the state
# after the one the walk announced. Two shots a moment apart have to agree before the picture is kept, and the
# picture has to be of this device.
shoot_settled() {
  local udid=$1 file=$2 attempt second=$(mktemp).png
  for attempt in 1 2 3; do
    shoot "$udid" "$file" || { rm -f "$second"; return 1; }
    if ! shows_device "$udid" "$file"; then
      sleep 2
      continue
    fi
    sleep 1
    shoot "$udid" "$second" || { rm -f "$second"; return 1; }
    if same_screen "$file" "$second"; then
      mv "$second" "$file"
      return 0
    fi
  done
  rm -f "$second"
  return 2
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
  local app="$(walk_data_for "$target")/Build/Products/Debug-iphonesimulator/TestApp.app"
  local bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
  local test_file=$(test_file_for "$target")
  local resources=$(resources_for "$target")
  local launch_arguments=$(sed -n 's|^// documentation-screenshots: launch-arguments ||p' "$test_file")
  local suffix=""
  [[ $appearance == dark ]] && suffix="~dark"
  mkdir -p "$resources"

  xcrun simctl ui "$udid" appearance "$appearance"
  # The previous pass's app goes, so this one starts from its first screen.
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
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
    -derivedDataPath "$(walk_data_for "$target")" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
    -packageCachePath "$PACKAGE_CACHE" \
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
        if (( ${#CAPTURES} )) && (( ${CAPTURES[(Ie)$name]} == 0 )); then
          continue
        fi
        sleep 1
        shoot_settled "$udid" "$resources/$name$suffix.png"
        case $? in
          0) ;;
          2) log "$target: $name$suffix never settled, or RocketSim kept answering with another device"
             print "unsettled" >> "$UNSETTLED"; continue;;
          *) log "$target: RocketSim returned nothing for $name$suffix"; continue;;
        esac
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
  capture "$target" "$udid" light
  capture "$target" "$udid" dark
  log "$target: done"
}

for udid in "${SIMULATORS[@]}"; do
  prepare_simulator "$udid"
done
rocketsim_restart

# The builds come first. The first target is built on its own, which is what compiles the package; its build
# directory is then cloned for each job, so the targets that follow only link against what is already there.
# A clone costs no space on APFS, and a directory of its own keeps the jobs off each other's build database.
exit_status=0
for target in "${TARGETS[@]}"; do
  install_snapshots "$target"
done
build "${TARGETS[1]}"
if (( ${#TARGETS} > 1 )); then
  typeset -a build_pids
  for (( i = 1; i <= BUILD_PARALLEL && i + 1 <= ${#TARGETS}; i++ )); do
    (
      build_dir="$BUILD_DIR-$i"
      rm -rf "$build_dir"
      cp -Rc "$BUILD_DIR" "$build_dir" 2>/dev/null || cp -R "$BUILD_DIR" "$build_dir"
      for (( j = i + 1; j <= ${#TARGETS}; j += BUILD_PARALLEL )); do
        build "${TARGETS[$j]}" "$build_dir"
      done
    ) &
    build_pids+=($!)
  done
  for pid in "${build_pids[@]}"; do
    wait "$pid" || exit_status=1
  done
  (( exit_status == 0 )) || exit $exit_status
fi

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
for pid in "${pids[@]}"; do
  wait "$pid" || exit_status=1
done

# Every capture has a light and a dark picture, and the dark one is the darker of the two: a dark pass that ran
# in light appearance, or a walk that failed before a capture, would otherwise pass unnoticed.
for target in "${TARGETS[@]}"; do
  resources=$(resources_for "$target")
  sed -n 's|^ *capture("\([^"]*\)").*|\1|p' "$(test_file_for "$target")" | sort -u | while read -r name; do
    if (( ${#CAPTURES} )) && (( ${CAPTURES[(Ie)$name]} == 0 )); then
      continue
    fi
    # A picture a snapshot directive installs is not the walk's to take.
    grep -q "^// documentation-screenshots: snapshot .* $name\( \|$\)" "$(test_file_for "$target")" && continue
    light="$resources/$name.png" dark="$resources/$name~dark.png"
    if [[ ! -f $light || ! -f $dark ]]; then
      log "$target: $name is missing its light or dark picture"; print "missing" >> "$UNSETTLED"; continue
    fi
    if [[ ! $light -nt $RUN_STARTED || ! $dark -nt $RUN_STARTED ]]; then
      log "$target: $name was not taken by this run"; print "stale" >> "$UNSETTLED"; continue
    fi
    python3 - "$light" "$dark" <<'PYTHON' || { log "$target: $name~dark is no darker than $name; the dark pass did not take"; print "appearance" >> "$UNSETTLED"; }
import sys, warnings
warnings.simplefilter("ignore")
from PIL import Image, ImageStat
light, dark = (ImageStat.Stat(Image.open(path).convert("L")).mean[0] for path in sys.argv[1:3])
sys.exit(0 if dark < light - 10 else 1)
PYTHON
  done
done

if [[ -s $UNSETTLED ]]; then
  log "$(wc -l < "$UNSETTLED" | tr -d ' ') capture(s) failed their checks; see the log above"
  exit_status=1
fi
rm -f "$UNSETTLED" "$RUN_STARTED"

for udid in "${SIMULATORS[@]}"; do
  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  [[ $KEEP_SIMULATORS == false ]] && xcrun simctl delete "$udid" >/dev/null 2>&1 || true
done
exit $exit_status
