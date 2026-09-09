#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
# Maps a list of changed files to the set of affected packages and emits TWO GitHub Actions job
# matrices: one for unit tests and one for UI tests. Used by .github/workflows/tests.yml so only the
# tests of packages whose code actually changed are run — and whenever a package's unit tests run, its
# UI tests do too. Each emitted job carries a `selfHosted` bool (see self-hosted-ci) that the
# workflow's `runs-on` uses to pick the self-hosted vs the GitHub-hosted runner.
#
# The logical sub-packages are defined in the repo-root packages.toml:
#   platforms      = the platforms its unit tests run on, narrowed to the platforms currently
#                    enabled by CI_PLATFORMS for every selector mode
#   uiTests        = the platforms its UI tests run on, straight from the UITests project's Xcode
#                    config, narrowed to the platforms currently enabled by UI_PLATFORMS for every
#                    selector mode
#   self-hosted-ci = which test kinds run on the self-hosted runner (vs GitHub-hosted): a subset of
#                    ["unit", "ui"]. Optional; default ["ui"] (= today's behavior). Linux unit jobs
#                    always run on GitHub-hosted ubuntu regardless (the self-hosted runner is macOS).
#   extra_runner_labels = additional runner labels to require for this package's self-hosted jobs, on
#                    top of the base ["self-hosted", "macOS"]. Optional; default []. Emitted per job as
#                    `selfHostedLabels` for the workflow's `runs-on` (e.g. ["python3.11+"] pins the
#                    jobs to a self-hosted runner with a new-enough Python).
# The dir -> package map used for change detection is derived from each package's targets+tests.
#
# Usage:
#   affected-test-matrix.py <changed-files.txt>     # one path per line; or the literal __ALL__
#   git diff --name-only A B | affected-test-matrix.py
# The workflow always supplies SwiftPM `dump-package` JSON for the head revision, and for the base
# revision as well when Package.swift changed. A changed source or test file schedules the package
# that owns its target plus every package that consumes that target, transitively, so a change in a
# shared module runs exactly what builds on it. Without the head graph the owner alone is scheduled.
#
# Only a manifest change the graph diff cannot classify runs the whole matrix; no lockfile is
# tracked (Package.resolved is ignored). Changes to the test workflow, the shared actions,
# the runner script or the Xcode scheme run a smoke set instead: one package per distinct
# configuration shape in packages.toml (platforms, UI tests, Linux targets, runner routing), which
# exercises every job variant without repeating it for every package. An unknown script under
# Scripts/ is an error until it is classified below, as a new target must be assigned to a package.
#
# Emits (to stdout, GITHUB_OUTPUT format):
#   matrix={"include":[{"package":"GroveAccount","platform":"macOS","selfHosted":false,"selfHostedLabels":"[...]"}, ...]}  # unit
#   ui_matrix={"include":[{"package":"GroveViews","platform":"iOS","selfHosted":true,"selfHostedLabels":"[...]"}, ...]}    # UI
#   has_jobs=true|false
#   has_ui_jobs=true|false
#   has_fhir_conformance=true|false
#   fhir_components=healthkit,questionnaire,sensor
#   affected=GroveAccount,GroveViews
import argparse
import json
import os
import sys

# tomllib needs Python 3.11+; checking the version (rather than try-importing) also lets Pylance
# mark the rest of the file unreachable instead of flagging the import when an older interpreter is selected.
if sys.version_info < (3, 11):
    sys.exit("error: this script requires Python 3.11+ (uses tomllib)")

import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_toml(path):
    with open(path, "rb") as file:
        return tomllib.load(file)


PKGS = load_toml(os.path.join(ROOT, "packages.toml"))

# dir (directly under Sources/ or Tests/) -> logical package, derived from each package's
# `targets` + `tests`. A change under Tests/<X>/UITests/... still routes via its <X> test dir.
def directory_to_package(packages):
    result = {}
    for package, info in packages.items():
        for directory in info.get("targets", []) + info.get("tests", []):
            result[directory] = package
    return result


DIR2PKG = directory_to_package(PKGS)

# Any change to these means "run everything" (shared test infrastructure, CI, or lint configuration).
# The legacy-identifier vault is in here because it belongs to no single package: every string in it
# names data already on a user's device, and fourteen targets read it.
# Infrastructure every job shares; a change here is checked on the smoke set (see smoke_packages).
INFRASTRUCTURE_PREFIXES = (".github/actions/", ".swiftpm/")

# Declares one UI-test project per top-level table, keyed by logical package, so a change here can
# be diffed per table instead of fanning out into every package's tests.
UI_TEST_PROJECTS_PATH = "Tests/UITestProjects.toml"

INFRASTRUCTURE_PATHS = {
    # value: whether the shared change can also affect the FHIR conformance job
    ".github/workflows/tests.yml": True,
    "Scripts/run-package-tests.sh": False,
}

# These scripts have their own static-analysis or deployment-floor checks. Editing them cannot alter
# a package's unit/UI behavior, so they should not fan out into the package test matrix.
NON_TEST_SCRIPT_PATHS = {
    "Scripts/affected-test-matrix.py",
    "Scripts/build-documentation.sh",
    "Scripts/build-floor.sh",
    "Scripts/check-documentation-targets.py",
    "Scripts/check-gyb-output.sh",
    "Scripts/ci-dryrun.sh",
    "Scripts/cleanup-generated-artifacts.sh",
    "Scripts/generate-ui-test-projects.py",
    "Scripts/run-periphery.sh",
}

FHIR_VALIDATION_PATHS = {
    "Scripts/check-fhir-canonical-hygiene.sh",
    "Scripts/generate-grove-fhir-producer-manifest.py",
    "Scripts/generate-grove-fhir-semantic-vector-fixtures.py",
    "Scripts/generate-grove-fhir-swift-contract.py",
    "Scripts/generate-grove-sensor-swift-contract.py",
    "Scripts/validate-fhir-conformance.sh",
}
# The end-to-end validator is expensive, so its CI job runs only when one of these FHIR-producing or
# FHIR-consuming packages is affected (or when its orchestration script changes directly).
FHIR_PACKAGES = {
    "FHIRModelsExtensions",
    "ResearchKitOnFHIR",
    "GroveFHIR",
    "GroveHealthKitFHIR",
    "GroveQuestionnaire",
    "GroveSensorKit",
    "GroveSensorKitFHIR",
}

# Producer components are intentionally narrower than FHIR_PACKAGES. Shared model/generator changes
# join whichever producer changes in the same PR; a shared-only change conservatively validates all
# producers. This lets each independently mergeable stacked PR validate only the IGs it implements.
FHIR_COMPONENT_PACKAGES = {
    "healthkit": {"GroveHealthKitFHIR"},
    "questionnaire": {"GroveQuestionnaire", "ResearchKitOnFHIR"},
    "sensor": {"GroveSensorKit", "GroveSensorKitFHIR"},
}
ALL_FHIR_COMPONENTS = set(FHIR_COMPONENT_PACKAGES)

# Temporary stacked-PR scopes. A scope is honored only when the caller opts in explicitly. The broad
# FHIR scope is capped to the producer/consumer stack plus the HealthKit and Study support packages
# changed by this branch; narrower scopes continue to include directly changed target owners. This
# avoids rerunning unrelated packages already validated at earlier branch heads while retaining all
# configured unit and UI lanes for the active stack. Release and main CI remain unaffected; delete
# `.github/GROVE_FHIR_DEVELOPMENT_SCOPE` and run the explicit full-readiness workflow before merge.
DEVELOPMENT_SCOPES = {
    "fhir": FHIR_PACKAGES | {"GroveHealthKit", "GroveStudy"},
    "healthkit": {"GroveHealthKitFHIR"},
    "questionnaire": {"GroveQuestionnaire"},
    "sensor": {"GroveSensorKit", "GroveSensorKitFHIR"},
}

# TEMPORARY: limit UNIT-test scheduling to these currently enabled CI platforms, including explicit
# all-package/full-readiness runs. Linux uses GitHub-hosted ubuntu.
CI_PLATFORMS = ("iOS", "macOS", "watchOS", "Linux")

# TEMPORARY: limit UI-test scheduling to these currently enabled CI platforms, including explicit
# all-package/full-readiness runs.
UI_PLATFORMS = ("iOS",)

def smoke_packages(packages=None):
    """One package per distinct configuration shape: enough to exercise every job variant."""
    packages = packages or PKGS
    shapes = {}
    for name, info in packages.items():
        shape = (
            tuple(sorted(set(info["platforms"]) & set(CI_PLATFORMS))),
            tuple(sorted(set(info.get("uiTests", [])) & set(UI_PLATFORMS))),
            bool(info.get("linuxTargets")),
            tuple(sorted(info.get("self-hosted-ci", ["ui"]))),
            tuple(info.get("extra_runner_labels", [])),
        )
        shapes.setdefault(shape, []).append(name)
    return {sorted(names, key=lambda name: (len(packages[name]["targets"]), name))[0] for names in shapes.values()}


def packages_consuming(directory, head_dump):
    """The packages owning the targets under `Sources/<directory>` or `Tests/<directory>` and every
    package consuming them, transitively. None when the graph does not know the directory."""
    targets = keyed(head_dump.get("targets", []))
    roots = {
        name for name, target in targets.items()
        if (target.get("path") or "").split("/")[1:2] == [directory] or name == directory
    }
    if not roots:
        return None
    reverse = {}
    for name, target in targets.items():
        for dependency in target_dependencies(target):
            reverse.setdefault(dependency, set()).add(name)
    reached, pending = set(roots), list(roots)
    while pending:
        for dependent in reverse.get(pending.pop(), set()):
            if dependent not in reached:
                reached.add(dependent)
                pending.append(dependent)
    return {package for package in (package_for_target(name, targets, [DIR2PKG]) for name in reached) if package}


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("changed_files", nargs="?", default="-")
    parser.add_argument("--base-package-dump")
    parser.add_argument("--base-ui-test-projects")
    parser.add_argument("--head-package-dump")
    parser.add_argument("--base-packages")
    parser.add_argument("--development-scope", choices=sorted(DEVELOPMENT_SCOPES))
    parser.add_argument(
        "--full-readiness",
        action="store_true",
        help=(
            "Run every package on the currently enabled CI platforms while retaining "
            "change-aware FHIR components."
        ),
    )
    parser.add_argument(
        "--fhir-only",
        action="store_true",
        help="Run all FHIR producer conformance lanes without scheduling unit or UI jobs.",
    )
    return parser.parse_args()


def read_changed(path):
    if path == "-":
        return [line.strip() for line in sys.stdin if line.strip()]
    with open(path) as file:
        return [line.strip() for line in file if line.strip()]


def load_json(path):
    with open(path) as file:
        return json.load(file)


def normalized_identity(value):
    return "".join(character for character in value.lower() if character.isalnum())


def package_dependency_identity(dependency):
    for kind in ("sourceControl", "registry", "fileSystem"):
        entries = dependency.get(kind)
        if not entries:
            continue
        identity = entries[0].get("identity") if isinstance(entries[0], dict) else None
        if identity:
            return normalized_identity(identity)
    return None


def target_dependencies(target):
    dependencies = set()
    for dependency in target.get("dependencies", []):
        value = dependency.get("target") or dependency.get("byName")
        if value:
            dependencies.add(value[0])
    return dependencies



def direct_packages_for_target(target_name, package_dump, directory_map):
    """Returns the changed target's owner, or the nearest owners of an unowned shared target.

    Temporary development CI intentionally stops at the first mapped consumer instead of walking
    through that package to every transitive dependent. Full-readiness CI uses
    ``packages_consuming`` and retains the complete reverse dependency closure.
    """
    if target_name in directory_map:
        return {directory_map[target_name]}
    targets = {target["name"]: target for target in package_dump.get("targets", [])}
    if target_name not in targets:
        return None
    reverse = {}
    for name, target in targets.items():
        for dependency in target_dependencies(target):
            reverse.setdefault(dependency, set()).add(name)
    packages, reached, pending = set(), {target_name}, [target_name]
    while pending:
        current = pending.pop()
        for dependent in reverse.get(current, set()):
            if dependent in directory_map:
                packages.add(directory_map[dependent])
            elif dependent not in reached:
                reached.add(dependent)
                pending.append(dependent)
    return packages or None


def external_package_dependencies(target):
    dependencies = set()
    for dependency in target.get("dependencies", []):
        value = dependency.get("product")
        if value and len(value) > 1 and value[1]:
            dependencies.add(normalized_identity(value[1]))
    return dependencies


def keyed(items):
    return {item["name"]: item for item in items}


def changed_keys(base, head):
    return {
        key
        for key in set(base) | set(head)
        if base.get(key) != head.get(key)
    }


class UnclassifiedTargetsError(ValueError):
    pass


def package_for_target(target_name, targets, directory_maps):
    target = targets.get(target_name, {})
    path = target.get("path", "")
    directory = None
    parts = path.split("/")
    if len(parts) >= 2 and parts[0] in ("Sources", "Tests"):
        directory = parts[1]
    candidates = [directory, target_name]
    for directory_map in directory_maps:
        for candidate in candidates:
            if candidate and candidate in directory_map:
                return directory_map[candidate]
    return None


def traits_by_name(dump):
    return {
        trait.get("name", ""): {**trait, "enabledTraits": sorted(trait.get("enabledTraits", []))}
        for trait in dump.get("traits", [])
    }


def changed_traits(base_dump, head_dump):
    """The traits whose definition or default state differs between the two manifests.

    A trait only gates the dependencies that name it, so a trait change reaches exactly the targets
    with such a dependency; toggling a trait in the `default` set counts as a change to that trait.
    """
    base, head = traits_by_name(base_dump), traits_by_name(head_dump)
    changed = {name for name in set(base) | set(head) if base.get(name) != head.get(name)}
    if "default" in changed:
        changed.discard("default")
        changed |= set(base.get("default", {}).get("enabledTraits", [])) ^ set(head.get("default", {}).get("enabledTraits", []))
    return changed


def dependency_traits(target):
    """The traits any of the target's dependencies is conditioned on."""
    traits = set()
    for dependency in target.get("dependencies", []):
        for value in dependency.values():
            condition = next((item for item in value if isinstance(item, dict)), None)
            traits.update((condition or {}).get("traits", []))
    return traits


def affected_by_manifest(base_dump, head_dump, base_packages):
    ignored_keys = {"dependencies", "packageKind", "products", "targets", "traits"}
    base_global = {key: value for key, value in base_dump.items() if key not in ignored_keys}
    head_global = {key: value for key, value in head_dump.items() if key not in ignored_keys}
    if base_global != head_global:
        changed = sorted(key for key in set(base_global) | set(head_global) if base_global.get(key) != head_global.get(key))
        sys.stderr.write(f"[affected-test-matrix] manifest: top-level keys changed ({', '.join(changed)}); running everything\n")
        return None

    base_targets = keyed(base_dump.get("targets", []))
    head_targets = keyed(head_dump.get("targets", []))
    changed_targets = changed_keys(base_targets, head_targets)

    base_products = keyed(base_dump.get("products", []))
    head_products = keyed(head_dump.get("products", []))
    for product_name in changed_keys(base_products, head_products):
        for product in (base_products.get(product_name), head_products.get(product_name)):
            if product:
                changed_targets.update(product.get("targets", []))

    def dependencies_by_identity(dump):
        result = {}
        unknown = []
        for dependency in dump.get("dependencies", []):
            identity = package_dependency_identity(dependency)
            if identity:
                result[identity] = dependency
            else:
                unknown.append(dependency)
        return result, unknown

    base_dependencies, base_unknown_dependencies = dependencies_by_identity(base_dump)
    head_dependencies, head_unknown_dependencies = dependencies_by_identity(head_dump)
    if base_unknown_dependencies != head_unknown_dependencies:
        sys.stderr.write("[affected-test-matrix] manifest: a dependency without an identity changed; running everything\n")
        return None
    changed_dependencies = changed_keys(base_dependencies, head_dependencies)
    if changed_dependencies:
        for name, target in {**base_targets, **head_targets}.items():
            if external_package_dependencies(target) & changed_dependencies:
                changed_targets.add(name)
    toggled_traits = changed_traits(base_dump, head_dump)
    if toggled_traits:
        for name, target in {**base_targets, **head_targets}.items():
            if dependency_traits(target) & toggled_traits:
                changed_targets.add(name)

    reverse_dependencies = {}
    for targets in (base_targets, head_targets):
        for name, target in targets.items():
            for dependency in target_dependencies(target):
                reverse_dependencies.setdefault(dependency, set()).add(name)

    affected_targets = set(changed_targets)
    pending = list(changed_targets)
    while pending:
        dependency = pending.pop()
        for dependent in reverse_dependencies.get(dependency, set()):
            if dependent not in affected_targets:
                affected_targets.add(dependent)
                pending.append(dependent)

    directory_maps = [DIR2PKG, directory_to_package(base_packages)]
    all_targets = {**base_targets, **head_targets}
    affected_packages = set()
    unclassified_targets = set()
    for target in affected_targets:
        package = package_for_target(target, all_targets, directory_maps)
        if package in PKGS:
            affected_packages.add(package)
        else:
            unclassified_targets.add(target)

    # A pre-existing unclassified helper may legitimately force the conservative full suite, but a
    # brand-new target must first be assigned to a logical package in packages.toml. Otherwise it
    # could silently disappear from the package-level test matrix.
    new_targets = set(head_targets) - set(base_targets)
    new_unclassified_targets = unclassified_targets & new_targets
    if new_unclassified_targets:
        names = ", ".join(sorted(new_unclassified_targets))
        raise UnclassifiedTargetsError(
            f"new Package.swift target(s) are not classified in packages.toml: {names}"
        )
    if unclassified_targets:
        names = ", ".join(sorted(unclassified_targets))
        sys.stderr.write(f"[affected-test-matrix] manifest: affected targets outside packages.toml ({names}); running everything\n")
        return None
    return affected_packages


def affected_by_ui_test_projects(base_projects):
    head_projects = load_toml(os.path.join(ROOT, UI_TEST_PROJECTS_PATH))
    changed_projects = {
        project
        for project in set(base_projects) | set(head_projects)
        if base_projects.get(project) != head_projects.get(project)
    }
    if any(project not in PKGS for project in changed_projects):
        return None
    return changed_projects


def affected_by_package_configuration(base_packages):
    changed_packages = {
        package
        for package in set(base_packages) | set(PKGS)
        if base_packages.get(package) != PKGS.get(package)
    }
    # A package removed from the configuration has nothing left to test.
    return {package for package in changed_packages if package in PKGS}


def fhir_components_for_packages(packages):
    return {
        component
        for component, component_packages in FHIR_COMPONENT_PACKAGES.items()
        if set(packages) & component_packages
    }


def main():
    args = parse_args()
    if args.full_readiness and args.development_scope:
        sys.exit("error: --full-readiness cannot be combined with --development-scope")
    if args.fhir_only and (args.full_readiness or args.development_scope):
        sys.exit(
            "error: --fhir-only cannot be combined with --full-readiness or --development-scope"
        )
    if args.fhir_only:
        lines = [
            f'matrix={json.dumps({"include": []})}',
            f'ui_matrix={json.dumps({"include": []})}',
            'has_jobs=false',
            'has_ui_jobs=false',
            'has_fhir_conformance=true',
            f'fhir_components={",".join(sorted(ALL_FHIR_COMPONENTS))}',
            'affected=(none)',
        ]
        sys.stdout.write("\n".join(lines) + "\n")
        sys.stderr.write(
            "[affected-test-matrix] fhir_only=true affected=[] unit_jobs=0 ui_jobs=0 "
            f"fhir_components={sorted(ALL_FHIR_COMPONENTS)}\n"
        )
        return
    changed = read_changed(args.changed_files)
    development_scoped = args.development_scope is not None
    if development_scoped:
        # This is the temporary global-file override: retain direct source/test target changes and
        # ignore shared manifest, workflow, script, UI-project, and all-package test-plan fan-out.
        changed = [
            path
            for path in changed
            if path.startswith(("Sources/", "Tests/"))
            and path != UI_TEST_PROJECTS_PATH
            and not path.startswith("Tests/TestPlans/")
        ]
    run_all = False
    run_fhir_conformance = development_scoped
    affected = set(DEVELOPMENT_SCOPES.get(args.development_scope, set())) & set(PKGS)
    fhir_components = (
        set(ALL_FHIR_COMPONENTS)
        if args.development_scope == "fhir"
        else ({args.development_scope} if development_scoped else set())
    )
    shared_fhir_change = False
    # The manifest graph resolves source changes to the packages that actually consume them.
    head_dump = load_json(args.head_package_dump) if args.head_package_dump else None
    base_dump = load_json(args.base_package_dump) if args.base_package_dump else None
    development_directory_map = dict(DIR2PKG)
    if development_scoped and args.base_packages:
        # Deleted targets no longer occur in the head map. Retain their former package ownership so
        # removing a target still schedules the package that owned it at the PR base.
        for directory, package in directory_to_package(load_toml(args.base_packages)).items():
            development_directory_map.setdefault(directory, package)
    for path in changed:
        if path in FHIR_VALIDATION_PATHS:
            affected.update(FHIR_PACKAGES & set(PKGS))
            run_fhir_conformance = True
            shared_fhir_change = True
            continue
        if path in INFRASTRUCTURE_PATHS or path.startswith(INFRASTRUCTURE_PREFIXES):
            affected.update(smoke_packages())
            run_fhir_conformance |= INFRASTRUCTURE_PATHS.get(path, False)
            shared_fhir_change |= INFRASTRUCTURE_PATHS.get(path, False)
            continue
        if path in NON_TEST_SCRIPT_PATHS or path.startswith("Scripts/Tests/"):
            continue
        if path.startswith("Scripts/"):
            sys.exit(
                f"error: {path} is not classified in affected-test-matrix.py; "
                "add it to NON_TEST_SCRIPT_PATHS or INFRASTRUCTURE_PATHS"
            )
        if path.startswith(".github/"):
            # Other workflows validate their own configuration.
            continue
        if path == "__ALL__":
            run_all = True
            run_fhir_conformance = True
            fhir_components.update(ALL_FHIR_COMPONENTS)
            continue
        if path == "Package.swift" or path.startswith("Package@"):
            # A version-specific manifest is evaluated like the main one: dump-package already picks
            # the manifest that applies to the toolchain running the tests.
            if not args.base_package_dump or not args.head_package_dump:
                run_all = True
                run_fhir_conformance = True
                shared_fhir_change = True
                continue
            try:
                manifest_affected = affected_by_manifest(
                    load_json(args.base_package_dump),
                    load_json(args.head_package_dump),
                    load_toml(args.base_packages) if args.base_packages else PKGS,
                )
            except UnclassifiedTargetsError as error:
                sys.exit(f"error: {error}")
            if manifest_affected is None:
                run_all = True
                run_fhir_conformance = True
                shared_fhir_change = True
                continue
            affected.update(manifest_affected)
            run_fhir_conformance |= bool(manifest_affected & FHIR_PACKAGES)
            fhir_components.update(fhir_components_for_packages(manifest_affected))
            continue
        if path == UI_TEST_PROJECTS_PATH:
            if not args.base_ui_test_projects:
                run_all = True
                continue
            projects_affected = affected_by_ui_test_projects(load_toml(args.base_ui_test_projects))
            if projects_affected is None:
                run_all = True
                run_fhir_conformance = True
                continue
            affected.update(projects_affected)
            run_fhir_conformance |= bool(projects_affected & FHIR_PACKAGES)
            continue
        if path == "packages.toml":
            if not args.base_packages:
                run_all = True
                run_fhir_conformance = True
                shared_fhir_change = True
                continue
            configuration_affected = affected_by_package_configuration(load_toml(args.base_packages))
            if configuration_affected is None:
                run_all = True
                run_fhir_conformance = True
                shared_fhir_change = True
                continue
            affected.update(configuration_affected)
            run_fhir_conformance |= bool(configuration_affected & FHIR_PACKAGES)
            fhir_components.update(fhir_components_for_packages(configuration_affected))
            continue
        if path.startswith("Tests/TestPlans/"):
            package = os.path.splitext(os.path.basename(path))[0]
            if package in PKGS:
                affected.add(package)
                run_fhir_conformance |= package in FHIR_PACKAGES
                fhir_components.update(fhir_components_for_packages({package}))
            else:
                # The _All-<platform> plans cover multiple packages. Keep this conservative until
                # the matrix supports a platform-only all-packages selection.
                run_all = True
            continue
        parts = path.split("/")
        if len(parts) >= 2 and parts[0] in ("Sources", "Tests"):
            if parts[0] == "Sources" and any(part.endswith(".docc") for part in parts):
                continue
            # Temporary development scopes intentionally test direct target owners rather than
            # every transitive consumer. The full-readiness run restores the complete graph before
            # merge. Ordinary CI continues to resolve shared targets through the manifest graph.
            if development_scoped:
                owner = development_directory_map.get(parts[1])
                if owner is not None:
                    packages = {owner}
                else:
                    packages = (
                        direct_packages_for_target(
                            parts[1],
                            head_dump,
                            development_directory_map,
                        )
                        if head_dump
                        else None
                    )
                    if packages is None and base_dump:
                        packages = direct_packages_for_target(
                            parts[1],
                            base_dump,
                            development_directory_map,
                        )
                if packages is None:
                    sys.exit(
                        "error: temporary development scope cannot classify changed target "
                        f"{parts[1]!r}; add it to packages.toml"
                    )
                # A package removed entirely from the head has no test job left to schedule.
                packages &= set(PKGS)
            else:
                packages = packages_consuming(parts[1], head_dump) if head_dump else None
                if packages is None:
                    owner = DIR2PKG.get(parts[1])
                    packages = {owner} if owner else None
            if packages is None:
                # Neither the graph nor packages.toml knows the directory: the same conservative answer
                # the manifest path gives for a target it cannot classify.
                sys.stderr.write(f"[affected-test-matrix] {parts[0]}/{parts[1]} is unknown; running everything\n")
                run_all = True
                run_fhir_conformance = True
                shared_fhir_change = True
                continue
            affected.update(packages)
            run_fhir_conformance |= bool(packages & FHIR_PACKAGES)
            fhir_components.update(fhir_components_for_packages(packages))
        # files elsewhere (root docs, etc.) affect no package

    if run_fhir_conformance and not fhir_components:
        # A shared-only validator/model/tooling change can affect every producer. If the same PR has
        # a concrete producer change, that producer already narrows the applicable IG closure.
        if shared_fhir_change or not development_scoped:
            fhir_components.update(ALL_FHIR_COMPONENTS)

    if args.development_scope == "fhir":
        affected.intersection_update(DEVELOPMENT_SCOPES["fhir"])

    if run_all or args.full_readiness:
        affected = set(PKGS.keys())

    unit, ui = [], []
    for pkg in sorted(affected):
        info = PKGS[pkg]
        # Which test kinds run on the self-hosted runner (vs GitHub-hosted): a subset of
        # ["unit", "ui"]. Default ["ui"] keeps today's behavior (UI on self-hosted, unit on
        # GitHub-hosted). Each emitted job carries a `selfHosted` bool the workflow `runs-on` reads.
        self_hosted = info.get("self-hosted-ci", ["ui"])
        # Self-hosted runner label set for this package: base labels + any package-specific extras,
        # emitted as a JSON string the workflow's `runs-on` reads via fromJson(matrix.selfHostedLabels).
        self_hosted_labels = json.dumps(["self-hosted", "macOS"] + list(info.get("extra_runner_labels", [])))
        for platform in info["platforms"]:
            if platform in CI_PLATFORMS:
                # Linux unit jobs always use GitHub-hosted ubuntu (the self-hosted runner is macOS).
                unit.append({"package": pkg, "platform": platform,
                             "selfHosted": ("unit" in self_hosted) and platform != "Linux",
                             "selfHostedLabels": self_hosted_labels})
        for platform in info.get("uiTests", []):  # UI tests: per-project platforms from packages.toml
            if platform not in UI_PLATFORMS:
                continue
            ui.append({"package": pkg, "platform": platform, "selfHosted": "ui" in self_hosted,
                       "selfHostedLabels": self_hosted_labels})

    lines = [
        f'matrix={json.dumps({"include": unit})}',
        f'ui_matrix={json.dumps({"include": ui})}',
        f'has_jobs={"true" if unit else "false"}',
        f'has_ui_jobs={"true" if ui else "false"}',
        f'has_fhir_conformance={"true" if run_fhir_conformance else "false"}',
        f'fhir_components={",".join(sorted(fhir_components)) if fhir_components else "(none)"}',
        f'affected={",".join(sorted(affected)) if affected else "(none)"}',
    ]
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stderr.write(
        f"[affected-test-matrix] run_all={run_all} full_readiness={args.full_readiness} "
        f"development_scope={args.development_scope} "
        f"affected={sorted(affected)} unit_jobs={len(unit)} ui_jobs={len(ui)} "
        f"fhir_components={sorted(fhir_components)}\n"
    )

if __name__ == "__main__":
    main()
