#!/usr/bin/env python3
#
# This source file is part of the Stanford Spezi open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
# Maps a list of changed files to the set of affected packages and emits THREE GitHub Actions job
# matrices: one for unit tests, one for UI tests, and one for package-trait product builds. Used by
# .github/workflows/tests.yml so only the checks for packages whose code actually changed are run —
# and whenever a package's unit tests run, its UI tests do too. Each emitted unit/UI job carries a
# `selfHosted` bool (see self-hosted-ci) that the workflow's `runs-on` uses to pick the self-hosted vs
# the GitHub-hosted runner.
#
# The logical sub-packages are defined in the repo-root packages.toml:
#   platforms      = the platforms its unit tests run on (subject to the temporary CI_PLATFORMS limit)
#   uiTests        = the platforms its UI tests run on, straight from the UITests project's Xcode config
#                    (NOT subject to CI_PLATFORMS — absent for packages with no UITests project)
#   traitBuilds    = package-trait product build checks CI should run for the package
#   self-hosted-ci = which test kinds run on the self-hosted runner (vs GitHub-hosted): a subset of
#                    ["unit", "ui"]. Optional; default ["ui"] (= today's behavior). Linux unit jobs
#                    always run on GitHub-hosted ubuntu regardless (the self-hosted runner is macOS).
# The dir -> package map used for change detection is derived from each package's targets+tests.
#
# Usage:
#   affected-test-matrix.py <changed-files.txt>     # one path per line; or the literal __ALL__
#   git diff --name-only A B | affected-test-matrix.py
#   affected-test-matrix.py changed.txt --only-targets SpeziScheduler ResearchKitOnFHIR --only-job-kinds ui
#
# The --only-targets and --only-job-kinds options are intended for temporary CI debugging only.
# Workflow changes that pass these arguments must never be merged into main; remove them before the final PR validation.
#
# Emits (to stdout, GITHUB_OUTPUT format):
#   matrix={"include":[{"package":"SpeziAccount","platform":"macOS","selfHosted":false}, ...]}   # unit
#   ui_matrix={"include":[{"package":"SpeziViews","platform":"iOS","selfHosted":true}, ...]}      # UI
#   trait_matrix={"include":[{"package":"SpeziChat","product":"SpeziChat", ...}, ...]}            # traits
#   has_jobs=true|false
#   has_ui_jobs=true|false
#   has_trait_jobs=true|false
#   affected=SpeziAccount,SpeziViews
import argparse
import json
import os
import sys
import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(os.path.join(ROOT, "packages.toml"), "rb") as f:
    PKGS = tomllib.load(f)

# dir (directly under Sources/ or Tests/) -> logical package, derived from each package's
# `targets` + `tests`. A change under Tests/<X>/UITests/... still routes via its <X> test dir.
DIR2PKG = {}
for _pkg, _info in PKGS.items():
    for _d in _info.get("targets", []) + _info.get("tests", []):
        DIR2PKG[_d] = _pkg

# Any change to these means "run everything" (shared manifest / test infra / CI / lint / pkg defs).
GLOBAL_PREFIXES = (
    "Package.swift", "Package@", "Package.resolved", "packages.toml",
    ".swiftlint.yml", ".github/", "Scripts/", "Tests/TestPlans/", ".swiftpm/",
)

# TEMPORARY: limit UNIT-test scheduling to these platforms (macCatalyst/visionOS/tvOS excluded for
# now — remove from this tuple to restore). Linux runs on GitHub-hosted ubuntu.
CI_PLATFORMS = ("iOS", "macOS", "watchOS", "Linux")

# TEMPORARY: limit UI-test scheduling to these platforms. The full per-project set (from packages.toml
# `uiTests`) is iOS/iPadOS/visionOS; iPadOS + visionOS are disabled for now — add them back here to re-enable.
UI_PLATFORMS = ("iOS",)

def parse_arguments():
    parser = argparse.ArgumentParser(description="Compute affected package test matrices for GitHub Actions.")
    parser.add_argument(
        "changed_files",
        nargs="?",
        default="-",
        help="Path to a newline-delimited changed-files list, or '-' for stdin."
    )
    parser.add_argument(
        "--only-targets",
        "--only-packages",
        dest="only_packages",
        nargs="+",
        metavar="PACKAGE",
        default=(),
        help="Temporarily restrict matrices to these packages/targets while debugging CI. Do not merge workflow uses into main."
    )
    parser.add_argument(
        "--only-job-kinds",
        nargs="+",
        choices=("unit", "ui", "trait"),
        default=("unit", "ui", "trait"),
        help="Temporarily restrict emitted job kinds while debugging CI. Do not merge workflow uses into main."
    )
    return parser.parse_args()


def read_changed(path):
    if path == "-":
        return [ln.strip() for ln in sys.stdin if ln.strip()]
    with open(path) as src:
        return [ln.strip() for ln in src if ln.strip()]


def validate_package_filter(packages):
    unknown = sorted(set(packages).difference(PKGS))
    if unknown:
        known = ", ".join(sorted(PKGS))
        raise SystemExit(f"Unknown package(s) passed to --only-targets: {', '.join(unknown)}. Known packages: {known}")

def main():
    arguments = parse_arguments()
    changed = read_changed(arguments.changed_files)
    run_all = False
    affected = set()
    for path in changed:
        if path == "__ALL__" or path.startswith(GLOBAL_PREFIXES):
            run_all = True
            break
        parts = path.split("/")
        if len(parts) >= 2 and parts[0] in ("Sources", "Tests"):
            pkg = DIR2PKG.get(parts[1])
            if pkg:
                affected.add(pkg)
        # files elsewhere (root docs, etc.) affect no package

    if run_all:
        affected = set(PKGS.keys())

    validate_package_filter(arguments.only_packages)
    if arguments.only_packages:
        affected = affected.intersection(arguments.only_packages)
    job_kinds = set(arguments.only_job_kinds)

    unit, ui, trait = [], [], []
    for pkg in sorted(affected):
        info = PKGS[pkg]
        # Which test kinds run on the self-hosted runner (vs GitHub-hosted): a subset of
        # ["unit", "ui"]. Default ["ui"] keeps today's behavior (UI on self-hosted, unit on
        # GitHub-hosted). Each emitted job carries a `selfHosted` bool the workflow `runs-on` reads.
        self_hosted = info.get("self-hosted-ci", ["ui"])
        if "unit" in job_kinds:
            for platform in info["platforms"]:
                if platform in CI_PLATFORMS:  # TEMPORARY unit-test platform limit (see CI_PLATFORMS above)
                    # Linux unit jobs always use GitHub-hosted ubuntu (the self-hosted runner is macOS).
                    unit.append({"package": pkg, "platform": platform,
                                 "selfHosted": ("unit" in self_hosted) and platform != "Linux"})
        if "ui" in job_kinds:
            for platform in info.get("uiTests", []):  # UI tests: per-project platforms from packages.toml
                if platform not in UI_PLATFORMS:  # TEMPORARY UI-test platform limit (see UI_PLATFORMS above)
                    continue
                ui.append({"package": pkg, "platform": platform, "selfHosted": "ui" in self_hosted})
        if "trait" in job_kinds:
            for build in info.get("traitBuilds", []):
                trait.append({"package": pkg, **build})

    lines = [
        f'matrix={json.dumps({"include": unit})}',
        f'ui_matrix={json.dumps({"include": ui})}',
        f'trait_matrix={json.dumps({"include": trait})}',
        f'has_jobs={"true" if unit else "false"}',
        f'has_ui_jobs={"true" if ui else "false"}',
        f'has_trait_jobs={"true" if trait else "false"}',
        f'affected={",".join(sorted(affected)) if affected else "(none)"}',
    ]
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stderr.write(
        f"[affected-test-matrix] run_all={run_all} affected={sorted(affected)} "
        f"job_kinds={sorted(job_kinds)} unit_jobs={len(unit)} ui_jobs={len(ui)} trait_jobs={len(trait)}\n"
    )

if __name__ == "__main__":
    main()
