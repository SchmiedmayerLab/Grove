#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
"""Compile every supported library at its deployment floor, without running tests.

Build the top-level library products together in a CI-only aggregate, then verify
that every supported module was compiled. The normal test jobs use current OS
deployment targets, so they cannot catch missing availability annotations here.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

if sys.version_info < (3, 11):
    sys.exit("error: this script requires Python 3.11+ (uses tomllib)")

import tomllib

from build_support import run_build, run_cli, run_command


# Existing platform limitations, independent of the deployment floor. The
# XCUIApplication authorization helper has only iOS/visionOS branches and leaves
# a bodyless -> Bool method on macOS/watchOS. Keep exceptions small and justified.
FLOOR_SKIP = {
    ("XCTGroveNotifications", "macOS"),
    ("XCTGroveNotifications", "watchOS"),
}


def dependency_edge(dependency):
    """Return (kind, name, condition) for a manifest dependency entry."""
    for kind in ("target", "byName"):
        if dependency.get(kind):
            entry = dependency[kind]
            return kind, entry[0], entry[1] if len(entry) > 1 else None
    if dependency.get("product"):
        entry = dependency["product"]
        return "product", entry[0], entry[3] if len(entry) > 3 else None
    return None, None, None


def condition_active(condition, platform):
    # Every package trait is disabled for floor builds. Platform conditions are
    # active only on their listed platforms.
    if not condition:
        return True
    if condition.get("traits"):
        return False
    platforms = condition.get("platformNames")
    return not platforms or platform.lower() in platforms


def select_products(manifest, packages, platform):
    """Return the top-level library products and all supported module names.

    The manifest supplies the dependency graph, and packages.toml supplies the
    curated platform support. Selection follows package and dependency changes
    without keeping a separate list of packages in this script.
    """
    library_products = {
        product["name"]: product["targets"]
        for product in manifest["products"] if "library" in product["type"]
    }
    targets = {target["name"]: target for target in manifest["targets"]}

    def dependency_targets(target):
        dependencies = set()
        for dependency in target.get("dependencies", []):
            kind, name, condition = dependency_edge(dependency)
            if kind in ("target", "byName") and name in targets and condition_active(condition, platform):
                dependencies.add(name)
        return dependencies

    # By repository convention, an external product with a platform-only
    # condition is a hard requirement: its consumer cannot compile where that
    # dependency is absent (for example, FHIRModels on lowered watchOS).
    # Trait-conditioned edges do not count: consumers are source-gated and
    # compile to empty without their trait. Propagate unsupportedness through
    # active local edges, exactly as for the normal package graph.
    unsupported = set()
    for name, target in targets.items():
        for dependency in target.get("dependencies", []):
            kind, _, condition = dependency_edge(dependency)
            if kind == "product" and condition and not condition.get("traits"):
                platforms = condition.get("platformNames")
                if platforms and platform.lower() not in platforms:
                    unsupported.add(name)
                    break
    changed = True
    while changed:
        changed = False
        for name, target in targets.items():
            if name not in unsupported and any(dependency in unsupported for dependency in dependency_targets(target)):
                unsupported.add(name)
                changed = True

    package_platforms, target_packages = {}, {}
    for package, info in packages.items():
        if not isinstance(info, dict) or "platforms" not in info:
            continue
        package_platforms[package] = set(info["platforms"])
        for target in info.get("targets", []):
            target_packages[target] = package

    def supports(product):
        modules = library_products[product]
        if any(module in unsupported for module in modules):
            return False
        # A product is supported if an owning package supports this platform,
        # or all its targets are unowned core targets (supported everywhere).
        if any(platform in package_platforms.get(target_packages[module], ())
               for module in modules if target_packages.get(module)):
            return True
        return all(target_packages.get(module) is None for module in modules)

    supported = [product for product in library_products if supports(product)]
    supported_targets = {module for product in supported for module in library_products[product]}
    depended = {
        dependency
        for name in supported_targets if name in targets
        for dependency in dependency_targets(targets[name]) if dependency in supported_targets
    }
    top_level = sorted(
        product for product in supported
        if not any(module in depended for module in library_products[product])
    )
    modules = sorted(module for module in supported_targets if module not in unsupported)
    return top_level, modules


def destination_for(platform, kind):
    if platform == "macOS":
        return "platform=macOS,arch=arm64"
    if platform in ("iOS", "watchOS") and kind in ("device", "simulator"):
        return f"generic/platform={platform}" + (" Simulator" if kind == "simulator" else "")
    return None


def main():
    if len(sys.argv) < 2 or not sys.argv[1]:
        print("usage: build-floor.py <iOS|macOS|watchOS> <device|simulator>", file=sys.stderr)
        return 1
    platform = sys.argv[1]
    kind = (sys.argv[2] if len(sys.argv) > 2 else "") or "simulator"
    destination = destination_for(platform, kind)
    if destination is None:
        print(f"unknown platform/kind: {platform}:{kind}", file=sys.stderr)
        return 2
    os.chdir(Path(__file__).resolve().parent.parent)

    environment = os.environ.copy()
    environment["PWD"] = str(Path.cwd())
    environment["GROVE_LOWERED_DEPLOYMENT_TARGETS"] = "1"
    environment["GROVE_EXCLUDE_DOCC_CATALOGS"] = "1"
    environment.pop("GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS", None)
    # Inspect the normal products before adding the CI-only aggregate.
    environment.pop("GROVE_FLOOR_BUILD_TARGETS", None)

    # Keep every run's output fresh for the coverage assertion, and retain it
    # for inspection until the normal runner/local cleanup removes it.
    output_root = Path(environment.get("RUNNER_TEMP") or Path.cwd() / ".derivedData")
    output_root.mkdir(parents=True, exist_ok=True)
    derived_data = Path(tempfile.mkdtemp(prefix=f"floor-{platform}-{kind}.", dir=output_root))
    manifest_path = derived_data / "package.json"
    with manifest_path.open("w") as output:
        status = run_command(
            ["swift", "package", "dump-package"], env=environment, stdout=output, stderr=subprocess.DEVNULL,
        )
    if status:
        # Retry once with diagnostics visible, truncating the first attempt.
        with manifest_path.open("w") as output:
            status = run_command(["swift", "package", "dump-package"], env=environment, stdout=output)
        if status:
            return status
    with manifest_path.open() as source:
        manifest = json.load(source)
    versions = [entry["version"] for entry in manifest["platforms"] if entry["platformName"] == platform.lower()]
    if len(versions) != 1:
        print(f"error: expected one explicit deployment floor for {platform}", file=sys.stderr)
        return 1
    with Path("packages.toml").open("rb") as source:
        packages = tomllib.load(source)
    top_level, modules = select_products(manifest, packages, platform)

    print(f"==> {platform} {versions[0]} ({kind}) — {len(top_level)} top-level products cover {len(modules)} modules")
    print(f"    destination: {destination}")
    build_products, skipped_products = [], []
    for product in top_level:
        if (product, platform) in FLOOR_SKIP:
            print(f"==> SKIP {product} (pre-existing {platform} limitation — does not build on main either)")
            skipped_products.append(product)
        else:
            build_products.append(product)

    # Products may contain several targets and need not share their names.
    product_targets = {product["name"]: product["targets"] for product in manifest["products"]}
    build_targets = sorted({target for product in build_products for target in product_targets[product]})
    if not build_targets:
        print("error: no deployment-floor targets selected", file=sys.stderr)
        return 1
    environment["GROVE_FLOOR_BUILD_TARGETS"] = ",".join(build_targets)
    command = [
        "xcodebuild", "build",
        "-scheme", "GroveDeploymentFloor",
        "-destination", destination,
        "-configuration", "Debug",
        "-derivedDataPath", str(derived_data),
        "-skipMacroValidation", "-skipPackagePluginValidation",
        # Skip Intel host tools without restricting watchOS device arm64_32.
        "EXCLUDED_ARCHS=x86_64",
    ]
    if kind == "simulator" and platform != "macOS":
        command.append("ARCHS=arm64")
    print(f"==> build {len(build_products)} products together: {' '.join(build_products)}", flush=True)
    failed = run_build(command, env=environment) != 0

    # Every supported module must exist in this run's build output, even if
    # Xcode returned success. Apply the existing platform exceptions here too.
    built_modules = {
        path.stem for path in (derived_data / "Build").rglob("*.swiftmodule")
        if path.is_dir() and not path.is_symlink()
    }
    missing = [module for module in modules if (module, platform) not in FLOOR_SKIP and module not in built_modules]
    print()
    print(f"===================== floor build-check summary: {platform} ({kind}) =====================")
    print(f"built modules: {len(built_modules)}   expected-supported: {len(modules)}")
    if skipped_products:
        print(f"skipped (pre-existing {platform} limitations): {' '.join(skipped_products)}")
    if failed:
        print(f"::error::floor build FAILED for {platform} ({kind})")
    if missing:
        print(f"::error::coverage gap — supported modules never built: {' '.join(missing)}")
    if failed or missing:
        return 1
    print(f"OK — all {len(modules)} {platform} modules compile at the deployment floor.")
    return 0


if __name__ == "__main__":
    run_cli(main)
