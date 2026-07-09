#!/usr/bin/env python3
#
# This source file is part of the Stanford Spezi open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
"""Build trait-sensitive products with optional package traits disabled."""

import argparse
import os
import re
import subprocess
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

TRAITS = {"MLX", "ResearchKit", "Textual"}


@dataclass(frozen=True)
class TraitProductBuild:
    package: str
    product: str
    platform: str
    deployment_target: str
    reason: str = ""

    @property
    def label(self) -> str:
        return f"{self.product} for {self.platform} {self.deployment_target} (no optional traits)"


def load_trait_product_builds() -> tuple[TraitProductBuild, ...]:
    with (ROOT / "packages.toml").open("rb") as file:
        packages = tomllib.load(file)

    builds = []
    for package, info in packages.items():
        for build in info.get("traitBuilds", []):
            builds.append(TraitProductBuild(
                package=package,
                product=build["product"],
                platform=build["platform"],
                deployment_target=build["deploymentTarget"],
                reason=build.get("reason", "")
            ))
    return tuple(builds)


TRAIT_PRODUCT_BUILDS = load_trait_product_builds()
TRAIT_PACKAGES = tuple(sorted({build.package for build in TRAIT_PRODUCT_BUILDS}))


class CheckFailure(Exception):
    """Raised when a package trait check fails."""


def swiftpm_environment() -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("CLANG_MODULE_CACHE_PATH", str(ROOT / ".build" / "clang-module-cache"))
    env.setdefault("TMPDIR", str(ROOT / ".build" / "tmp"))
    env.setdefault("SPEZI_EXCLUDE_DOCC_CATALOGS", "1")
    Path(env["CLANG_MODULE_CACHE_PATH"]).mkdir(parents=True, exist_ok=True)
    Path(env["TMPDIR"]).mkdir(parents=True, exist_ok=True)
    return env


def swift_build(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    swiftpm_build_paths()
    command = [
        "swift",
        "build",
        "--disable-sandbox",
        "--cache-path",
        str(ROOT / ".build" / "swiftpm-cache"),
        "--config-path",
        str(ROOT / ".build" / "swiftpm-config"),
        "--security-path",
        str(ROOT / ".build" / "swiftpm-security"),
        "--manifest-cache",
        "local",
        *arguments
    ]
    print(f"==> {' '.join(command)}", flush=True)
    return subprocess.run(command, cwd=ROOT, env=swiftpm_environment(), text=True, check=False)


def swiftpm_build_paths() -> None:
    for path in (
        ROOT / ".build" / "swiftpm-cache",
        ROOT / ".build" / "swiftpm-config",
        ROOT / ".build" / "swiftpm-security"
    ):
        path.mkdir(parents=True, exist_ok=True)


def run_checked(process: subprocess.CompletedProcess[str]) -> subprocess.CompletedProcess[str]:
    if process.returncode == 0:
        return process

    if process.stdout:
        print(process.stdout, file=sys.stdout)
    if process.stderr:
        print(process.stderr, file=sys.stderr)
    raise CheckFailure(f"Command failed with exit code {process.returncode}.")


def find_ios_simulator_sdk() -> str:
    process = subprocess.run(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"],
        cwd=ROOT,
        env=swiftpm_environment(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False
    )
    if process.returncode != 0:
        if process.stderr:
            print(process.stderr, file=sys.stderr)
        raise CheckFailure("Unable to locate the iPhone Simulator SDK with xcrun.")

    sdk_path = process.stdout.strip()
    if not sdk_path:
        raise CheckFailure("xcrun returned an empty iPhone Simulator SDK path.")
    return sdk_path


def check_trait_listing() -> None:
    manifest = (ROOT / "Package.swift").read_text(encoding="utf-8")
    trait_constants = dict(re.findall(
        r"let\s+([A-Za-z_][A-Za-z0-9_]*Trait)\s*=\s*\"([^\"]+)\"",
        manifest
    ))
    trait_name_variables = re.findall(
        r"\.trait\(\s*name:\s*([A-Za-z_][A-Za-z0-9_]*)",
        manifest
    )
    literal_trait_names = re.findall(r"\.trait\(\s*name:\s*\"([^\"]+)\"", manifest)
    unresolved_trait_names = [name for name in trait_name_variables if name not in trait_constants]
    if unresolved_trait_names:
        raise CheckFailure(f"Unable to resolve package trait names: {', '.join(unresolved_trait_names)}.")

    listed_traits = set(literal_trait_names) | {trait_constants[name] for name in trait_name_variables}
    if listed_traits != TRAITS:
        raise CheckFailure(f"Expected package traits {sorted(TRAITS)}, found {sorted(listed_traits)}.")
    print(f"Verified package trait declarations: {', '.join(sorted(listed_traits))}.", flush=True)


def build_ios_product(arguments: list[str], build: TraitProductBuild) -> None:
    print(f"Building {build.label}: {build.reason}", flush=True)
    run_checked(swift_build(arguments))


def swift_build_arguments(build: TraitProductBuild, sdk_path: str) -> list[str]:
    if build.platform != "iOS":
        raise CheckFailure(f"Unsupported package trait build platform: {build.platform}.")

    arguments = [
        "--triple",
        f"arm64-apple-ios{build.deployment_target}-simulator",
        "--sdk",
        sdk_path,
        "--disable-default-traits"
    ]
    return arguments


def check_ios_builds(builds: list[TraitProductBuild]) -> None:
    sdk_path = find_ios_simulator_sdk()
    print(f"Using iPhone Simulator SDK: {sdk_path}", flush=True)

    for build in builds:
        arguments = swift_build_arguments(build, sdk_path)
        arguments.extend(["--target", build.product])
        build_ios_product(arguments, build)


def selected_builds(arguments: argparse.Namespace) -> list[TraitProductBuild]:
    builds = [
        build
        for build in TRAIT_PRODUCT_BUILDS
        if build.package in set(arguments.packages)
    ]
    if arguments.product:
        builds = [build for build in builds if build.product == arguments.product]
    if arguments.platform:
        builds = [build for build in builds if build.platform == arguments.platform]
    if arguments.deployment_target:
        builds = [build for build in builds if build.deployment_target == arguments.deployment_target]

    if not builds:
        raise CheckFailure("No package trait build matches the requested filters.")
    return builds


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Only validate that the expected SwiftPM traits are present."
    )
    parser.add_argument(
        "--product",
        help="Only build this trait-sensitive Swift target."
    )
    parser.add_argument(
        "--platform",
        choices=("iOS",),
        help="Only build this platform."
    )
    parser.add_argument(
        "--deployment-target",
        help="Only build this deployment target."
    )
    parser.add_argument(
        "packages",
        nargs="*",
        choices=TRAIT_PACKAGES,
        default=TRAIT_PACKAGES,
        metavar="PACKAGE",
        help="Trait-owning package to build. Defaults to all packages."
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        check_trait_listing()
        if not arguments.skip_build:
            check_ios_builds(selected_builds(arguments))
    except CheckFailure as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print("Package trait build checks passed.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
