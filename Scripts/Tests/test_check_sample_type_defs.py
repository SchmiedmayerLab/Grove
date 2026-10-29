#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

"""Fixture tests for Scripts/check-sample-type-defs.py."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "check-sample-type-defs.py"


def load_module():
    spec = importlib.util.spec_from_file_location("check_sample_type_defs", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


check = load_module()


MINIMAL_GYB = """
extension HKCharacteristicTypeIdentifier {
    /// All well-known `HKCharacteristicTypeIdentifier`s
    public static let allKnownIdentifiers: Set<HKCharacteristicTypeIdentifier> = [
        .biologicalSex,
        .dateOfBirth
    ]
}
"""

MINIMAL_DEFS = """
quantity_types: list[SampleType] = [
    quantity_type(
        identifier='stepCount',
        canonical_title='Step Count',
        unit='.count()',
        doc='steps'
    ),
    quantity_type(
        identifier='vo2Max',
        canonical_title='VO2 Max',
        unit='.literUnit(with: .milli)/.gramUnit(with: .kilo)/.minute()',
        doc='vo2'
    ),
    quantity_type(
        identifier='uvExposure',
        canonical_title='UV Exposure',
        unit='.count()',
        doc='uv'
    ),
]

category_types: list[SampleType] = [
    category_type(
        identifier='sleepAnalysis',
        canonical_title='Sleep Analysis',
        doc='sleep'
    ),
]

correlation_types: list[SampleType] = [
    correlation_type(
        identifier='bloodPressure',
        canonical_title='Blood Pressure',
        associated=['bloodPressureSystolic', 'bloodPressureDiastolic'],
        doc='bp'
    ),
]

clinical_types: list[SampleType] = [
    clinical_type(
        identifier='allergyRecord',
        canonical_title='Allergy Record',
        doc='allergy'
    ),
]

other_sample_types = [
    OtherSampleType(
        sampleTypePropertyName='workout',
        hkSampleClass='HKWorkout',
        canonical_title='Workout',
        doc='workout',
        hkSampleType='HKSampleType.workoutType()',
        variant='.other',
        identifier_def='HKWorkoutTypeIdentifier'
    ),
]
"""

APPLE_TYPE_IDENTIFIERS = """
HK_EXTERN HKQuantityTypeIdentifier const HKQuantityTypeIdentifierStepCount API_AVAILABLE(ios(8.0), watchos(2.0));
HK_EXTERN HKQuantityTypeIdentifier const HKQuantityTypeIdentifierVO2Max API_AVAILABLE(ios(11.0), watchos(4.0));
HK_EXTERN HKQuantityTypeIdentifier const HKQuantityTypeIdentifierUVExposure API_AVAILABLE(ios(9.0), watchos(2.0));
HK_EXTERN HKCategoryTypeIdentifier const HKCategoryTypeIdentifierSleepAnalysis API_AVAILABLE(ios(8.0), watchos(2.0));
HK_EXTERN HKCategoryTypeIdentifier const HKCategoryTypeIdentifierAudioExposureEvent API_DEPRECATED_WITH_REPLACEMENT("HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent", ios(13.0, 14.0), watchos(6.0, 7.0));
HK_EXTERN HKCorrelationTypeIdentifier const HKCorrelationTypeIdentifierBloodPressure API_AVAILABLE(ios(8.0), watchos(2.0));
HK_EXTERN HKCharacteristicTypeIdentifier const HKCharacteristicTypeIdentifierBiologicalSex API_AVAILABLE(ios(8.0), watchos(2.0));
HK_EXTERN HKCharacteristicTypeIdentifier const HKCharacteristicTypeIdentifierDateOfBirth API_AVAILABLE(ios(8.0), watchos(2.0));
HK_EXTERN NSString * const HKWorkoutTypeIdentifier API_AVAILABLE(ios(8.0), watchos(2.0));
"""

APPLE_CLINICAL = """
HK_EXTERN HKClinicalTypeIdentifier const HKClinicalTypeIdentifierAllergyRecord API_AVAILABLE(ios(12.0), watchos(5.0));
"""


def problems_for(
    *,
    defs: str = MINIMAL_DEFS,
    gyb: str = MINIMAL_GYB,
    type_identifiers: str = APPLE_TYPE_IDENTIFIERS,
    clinical: str = APPLE_CLINICAL,
    headers: str | None = None,
) -> list[str]:
    return check.collect_problems(
        defs_source=defs,
        gyb_source=gyb,
        type_identifiers_header=type_identifiers,
        clinical_header=clinical,
        all_headers_text=headers if headers is not None else type_identifiers + "\n" + clinical,
        ios_floor=check.Version.parse("18"),
    )


class CheckSampleTypeDefsTests(unittest.TestCase):
    def test_matching_inventory_is_clean(self) -> None:
        self.assertEqual(problems_for(), [])

    def test_swift_special_names_map_from_objc_suffixes(self) -> None:
        self.assertEqual(check.objc_suffix_to_swift_member("VO2Max"), "vo2Max")
        self.assertEqual(check.objc_suffix_to_swift_member("UVExposure"), "uvExposure")
        self.assertEqual(check.objc_suffix_to_swift_member("StepCount"), "stepCount")

    def test_missing_apple_identifier_fails(self) -> None:
        apple = APPLE_TYPE_IDENTIFIERS + (
            "\nHK_EXTERN HKCategoryTypeIdentifier const HKCategoryTypeIdentifierHypertensionEvent "
            "API_AVAILABLE(ios(26.2), watchos(26.2));\n"
        )
        messages = problems_for(type_identifiers=apple, headers=apple + "\n" + APPLE_CLINICAL)
        self.assertTrue(any("hypertensionEvent" in message and "does not define" in message for message in messages))

    def test_stale_grove_identifier_fails(self) -> None:
        defs = MINIMAL_DEFS.replace(
            "category_types: list[SampleType] = [",
            "category_types: list[SampleType] = [\n    category_type(\n"
            "        identifier='madeUpEvent',\n"
            "        canonical_title='Made Up',\n"
            "        doc='nope'\n    ),",
        )
        messages = problems_for(defs=defs)
        self.assertTrue(any("madeUpEvent" in message and "not in the HealthKit SDK" in message for message in messages))

    def test_deprecated_identifier_in_grove_fails(self) -> None:
        defs = MINIMAL_DEFS.replace(
            "category_types: list[SampleType] = [",
            "category_types: list[SampleType] = [\n    category_type(\n"
            "        identifier='audioExposureEvent',\n"
            "        canonical_title='Audio Exposure Event',\n"
            "        doc='deprecated'\n    ),",
        )
        messages = problems_for(defs=defs)
        self.assertTrue(any("deprecated" in message and "audioExposureEvent" in message for message in messages))

    def test_availability_mismatch_fails(self) -> None:
        apple = APPLE_TYPE_IDENTIFIERS + (
            "\nHK_EXTERN HKCategoryTypeIdentifier const HKCategoryTypeIdentifierHypertensionEvent "
            "API_AVAILABLE(ios(26.2), watchos(26.2));\n"
        )
        defs = MINIMAL_DEFS.replace(
            "category_types: list[SampleType] = [",
            "category_types: list[SampleType] = [\n    category_type(\n"
            "        availability=Availability(iOS='26.0', watchOS='26.0', macOS='26.0', visionOS='26.0'),\n"
            "        identifier='hypertensionEvent',\n"
            "        canonical_title='Hypertension Event',\n"
            "        doc='hypertension'\n    ),",
        )
        messages = problems_for(defs=defs, type_identifiers=apple, headers=apple + "\n" + APPLE_CLINICAL)
        self.assertTrue(any("hypertensionEvent" in message and "26.2" in message and "26.0" in message for message in messages))

    def test_missing_availability_gate_fails(self) -> None:
        apple = APPLE_TYPE_IDENTIFIERS + (
            "\nHK_EXTERN HKCategoryTypeIdentifier const HKCategoryTypeIdentifierHypertensionEvent "
            "API_AVAILABLE(ios(26.2), watchos(26.2));\n"
        )
        defs = MINIMAL_DEFS.replace(
            "category_types: list[SampleType] = [",
            "category_types: list[SampleType] = [\n    category_type(\n"
            "        identifier='hypertensionEvent',\n"
            "        canonical_title='Hypertension Event',\n"
            "        doc='hypertension'\n    ),",
        )
        messages = problems_for(defs=defs, type_identifiers=apple, headers=apple + "\n" + APPLE_CLINICAL)
        self.assertTrue(any("no Availability gate" in message for message in messages))

    def test_matching_availability_gate_passes(self) -> None:
        apple = APPLE_TYPE_IDENTIFIERS + (
            "\nHK_EXTERN HKCategoryTypeIdentifier const HKCategoryTypeIdentifierHypertensionEvent "
            "API_AVAILABLE(ios(26.2), watchos(26.2));\n"
        )
        defs = MINIMAL_DEFS.replace(
            "category_types: list[SampleType] = [",
            "category_types: list[SampleType] = [\n    category_type(\n"
            "        availability=Availability(iOS='26.2', watchOS='26.2', macOS='26.2', visionOS='26.2'),\n"
            "        identifier='hypertensionEvent',\n"
            "        canonical_title='Hypertension Event',\n"
            "        doc='hypertension'\n    ),",
        )
        self.assertEqual(problems_for(defs=defs, type_identifiers=apple, headers=apple + "\n" + APPLE_CLINICAL), [])


if __name__ == "__main__":
    unittest.main()
