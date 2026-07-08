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
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

TRAITS = {"MLX", "ResearchKit", "Textual"}


@dataclass(frozen=True)
class IOSProductBuild:
    package: str
    product: str
    deployment_target: str
    reason: str = ""

    @property
    def label(self) -> str:
        return f"{self.product} for iOS {self.deployment_target} (no optional traits)"


IOS_PRODUCT_BUILDS = [
    IOSProductBuild(
        package="SpeziChat",
        product="SpeziChat",
        deployment_target="15.0",
        reason="Textual-disabled lower-floor consumer baseline."
    ),
    IOSProductBuild(
        package="SpeziChat",
        product="SpeziChat",
        deployment_target="18.0",
        reason="Textual-disabled current deployment-target baseline."
    ),
    IOSProductBuild(
        package="SpeziLLM",
        product="SpeziLLMLocalDownload",
        deployment_target="17.0",
        reason="MLX-disabled lower-floor local LLM consumer baseline."
    ),
    IOSProductBuild(
        package="SpeziLLM",
        product="SpeziLLMLocalDownload",
        deployment_target="18.0",
        reason="MLX-disabled current deployment-target baseline."
    ),
    IOSProductBuild(
        package="ResearchKitOnFHIR",
        product="ResearchKitOnFHIR",
        deployment_target="15.0",
        reason="ResearchKit-disabled lower-floor FHIR conversion baseline."
    ),
    IOSProductBuild(
        package="ResearchKitOnFHIR",
        product="ResearchKitOnFHIR",
        deployment_target="18.0",
        reason="ResearchKit-disabled current deployment-target baseline."
    ),
    IOSProductBuild(
        package="SpeziQuestionnaire",
        product="SpeziQuestionnaire",
        deployment_target="17.0",
        reason="ResearchKit-disabled lower-floor questionnaire baseline."
    ),
    IOSProductBuild(
        package="SpeziQuestionnaire",
        product="SpeziQuestionnaire",
        deployment_target="18.0",
        reason="ResearchKit-disabled current deployment-target baseline."
    ),
]

TRAIT_PACKAGES = tuple(sorted({build.package for build in IOS_PRODUCT_BUILDS}))


class CheckFailure(Exception):
    """Raised when a package trait check fails."""


def swiftpm_environment() -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("CLANG_MODULE_CACHE_PATH", str(ROOT / ".build" / "clang-module-cache"))
    env.setdefault("TMPDIR", str(ROOT / ".build" / "tmp"))
    Path(env["CLANG_MODULE_CACHE_PATH"]).mkdir(parents=True, exist_ok=True)
    Path(env["TMPDIR"]).mkdir(parents=True, exist_ok=True)
    return env


def swift_package(arguments: list[str], *, capture_output: bool = False) -> subprocess.CompletedProcess[str]:
    swiftpm_build_paths()
    command = [
        "swift",
        "package",
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
    return subprocess.run(
        command,
        cwd=ROOT,
        env=swiftpm_environment(),
        text=True,
        stdout=subprocess.PIPE if capture_output else None,
        stderr=subprocess.PIPE if capture_output else None,
        check=False
    )


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
    process = run_checked(swift_package(["show-traits"], capture_output=True))
    listed_traits = {
        line.split(" - ", maxsplit=1)[0]
        for line in process.stdout.splitlines()
        if line.strip()
    }
    if listed_traits != TRAITS:
        raise CheckFailure(f"Expected package traits {sorted(TRAITS)}, found {sorted(listed_traits)}.")
    print(f"Verified package traits: {', '.join(sorted(listed_traits))}.", flush=True)


def build_ios_product(arguments: list[str], build: IOSProductBuild) -> None:
    print(f"Building {build.label}: {build.reason}", flush=True)
    run_checked(swift_build(arguments))


def swift_build_arguments(build: IOSProductBuild, sdk_path: str) -> list[str]:
    arguments = [
        "--triple",
        f"arm64-apple-ios{build.deployment_target}-simulator",
        "--sdk",
        sdk_path,
        "--disable-default-traits"
    ]
    return arguments


def check_ios_builds(packages: set[str]) -> None:
    sdk_path = find_ios_simulator_sdk()
    print(f"Using iPhone Simulator SDK: {sdk_path}", flush=True)

    for build in IOS_PRODUCT_BUILDS:
        if build.package not in packages:
            continue
        arguments = swift_build_arguments(build, sdk_path)
        arguments.extend(["--target", build.product])
        build_ios_product(arguments, build)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Only validate that the expected SwiftPM traits are present."
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
            check_ios_builds(set(arguments.packages))
    except CheckFailure as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print("Package trait build checks passed.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
