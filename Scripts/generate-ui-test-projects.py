#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
"""Generate all UITests.xcodeproj files from the canonical Grove reference project."""

from __future__ import annotations

import sys

# tomllib needs Python 3.11+; checking the version (rather than try-importing) also lets Pylance
# mark the rest of the file unreachable instead of flagging the import when an older interpreter is selected.
if sys.version_info < (3, 11):
    sys.exit("error: this script requires Python 3.11+ (uses tomllib)")

import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re
import tomllib


ROOT = Path(__file__).resolve().parent.parent
PROJECTS_FILE = ROOT / "Tests" / "UITestProjects.toml"
PACKAGES_FILE = ROOT / "packages.toml"
TEMPLATE = ROOT / "Tests" / "GroveTests" / "UITests" / "UITests.xcodeproj" / "project.pbxproj"

LOCAL_PACKAGE_ID = "654293E43002D0F400AF6915"
APP_TARGET_ID = "000000000000000100000000"
TEST_TARGET_ID = "656490953002CEA900F1D55F"
APP_FRAMEWORKS_ID = "000000000000000130000000"
TEST_FRAMEWORKS_ID = "656490933002CEA900F1D55F"
APP_GROUP_ID = "000000000000000000000010"
TEST_GROUP_ID = "656490973002CEA900F1D55F"
APP_CONFIG_IDS = ("000000000000000111000000", "000000000000000112000000")
TEST_CONFIG_IDS = ("6564909C3002CEA900F1D55F", "6564909D3002CEA900F1D55F")
IMPORT_PATTERN = re.compile(
    r"^(?:(?:public|package|internal|private|fileprivate)\s+)?"
    r"(?:(?:@testable|@_spi\([^)]*\))\s+)?"
    r"import\s+(?:(?:class|struct|enum|protocol|func|var|typealias)\s+)?([A-Za-z_]\w*)",
    re.MULTILINE,
)


def stable_id(*parts: str) -> str:
    return hashlib.sha1("\0".join(parts).encode()).hexdigest()[:24].upper()


def quoted(value: str) -> str:
    return json.dumps(value)


def replace_section(text: str, name: str, body: str) -> str:
    pattern = rf"(/\* Begin {re.escape(name)} section \*/\n).*?(\n/\* End {re.escape(name)} section \*/)"
    replacement = rf"\g<1>{body}\g<2>"
    result, count = re.subn(pattern, replacement, text, count=1, flags=re.DOTALL)
    if count != 1:
        raise ValueError(f"Could not replace {name} section")
    return result


def object_range(text: str, object_id: str) -> tuple[int, int]:
    start = text.index(f"\t\t{object_id} /*")
    end = text.index("\n\t\t};", start) + len("\n\t\t};")
    return start, end


def replace_object_list(text: str, object_id: str, key: str, entries: list[str]) -> str:
    start, end = object_range(text, object_id)
    block = text[start:end]
    pattern = rf"(\t\t\t{re.escape(key)} = \(\n).*?(\t\t\t\);)"
    body = "".join(f"\t\t\t\t{entry}\n" for entry in entries)
    block, count = re.subn(pattern, rf"\g<1>{body}\g<2>", block, count=1, flags=re.DOTALL)
    if count != 1:
        raise ValueError(f"Could not replace {key} in object {object_id}")
    return text[:start] + block + text[end:]


def modify_configuration(text: str, config_id: str, settings: dict[str, str], platforms: list[str]) -> str:
    start, end = object_range(text, config_id)
    block = text[start:end]
    supported = []
    families = []
    if "iOS" in platforms or "iPadOS" in platforms:
        supported += ["iphoneos", "iphonesimulator"]
    if "visionOS" in platforms:
        supported += ["xros", "xrsimulator"]
    if "iOS" in platforms:
        families.append("1")
    if "iPadOS" in platforms:
        families.append("2")
    if "visionOS" in platforms:
        families.append("7")

    block = re.sub(
        r'SUPPORTED_PLATFORMS = "[^"]+";',
        f'SUPPORTED_PLATFORMS = "{" ".join(supported)}";',
        block,
    )
    block = re.sub(
        r'TARGETED_DEVICE_FAMILY = "[^"]+";',
        f'TARGETED_DEVICE_FAMILY = "{",".join(families)}";',
        block,
    )
    if "visionOS" not in platforms:
        block = re.sub(r"^\t\t\t\tXROS_DEPLOYMENT_TARGET = 2\.6;\n", "", block, flags=re.MULTILINE)

    if settings:
        marker = "\t\t\tbuildSettings = {\n"
        for key in settings:
            block = re.sub(rf"^\t\t\t\t{re.escape(key)} = .*;\n", "", block, flags=re.MULTILINE)
        rendered = "".join(f"\t\t\t\t{key} = {quoted(str(value))};\n" for key, value in sorted(settings.items()))
        block = block.replace(marker, marker + rendered, 1)
    return text[:start] + block + text[end:]


def add_membership_exception(text: str, package: str, target: str, info_plist: str) -> str:
    target_id = APP_TARGET_ID if target == "TestApp" else TEST_TARGET_ID
    group_id = APP_GROUP_ID if target == "TestApp" else TEST_GROUP_ID
    exception_id = stable_id(package, target, "membership-exceptions")
    prefix = f"{target}/"
    if not info_plist.startswith(prefix):
        raise ValueError(f"{package}: {info_plist} must be inside {target}")
    membership_path = info_plist[len(prefix):]
    exception = (
        "/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */\n"
        f"\t\t{exception_id} /* Exceptions for {target} folder in {target} target */ = {{\n"
        "\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n"
        "\t\t\tmembershipExceptions = (\n"
        f"\t\t\t\t{quoted(membership_path)},\n"
        "\t\t\t);\n"
        f"\t\t\ttarget = {target_id} /* {target} */;\n"
        "\t\t};\n"
        "/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */\n\n"
    )
    text = text.replace("/* Begin PBXFileSystemSynchronizedRootGroup section */", exception + "/* Begin PBXFileSystemSynchronizedRootGroup section */", 1)

    start, end = object_range(text, group_id)
    block = text[start:end]
    marker = "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
    exceptions = f"\t\t\texceptions = (\n\t\t\t\t{exception_id} /* Exceptions for {target} folder in {target} target */,\n\t\t\t);\n"
    block = block.replace(marker, marker + exceptions, 1)
    return text[:start] + block + text[end:]


def requirement(remote: dict[str, object]) -> str:
    lines = [f"\t\t\t\tkind = {remote['kind']};"]
    for manifest_key, xcode_key in (
        ("minimum_version", "minimumVersion"),
        ("version", "version"),
        ("branch", "branch"),
        ("revision", "revision"),
    ):
        if manifest_key in remote:
            lines.append(f"\t\t\t\t{xcode_key} = {remote[manifest_key]};")
    return "\n".join(lines)


def imported_modules(package: str, target: str) -> set[str]:
    folder = ROOT / "Tests" / f"{package}Tests" / "UITests" / target
    return {
        module
        for source in folder.rglob("*.swift")
        for module in IMPORT_PATTERN.findall(source.read_text())
    }


def render_project(package: str, spec: dict[str, object], platforms: list[str], template: str) -> str:
    text = template
    # Target-specific capabilities belong to the manifest, not the canonical base.
    text = re.sub(r"^\t\t\t\t(?:CODE_SIGN_ENTITLEMENTS|INFOPLIST_FILE) = .*;\n", "", text, flags=re.MULTILINE)

    remotes = spec.get("remote_packages", [])
    remote_by_product: dict[str, tuple[str, dict[str, object]]] = {}
    remote_ids: list[tuple[str, dict[str, object]]] = []
    for remote in remotes:
        remote_id = stable_id(package, str(remote["url"]), "package")
        remote_ids.append((remote_id, remote))
        for product in remote.get("products", []):
            remote_by_product[str(product)] = (remote_id, remote)

    products: dict[str, list[tuple[str, str, str]]] = {"TestApp": [], "TestAppUITests": []}
    for target, key, fixture_key in (
        ("TestApp", "app_products", "app_fixture_products"),
        ("TestAppUITests", "test_products", "test_fixture_products"),
    ):
        for product in [*spec.get(key, []), *spec.get(fixture_key, [])]:
            product = str(product)
            dependency_id = stable_id(package, target, product, "dependency")
            build_file_id = stable_id(package, target, product, "build-file")
            products[target].append((product, dependency_id, build_file_id))

    build_files = []
    for target_products in products.values():
        for product, dependency_id, build_file_id in target_products:
            build_files.append(
                f"\t\t{build_file_id} /* {product} in Frameworks */ = "
                f"{{isa = PBXBuildFile; productRef = {dependency_id} /* {product} */; }};"
            )
    text = replace_section(text, "PBXBuildFile", "\n".join(build_files))

    for target, object_id in (("TestApp", APP_FRAMEWORKS_ID), ("TestAppUITests", TEST_FRAMEWORKS_ID)):
        entries = [f"{build_id} /* {product} in Frameworks */," for product, _, build_id in products[target]]
        text = replace_object_list(text, object_id, "files", entries)

    for target, object_id in (("TestApp", APP_TARGET_ID), ("TestAppUITests", TEST_TARGET_ID)):
        entries = [f"{dependency_id} /* {product} */," for product, dependency_id, _ in products[target]]
        text = replace_object_list(text, object_id, "packageProductDependencies", entries)

    app_plugins = [str(plugin) for plugin in spec.get("app_plugins", [])]
    plugin_dependencies = []
    plugin_products = []
    for plugin in app_plugins:
        if plugin not in remote_by_product:
            raise ValueError(f"{package}: plugin {plugin} must be declared by a remote package")
        product_id = stable_id(package, "TestApp", plugin, "plugin-product")
        dependency_id = stable_id(package, "TestApp", plugin, "plugin-dependency")
        remote_id = remote_by_product[plugin][0]
        plugin_dependencies.append(f"{dependency_id} /* PBXTargetDependency */,")
        plugin_products.append((plugin, product_id, dependency_id, remote_id))

    if plugin_dependencies:
        start, end = object_range(text, APP_TARGET_ID)
        block = text[start:end]
        marker = "\t\t\tbuildRules = (\n\t\t\t);\n"
        dependencies = "\t\t\tdependencies = (\n" + "".join(
            f"\t\t\t\t{entry}\n" for entry in plugin_dependencies
        ) + "\t\t\t);\n"
        block = block.replace(marker, marker + dependencies, 1)
        text = text[:start] + block + text[end:]

        target_dependencies = "\n".join(
            f"\t\t{dependency_id} /* PBXTargetDependency */ = {{\n"
            "\t\t\tisa = PBXTargetDependency;\n"
            f"\t\t\tproductRef = {product_id} /* {plugin} */;\n"
            "\t\t};"
            for plugin, product_id, dependency_id, _ in plugin_products
        )
        text = text.replace(
            "/* End PBXTargetDependency section */",
            target_dependencies + "\n/* End PBXTargetDependency section */",
            1,
        )

    package_entries = [f'{LOCAL_PACKAGE_ID} /* XCLocalSwiftPackageReference "../../.." */,']
    package_entries += [f'{remote_id} /* XCRemoteSwiftPackageReference "{remote["url"]}" */,' for remote_id, remote in remote_ids]
    # packageReferences is nested in PBXProject, whose TargetAttributes dictionary contains other objects;
    # replace the uniquely named list directly rather than using object_range.
    package_body = "".join(f"\t\t\t\t{entry}\n" for entry in package_entries)
    text, count = re.subn(
        r"(\t\t\tpackageReferences = \(\n).*?(\t\t\t\);)",
        rf"\g<1>{package_body}\g<2>",
        text,
        count=1,
        flags=re.DOTALL,
    )
    if count != 1:
        raise ValueError("Could not replace PBXProject packageReferences")

    # Traits declared in the spec are enabled on the monorepo package reference.
    # NEVER include the `default` pseudo-trait here: combining it with a named trait makes
    # xcodebuild (Xcode 26.5/26.6) crash with an IDESwiftPackageCore sortedInsert exception during
    # package resolution. Note that Xcode's GUI trait toggle WRITES `(X, default)` — after any GUI
    # edit, regenerate so the committed form stays `default`-free. An explicit list replaces the
    # default set, which is fine: these TestApps need exactly the listed traits (CI's
    # GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS=1 only affects trait-less projects).
    traits = [str(trait) for trait in spec.get("traits", [])]
    if "default" in traits:
        raise ValueError(f"{package}: the `default` pseudo-trait must not be listed (crashes xcodebuild)")
    if traits:
        marker = "\t\t\trelativePath = ../../..;\n"
        if text.count(marker) != 1:
            raise ValueError(f"{package}: could not locate the local package reference to attach traits")
        rendered = "".join(f"\t\t\t\t{trait},\n" for trait in traits)
        text = text.replace(marker, f"{marker}\t\t\ttraits = (\n{rendered}\t\t\t);\n", 1)

    remote_section = ""
    if remote_ids:
        remote_objects = []
        for remote_id, remote in remote_ids:
            remote_objects.append(
                f'\t\t{remote_id} /* XCRemoteSwiftPackageReference "{remote["url"]}" */ = {{\n'
                "\t\t\tisa = XCRemoteSwiftPackageReference;\n"
                f'\t\t\trepositoryURL = {quoted(str(remote["url"]))};\n'
                "\t\t\trequirement = {\n"
                f"{requirement(remote)}\n"
                "\t\t\t};\n"
                "\t\t};"
            )
        remote_section = (
            "/* Begin XCRemoteSwiftPackageReference section */\n"
            + "\n".join(remote_objects)
            + "\n/* End XCRemoteSwiftPackageReference section */\n\n"
        )
    text = re.sub(
        r"(?:/\* Begin XCRemoteSwiftPackageReference section \*/.*?/\* End XCRemoteSwiftPackageReference section \*/\n\n)?"
        r"(?=/\* Begin XCSwiftPackageProductDependency section \*/)",
        remote_section,
        text,
        count=1,
        flags=re.DOTALL,
    )

    dependency_objects = []
    for target_products in products.values():
        for product, dependency_id, _ in target_products:
            package_id = remote_by_product.get(product, (LOCAL_PACKAGE_ID, {}))[0]
            dependency_objects.append(
                f"\t\t{dependency_id} /* {product} */ = {{\n"
                "\t\t\tisa = XCSwiftPackageProductDependency;\n"
                f"\t\t\tpackage = {package_id} /* package */;\n"
                f"\t\t\tproductName = {product};\n"
                "\t\t};"
            )
    for plugin, product_id, _, remote_id in plugin_products:
        dependency_objects.append(
            f"\t\t{product_id} /* {plugin} */ = {{\n"
            "\t\t\tisa = XCSwiftPackageProductDependency;\n"
            f"\t\t\tpackage = {remote_id} /* package */;\n"
            f"\t\t\tproductName = {quoted(f'plugin:{plugin}')};\n"
            "\t\t};"
        )
    text = replace_section(text, "XCSwiftPackageProductDependency", "\n".join(dependency_objects))

    app_settings = {str(key): str(value) for key, value in spec.get("app_settings", {}).items()}
    test_settings = {str(key): str(value) for key, value in spec.get("test_settings", {}).items()}
    bundle_identifier = f"edu.stanford.spezi.{package.lower()}"
    app_settings.setdefault("PRODUCT_BUNDLE_IDENTIFIER", f"{bundle_identifier}.testapp")
    test_settings.setdefault("PRODUCT_BUNDLE_IDENTIFIER", f"{bundle_identifier}.testapp.uitests")
    for target, settings in (("TestApp", app_settings), ("TestAppUITests", test_settings)):
        if "INFOPLIST_FILE" in settings:
            text = add_membership_exception(text, package, target, settings["INFOPLIST_FILE"])
    for config_id in APP_CONFIG_IDS:
        text = modify_configuration(text, config_id, app_settings, platforms)
    for config_id in TEST_CONFIG_IDS:
        text = modify_configuration(text, config_id, test_settings, platforms)
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if any project differs from generated output")
    parser.add_argument("--package", action="append", help="Generate/check only the named logical package")
    args = parser.parse_args()

    with PROJECTS_FILE.open("rb") as file:
        project_specs = tomllib.load(file)
    with PACKAGES_FILE.open("rb") as file:
        packages = tomllib.load(file)

    for package, spec in project_specs.items():
        for target, key, fixture_key in (
            ("TestApp", "app_products", "app_fixture_products"),
            ("TestAppUITests", "test_products", "test_fixture_products"),
        ):
            direct_products = set(spec.get(key, []))
            fixture_products = set(spec.get(fixture_key, []))
            if overlap := direct_products & fixture_products:
                raise SystemExit(
                    f"{package}.{target}: products declared as both direct and fixtures: {sorted(overlap)}"
                )
            if unused := direct_products - imported_modules(package, target):
                raise SystemExit(
                    f"{package}.{target}: products without a matching source import: {sorted(unused)}; "
                    f"remove them or declare intentional runtime dependencies in {fixture_key}"
                )

    declared_ui = {name for name, info in packages.items() if info.get("uiTests")}
    if set(project_specs) != declared_ui:
        missing_specs = sorted(declared_ui - set(project_specs))
        missing_declarations = sorted(set(project_specs) - declared_ui)
        raise SystemExit(
            f"UITestProjects.toml/packages.toml mismatch; missing specs={missing_specs}, "
            f"missing uiTests declarations={missing_declarations}"
        )

    selected = set(args.package or project_specs)
    unknown = selected - set(project_specs)
    if unknown:
        raise SystemExit(f"Unknown UI-test packages: {sorted(unknown)}")

    template = TEMPLATE.read_text()
    failures = []
    for package in sorted(selected):
        project = ROOT / "Tests" / f"{package}Tests" / "UITests" / "UITests.xcodeproj" / "project.pbxproj"
        generated = render_project(package, project_specs[package], packages[package]["uiTests"], template)
        if args.check:
            actual = project.read_text()
            if actual != generated:
                failures.append(package)
                sys.stdout.writelines(
                    difflib.unified_diff(
                        actual.splitlines(keepends=True),
                        generated.splitlines(keepends=True),
                        fromfile=str(project.relative_to(ROOT)),
                        tofile=f"generated/{project.relative_to(ROOT)}",
                        n=2,
                    )
                )
        else:
            project.write_text(generated)
            print(f"Generated {project.relative_to(ROOT)}")

    if failures:
        print(f"UI-test projects out of date: {', '.join(failures)}", file=sys.stderr)
        return 1
    if args.check:
        print(f"All {len(selected)} UI-test projects match the canonical template.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
