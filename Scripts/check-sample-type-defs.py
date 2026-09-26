#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

"""Cross-check GroveHealthKit SampleType definitions against the HealthKit SDK.

Parses ``SampleTypeDefs.py`` (and the characteristic list in ``SampleTypes.swift.gyb``) and
compares identifiers to Apple's ``HKTypeIdentifiers.h`` / ``HKClinicalType.h`` from the active
iPhoneOS SDK. The check never writes or auto-generates Grove definitions: when Apple adds a type,
hand-author the entry in ``SampleTypeDefs.py`` (canonical title, units, docs) and regenerate with
``./useGYB``.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parent.parent
DEFS_PATH = ROOT / "Sources" / "GroveHealthKit" / "Sample Types" / "SampleTypeDefs.py"
GYB_PATH = ROOT / "Sources" / "GroveHealthKit" / "Sample Types" / "SampleTypes.swift.gyb"

# HealthKit Objective-C constant suffixes whose Swift member names are not simple lowerFirstCamel.
SWIFT_MEMBER_SPECIALS = {
    "VO2Max": "vo2Max",
    "UVExposure": "uvExposure",
}

# SampleType API surface floor (mirrors SAMPLE_TYPE_AVAILABILITY in SampleTypeDefs.py).
SAMPLE_TYPE_IOS_FLOOR = (18, 0)

FAMILY_PREFIXES = {
    "quantity": "HKQuantityTypeIdentifier",
    "category": "HKCategoryTypeIdentifier",
    "correlation": "HKCorrelationTypeIdentifier",
    "clinical": "HKClinicalTypeIdentifier",
    "characteristic": "HKCharacteristicTypeIdentifier",
}

OTHER_SYMBOL_FALLBACKS = {
    "electrocardiogram": "electrocardiogramType",
    "audiogram": "audiogramSampleType",
}


@dataclass(frozen=True)
class Version:
    parts: tuple[int, ...]

    @classmethod
    def parse(cls, text: str) -> Version:
        text = text.strip().strip('"').strip("'")
        if text.startswith(".v"):
            text = text[2:]
        parts = tuple(int(part) for part in text.split(".") if part != "")
        if not parts:
            raise ValueError(f"empty version: {text!r}")
        return cls(parts)

    def padded(self, width: int) -> tuple[int, ...]:
        return self.parts + (0,) * (width - len(self.parts))

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Version):
            return NotImplemented
        width = max(len(self.parts), len(other.parts))
        return self.padded(width) == other.padded(width)

    def __lt__(self, other: Version) -> bool:
        width = max(len(self.parts), len(other.parts))
        return self.padded(width) < other.padded(width)

    def __le__(self, other: Version) -> bool:
        return self == other or self < other

    def __str__(self) -> str:
        return ".".join(str(part) for part in self.parts)


@dataclass
class AppleIdentifier:
    family: str
    name: str
    deprecated: bool
    ios: Version | None


@dataclass
class GroveIdentifier:
    family: str
    name: str
    ios: Version | None


@dataclass
class OtherSampleType:
    property_name: str
    identifier_def: str | None


def objc_suffix_to_swift_member(suffix: str) -> str:
    if suffix in SWIFT_MEMBER_SPECIALS:
        return SWIFT_MEMBER_SPECIALS[suffix]
    return suffix[0].lower() + suffix[1:]


def extract_balanced(text: str, open_index: int) -> tuple[str, int]:
    if text[open_index] != "(":
        raise ValueError("expected '('")
    depth = 0
    for index in range(open_index, len(text)):
        char = text[index]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return text[open_index + 1 : index], index
    raise ValueError("unbalanced parentheses")


def parse_api_available_ios(attrs: str) -> Version | None:
    marker = "API_AVAILABLE"
    index = attrs.find(marker)
    if index < 0:
        return None
    paren = attrs.find("(", index)
    body, _ = extract_balanced(attrs, paren)
    match = re.search(r"\bios\(([\d.]+)\)", body)
    if not match:
        return None
    return Version.parse(match.group(1))


def parse_apple_family(text: str, family: str, prefix: str) -> list[AppleIdentifier]:
    results: list[AppleIdentifier] = []
    pattern = re.compile(rf"HK_EXTERN\s+{re.escape(prefix)}\s+const\s+{re.escape(prefix)}(\w+)\s+([^;]+);")
    for match in pattern.finditer(text):
        suffix, attrs = match.group(1), match.group(2)
        deprecated = "API_DEPRECATED" in attrs
        results.append(
            AppleIdentifier(
                family=family,
                name=objc_suffix_to_swift_member(suffix),
                deprecated=deprecated,
                ios=None if deprecated else parse_api_available_ios(attrs),
            )
        )
    return results


def parse_apple_identifiers(
    type_identifiers_header: str,
    clinical_header: str,
) -> dict[str, list[AppleIdentifier]]:
    by_family: dict[str, list[AppleIdentifier]] = {}
    for family, prefix in FAMILY_PREFIXES.items():
        source = clinical_header if family == "clinical" else type_identifiers_header
        by_family[family] = parse_apple_family(source, family, prefix)
    return by_family


def _extract_list_block(source: str, var_name: str) -> str:
    match = re.search(rf"{re.escape(var_name)}\s*(?::[^=]+)?=\s*\[", source)
    if match is None:
        raise ValueError(f"could not find list assignment for {var_name}")
    start = match.end()
    depth = 1
    index = start
    while index < len(source) and depth:
        char = source[index]
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
        index += 1
    return source[start : index - 1]


def _split_top_level_calls(block: str, factory_names: tuple[str, ...]) -> list[str]:
    """Return argument bodies for top-level ``factory(...)`` calls inside a list literal."""
    calls: list[str] = []
    pattern = re.compile(rf"\b({'|'.join(factory_names)})\s*\(")
    index = 0
    while True:
        match = pattern.search(block, index)
        if match is None:
            break
        open_paren = match.end() - 1
        body, close = extract_balanced(block, open_paren)
        calls.append(body)
        index = close + 1
    return calls


def _parse_availability_kwarg(call_body: str) -> Version | None:
    match = re.search(r"availability\s*=\s*Availability\s*\(", call_body)
    if match is None:
        return None
    open_paren = match.end() - 1
    body, _ = extract_balanced(call_body, open_paren)
    ios = re.search(r"iOS\s*=\s*['\"]([^'\"]+)['\"]", body)
    if ios is None:
        return None
    return Version.parse(ios.group(1))


def _parse_identifier_kwarg(call_body: str) -> str:
    match = re.search(r"identifier\s*=\s*['\"]([^'\"]+)['\"]", call_body)
    if match is None:
        raise ValueError(f"missing identifier= in call: {call_body[:120]!r}")
    return match.group(1)


def parse_grove_family_list(defs_source: str, var_name: str, family: str) -> list[GroveIdentifier]:
    block = _extract_list_block(defs_source, var_name)
    factories = {
        "quantity": ("quantity_type",),
        "category": ("category_type",),
        "correlation": ("correlation_type",),
        "clinical": ("clinical_type",),
    }[family]
    results: list[GroveIdentifier] = []
    for call_body in _split_top_level_calls(block, factories):
        results.append(
            GroveIdentifier(
                family=family,
                name=_parse_identifier_kwarg(call_body),
                ios=_parse_availability_kwarg(call_body),
            )
        )
    return results


def parse_grove_characteristics(gyb_source: str) -> list[GroveIdentifier]:
    match = re.search(
        r"extension HKCharacteristicTypeIdentifier\s*\{.*?allKnownIdentifiers.*?=\s*\[(.*?)\]",
        gyb_source,
        re.DOTALL,
    )
    if match is None:
        raise ValueError("could not find HKCharacteristicTypeIdentifier.allKnownIdentifiers in SampleTypes.swift.gyb")
    names = re.findall(r"\.(\w+)", match.group(1))
    return [GroveIdentifier(family="characteristic", name=name, ios=None) for name in names]


def parse_other_sample_types(defs_source: str) -> list[OtherSampleType]:
    block = _extract_list_block(defs_source, "other_sample_types")
    results: list[OtherSampleType] = []
    for call_body in _split_top_level_calls(block, ("OtherSampleType",)):
        property_match = re.search(r"sampleTypePropertyName\s*=\s*['\"]([^'\"]+)['\"]", call_body)
        ident_match = re.search(r"identifier_def\s*=\s*['\"]([^'\"]+)['\"]", call_body)
        if property_match is None:
            raise ValueError("OtherSampleType missing sampleTypePropertyName")
        results.append(
            OtherSampleType(
                property_name=property_match.group(1),
                identifier_def=ident_match.group(1) if ident_match else None,
            )
        )
    return results


def parse_grove_identifiers(defs_source: str, gyb_source: str) -> dict[str, list[GroveIdentifier]]:
    return {
        "quantity": parse_grove_family_list(defs_source, "quantity_types", "quantity"),
        "category": parse_grove_family_list(defs_source, "category_types", "category"),
        "correlation": parse_grove_family_list(defs_source, "correlation_types", "correlation"),
        "clinical": parse_grove_family_list(defs_source, "clinical_types", "clinical"),
        "characteristic": parse_grove_characteristics(gyb_source),
    }


def headers_contain_symbol(headers_text: str, symbol: str) -> bool:
    if re.search(rf"\b{re.escape(symbol)}\b", headers_text):
        return True
    # Scored assessments are written as HKScoredAssessmentTypeIdentifier.GAD7 in defs.
    if "." in symbol:
        compact = symbol.replace(".", "")
        return re.search(rf"\b{re.escape(compact)}\b", headers_text) is not None
    return False


def other_type_symbol_candidates(other: OtherSampleType) -> list[str]:
    candidates: list[str] = []
    if other.identifier_def:
        candidates.append(other.identifier_def)
        if "." in other.identifier_def:
            candidates.append(other.identifier_def.replace(".", ""))
    fallback = OTHER_SYMBOL_FALLBACKS.get(other.property_name)
    if fallback:
        candidates.append(fallback)
    return candidates


def compare_families(
    grove: dict[str, list[GroveIdentifier]],
    apple: dict[str, list[AppleIdentifier]],
    *,
    ios_floor: Version,
) -> list[str]:
    problems: list[str] = []
    for family in FAMILY_PREFIXES:
        grove_by_name = {item.name: item for item in grove[family]}
        apple_items = apple[family]
        apple_active = {item.name: item for item in apple_items if not item.deprecated}
        apple_deprecated = {item.name for item in apple_items if item.deprecated}

        for name in sorted(set(grove_by_name) - set(apple_active) - apple_deprecated):
            problems.append(
                f"{family}: Grove defines '{name}', which is not in the HealthKit SDK. "
                "Remove the stale definition from SampleTypeDefs.py (or SampleTypes.swift.gyb for characteristics) "
                "and regenerate with ./useGYB."
            )
        for name in sorted(set(grove_by_name) & apple_deprecated):
            problems.append(
                f"{family}: Grove still defines deprecated HealthKit identifier '{name}'. "
                "Remove it from SampleTypeDefs.py and regenerate with ./useGYB."
            )
        for name in sorted(set(apple_active) - set(grove_by_name)):
            problems.append(
                f"{family}: HealthKit exposes '{name}', which Grove does not define. "
                "Hand-author an entry in SampleTypeDefs.py (title, units, docs) and regenerate with ./useGYB. "
                "This check never auto-adds definitions."
            )

        for name, apple_item in sorted(apple_active.items()):
            grove_item = grove_by_name.get(name)
            if grove_item is None or apple_item.ios is None:
                continue
            problems.extend(
                availability_problems(family, name, grove_item.ios, apple_item.ios, ios_floor=ios_floor)
            )
    return problems


def availability_problems(
    family: str,
    name: str,
    grove_ios: Version | None,
    apple_ios: Version,
    *,
    ios_floor: Version,
) -> list[str]:
    if apple_ios <= ios_floor:
        if grove_ios is not None and grove_ios > ios_floor:
            return [
                f"{family}: '{name}' is available since iOS {apple_ios} (at/below SampleType floor "
                f"{ios_floor}), but Grove declares Availability(iOS='{grove_ios}')."
            ]
        return []

    if grove_ios is None:
        return [
            f"{family}: '{name}' requires iOS {apple_ios} in HealthKit, but Grove has no Availability gate. "
            f"Add Availability(iOS='{apple_ios}', ...) in SampleTypeDefs.py and regenerate with ./useGYB."
        ]
    if grove_ios != apple_ios:
        return [
            f"{family}: '{name}' HealthKit iOS availability is {apple_ios}, but Grove declares "
            f"Availability(iOS='{grove_ios}'). Align the Availability annotation and regenerate with ./useGYB."
        ]
    return []


def compare_other_sample_types(
    others: Iterable[OtherSampleType],
    headers_text: str,
) -> list[str]:
    problems: list[str] = []
    for other in others:
        candidates = other_type_symbol_candidates(other)
        if not candidates:
            problems.append(
                f"other: '{other.property_name}' has no identifier_def to validate against HealthKit headers."
            )
            continue
        if not any(headers_contain_symbol(headers_text, candidate) for candidate in candidates):
            problems.append(
                f"other: '{other.property_name}' references {candidates[0]!r}, which was not found in "
                "HealthKit headers. Update or remove the other-sample-type definition."
            )
    return problems


def resolve_iphoneos_sdk_path() -> Path:
    result = subprocess.run(
        ["xcrun", "--sdk", "iphoneos", "--show-sdk-path"],
        check=True,
        capture_output=True,
        text=True,
    )
    path = Path(result.stdout.strip())
    if not path.is_dir():
        raise FileNotFoundError(f"iphoneos SDK path does not exist: {path}")
    return path


def load_sdk_headers(sdk_path: Path) -> tuple[str, str, str]:
    headers = sdk_path / "System" / "Library" / "Frameworks" / "HealthKit.framework" / "Headers"
    type_identifiers = (headers / "HKTypeIdentifiers.h").read_text(encoding="utf-8")
    clinical = (headers / "HKClinicalType.h").read_text(encoding="utf-8")
    combined = "\n".join(path.read_text(encoding="utf-8") for path in sorted(headers.glob("*.h")))
    return type_identifiers, clinical, combined


def collect_problems(
    *,
    defs_source: str,
    gyb_source: str,
    type_identifiers_header: str,
    clinical_header: str,
    all_headers_text: str,
    ios_floor: Version = Version(SAMPLE_TYPE_IOS_FLOOR),
) -> list[str]:
    grove = parse_grove_identifiers(defs_source, gyb_source)
    apple = parse_apple_identifiers(type_identifiers_header, clinical_header)
    problems = compare_families(grove, apple, ios_floor=ios_floor)
    problems.extend(compare_other_sample_types(parse_other_sample_types(defs_source), all_headers_text))
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sdk",
        type=Path,
        help="iphoneos SDK root (defaults to `xcrun --sdk iphoneos --show-sdk-path`)",
    )
    parser.add_argument(
        "--defs",
        type=Path,
        default=DEFS_PATH,
        help="path to SampleTypeDefs.py",
    )
    parser.add_argument(
        "--gyb",
        type=Path,
        default=GYB_PATH,
        help="path to SampleTypes.swift.gyb",
    )
    args = parser.parse_args(argv)

    try:
        sdk_path = args.sdk or resolve_iphoneos_sdk_path()
        type_identifiers, clinical, all_headers = load_sdk_headers(sdk_path)
        problems = collect_problems(
            defs_source=args.defs.read_text(encoding="utf-8"),
            gyb_source=args.gyb.read_text(encoding="utf-8"),
            type_identifiers_header=type_identifiers,
            clinical_header=clinical,
            all_headers_text=all_headers,
        )
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        print(
            "error: SampleType definitions drifted from HealthKit. "
            "Hand-edit SampleTypeDefs.py / SampleTypes.swift.gyb, then run ./useGYB. "
            "This script does not auto-add definitions.",
            file=sys.stderr,
        )
        return 1

    print(
        f"ok: Grove SampleType definitions match HealthKit identifiers in {sdk_path.name}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
