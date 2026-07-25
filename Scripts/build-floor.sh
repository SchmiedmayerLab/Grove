#!/usr/bin/env bash
#
# This source file is part of the Stanford Spezi open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
# Compile-checks that every library product builds at the package's DEPLOYMENT FLOOR
# (iOS 15 / macOS 12 / watchOS 8), for a real device and a simulator. This is the guard for the
# availability-annotation strategy: every API newer than the floor is gated behind an
# `@available(iOS 18, macOS 15, watchOS 11, *)` clause, so the package must still *compile* when a
# consumer's app targets the floor. The regular test matrix cannot catch a missing annotation because
# it builds the test targets at the current OS wave (OS 26), where every API is available.
#
# It builds — never tests, and never overrides the deployment target (that would defeat the check).
# Package traits stay OFF so we exercise exactly the lean default graph an iOS-15 consumer receives.
#
# We build the *top-level* library products (those not depended on by another product); their
# transitive closures compile every other library target's sources. Afterwards we assert that every
# platform-supported module actually produced a .swiftmodule, so a stale dependency-graph analysis
# surfaces as a hard coverage failure instead of silent under-coverage.
#
# Usage:
#   Scripts/build-floor.sh <iOS|macOS|watchOS> <device|simulator>   # macOS ignores the 2nd argument
#
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORM="${1:?usage: build-floor.sh <iOS|macOS|watchOS> <device|simulator>}"
KIND="${2:-simulator}"

case "$PLATFORM:$KIND" in
  iOS:device)         DEST="generic/platform=iOS" ;;
  iOS:simulator)      DEST="generic/platform=iOS Simulator" ;;
  watchOS:device)     DEST="generic/platform=watchOS" ;;
  watchOS:simulator)  DEST="generic/platform=watchOS Simulator" ;;
  macOS:*)            DEST="platform=macOS,arch=arm64" ;;
  *) echo "unknown platform/kind: $PLATFORM:$KIND" >&2; exit 2 ;;
esac

# Make sure a lowered floor, not the current OS wave, is what we compile against.
export SPEZI_LOWERED_DEPLOYMENT_TARGETS=1
unset SPEZI_ENABLE_DEFAULT_PACKAGE_TRAITS || true
# Everything lives under the gitignored `.derivedData/` so a build leaves the checkout clean.
mkdir -p .derivedData
DD=".derivedData/floor-$PLATFORM-$KIND"

# Resolve, for this platform, the top-level library products to build and the full set of supported
# modules to assert coverage over. Platform support comes from packages.toml (the curated union CI
# matrix); the dependency graph comes from the manifest dump.
swift package dump-package > "$DD.dump.json" 2>/dev/null || swift package dump-package > "$DD.dump.json"
# The analysis is written to a file (rather than a heredoc inside $()) because bash 3.2 — the /bin/bash
# on macOS runners — mis-parses a heredoc nested in command substitution.
ANALYZER=".derivedData/floor-analyze.py"
cat > "$ANALYZER" <<'PY'
import json, sys, tomllib
dump = json.load(open(sys.argv[1])); plat = sys.argv[2]
toml = tomllib.load(open('packages.toml', 'rb'))
plat_l = plat.lower()

libprods = {p["name"]: p["targets"] for p in dump["products"] if "library" in p["type"]}
targets = {t["name"]: t for t in dump["targets"]}

def edge(dep):
    """Returns (kind, name, condition) for a manifest dependency entry."""
    for kind in ("target", "byName"):
        if dep.get(kind):
            e = dep[kind]
            return (kind, e[0], e[1] if len(e) > 1 else None)
    if dep.get("product"):
        e = dep["product"]
        return ("product", e[0], e[3] if len(e) > 3 else None)
    return (None, None, None)

def active(cond):
    # The floor builds with every package trait disabled, so trait-conditioned edges are never
    # active here; platform-conditioned edges are active only on their listed platforms.
    if not cond:
        return True
    if cond.get("traits"):
        return False
    plats = cond.get("platformNames")
    return not plats or plat_l in plats

def dep_targets(t):
    out = set()
    for dep in t.get("dependencies", []):
        kind, name, cond = edge(dep)
        if kind in ("target", "byName") and name in targets and active(cond):
            out.add(name)
    return out

# Hard per-platform unsupportedness. CONVENTION: an *external product* dependency edge that carries a
# platform-only condition (no traits) marks a hard requirement — the target cannot compile where the
# edge is conditioned away (e.g. the FHIRModels stack, which cannot link for armv7k, is conditioned
# off watchOS in the lowered configuration). Trait-conditioned edges never count: by repo convention
# their consumers are source-gated (`#if <Trait>`) and compile to empty without them.
# Unsupportedness propagates transitively along active in-package edges.
unsupported = set()
for name, t in targets.items():
    for dep in t.get("dependencies", []):
        kind, _, cond = edge(dep)
        if kind == "product" and cond and not cond.get("traits"):
            plats = cond.get("platformNames")
            if plats and plat_l not in plats:
                unsupported.add(name)
                break
changed = True
while changed:
    changed = False
    for name, t in targets.items():
        if name not in unsupported and any(d in unsupported for d in dep_targets(t)):
            unsupported.add(name)
            changed = True

pkg_plat, tgt_pkg = {}, {}
for pkg, info in toml.items():
    if not isinstance(info, dict) or "platforms" not in info:
        continue
    pkg_plat[pkg] = set(info["platforms"])
    for tt in info.get("targets", []):
        tgt_pkg[tt] = pkg

def supports(prod):
    mts = libprods[prod]
    if any(mt in unsupported for mt in mts):
        return False
    # supported if any owning sub-package covers this platform ...
    if any(plat in pkg_plat.get(tgt_pkg[mt], ()) for mt in mts if tgt_pkg.get(mt)):
        return True
    # ... or the product's targets are core targets not owned by any sub-package (all platforms).
    return all(tgt_pkg.get(mt) is None for mt in mts)

supported = [p for p in libprods if supports(p)]
sup_targets = {mt for p in supported for mt in libprods[p]}
depended = {d for tn in sup_targets if tn in targets for d in dep_targets(targets[tn]) if d in sup_targets}
toplevel = sorted(p for p in supported if not any(mt in depended for mt in libprods[p]))
mods = sorted(mt for mt in sup_targets if mt not in unsupported)
print(" ".join(toplevel) + "\t" + " ".join(mods))
PY
PYOUT="$(python3 "$ANALYZER" "$DD.dump.json" "$PLATFORM")"
IFS=$'\t' read -r TOPLEVEL SUPPORTED <<< "$PYOUT"

IFS=' ' read -r -a TOP <<< "$TOPLEVEL"
IFS=' ' read -r -a MODS <<< "$SUPPORTED"

# Products that do NOT build on a given platform on `main` either — pre-existing platform limitations
# below packages.toml's package-level granularity. These modules carry a source `#if os(...)` that
# covers only some platforms with no fallback branch (e.g. an iOS/visionOS-only body that leaves a
# bodyless function on macOS), so they cannot compile on the excluded platform regardless of the
# deployment floor. They are skipped so the check flags only genuine floor regressions, never a
# limitation that predates this work. Keep this list SMALL and each entry justified. Format: Product:platform.
#   XCTSpeziNotifications on macOS and watchOS: its XCUIApplication authorization-alert helper
#     (XCUIApplication+AuthorizationAlert.swift) is `#if os(iOS) … #elseif os(visionOS) … #endif` with no
#     macOS/watchOS branch, leaving a bodyless `-> Bool` method there. Byte-identical to main; not floor-related.
FLOOR_SKIP="XCTSpeziNotifications:macOS XCTSpeziNotifications:watchOS"
skipped() { case " $FLOOR_SKIP " in *" $1:$PLATFORM "*) return 0 ;; *) return 1 ;; esac; }

echo "==> $PLATFORM ($KIND) at deployment floor — ${#TOP[@]} top-level products cover ${#MODS[@]} modules"
echo "    destination: $DEST"

beautify() {
  if ! command -v xcbeautify >/dev/null 2>&1; then cat; return; fi
  if [ -n "${GITHUB_ACTIONS:-}" ]; then xcbeautify --renderer github-actions; else xcbeautify; fi
}

FAILED=()
SKIPPED=()
for prod in "${TOP[@]}"; do
  if skipped "$prod"; then
    echo "==> SKIP $prod (pre-existing $PLATFORM limitation — does not build on main either)"
    SKIPPED+=("$prod")
    continue
  fi
  echo "==> build $prod"
  if ! xcodebuild build \
      -scheme "$prod" \
      -destination "$DEST" \
      -configuration Debug \
      -derivedDataPath "$DD" \
      -skipMacroValidation -skipPackagePluginValidation \
      2>&1 | beautify; then
    FAILED+=("$prod")
  fi
done

# Coverage assertion: every platform-supported module must have produced a .swiftmodule. This catches
# any under-coverage from the top-level analysis (a module no top-level product actually pulled in).
# Skip-listed products (and any module reachable only through them) are excluded from the expectation.
BUILT="$(find "$DD/Build" -type d -name '*.swiftmodule' 2>/dev/null | sed 's#.*/##; s#\.swiftmodule$##' | sort -u)"
MISSING=()
for m in "${MODS[@]}"; do
  skipped "$m" && continue
  grep -qx "$m" <<< "$BUILT" || MISSING+=("$m")
done

echo
echo "===================== floor build-check summary: $PLATFORM ($KIND) ====================="
echo "built modules: $(wc -l <<< "$BUILT" | tr -d ' ')   expected-supported: ${#MODS[@]}"
if [ "${#SKIPPED[@]}" -ne 0 ]; then
  echo "skipped (pre-existing $PLATFORM limitations): ${SKIPPED[*]}"
fi
if [ "${#FAILED[@]}" -ne 0 ]; then
  echo "::error::floor build FAILED for: ${FAILED[*]}"
fi
if [ "${#MISSING[@]}" -ne 0 ]; then
  echo "::error::coverage gap — supported modules never built: ${MISSING[*]}"
fi
if [ "${#FAILED[@]}" -ne 0 ] || [ "${#MISSING[@]}" -ne 0 ]; then
  exit 1
fi
echo "OK — all ${#MODS[@]} $PLATFORM modules compile at the deployment floor."
