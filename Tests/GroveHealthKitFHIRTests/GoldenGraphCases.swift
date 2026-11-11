//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4


/// The Observation-graph shapes the goldens pin: one sample each, exported through `HealthKitFHIRExporter`.
extension GoldenCase {
    /// Every pinned shape, in the order the goldens directory lists them.
    static let all: [GoldenCase] = observations + writers + disclosures + documents + retractions + exporter + guideExamples + thresholds

    static let thresholds: [GoldenCase] = [
        GoldenCase("high-heart-rate-threshold") {
            let sample = HKCategorySample(
                type: HKCategoryType(.highHeartRateEvent),
                value: HKCategoryValue.notApplicable.rawValue,
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart,
                metadata: [HKMetadataKeyHeartRateEventThreshold: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 120)]
            )
            return try await GoldenFixtures.export(
                StoredSampleFixtures.stored(sample, uuid: GoldenFixtures.uuid(0x96), writer: .unattributed)
            )
        }
    ]

    /// The measurement shapes under the default context.
    static let observations: [GoldenCase] = [
        GoldenCase("heart-rate-minimal") {
            try await GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(1), metadata: nil, writer: .unattributed)
            )
        },
        GoldenCase("heart-rate-study") {
            var inputs = ExportInputs()
            inputs.studies = [.test("study-a")]
            return try await GoldenFixtures.export(GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(2)), inputs)
        },
        GoldenCase("heart-rate-recording-device") {
            try await GoldenFixtures.export(GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(3), device: GoldenFixtures.watch))
        },
        GoldenCase("heart-rate-device-without-unit-token") {
            try await GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(4), device: GoldenFixtures.watchWithoutUnitToken)
            )
        },
        GoldenCase("heart-rate-no-time-zone") {
            try await GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(5), device: GoldenFixtures.watch, metadata: nil)
            )
        },
        GoldenCase("heart-rate-interval") {
            try await GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(6), end: GoldenFixtures.sampleStart.addingTimeInterval(45))
            )
        },
        GoldenCase("heart-rate-motion-context") {
            let metadata: [String: any Sendable] = [
                HKMetadataKeyTimeZone: GoldenFixtures.timeZone,
                HKMetadataKeyHeartRateMotionContext: HKHeartRateMotionContext.active.rawValue
            ]
            return try await GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(7), device: GoldenFixtures.watch, metadata: metadata)
            )
        },
        GoldenCase("step-count-period") {
            let steps = HKQuantitySample(
                type: HKQuantityType(.stepCount),
                quantity: HKQuantity(unit: .count(), doubleValue: 120),
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart.addingTimeInterval(60),
                device: GoldenFixtures.watch,
                metadata: GoldenFixtures.timeZoneMetadata
            )
            return try await GoldenFixtures.export(StoredSampleFixtures.stored(steps, uuid: GoldenFixtures.uuid(8)))
        },
        GoldenCase("blood-pressure-correlation") {
            try await GoldenFixtures.export(bloodPressure())
        },
        GoldenCase("sleep-analysis") {
            try await GoldenFixtures.export(
                GoldenFixtures.category(
                    .sleepAnalysis,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    uuid: GoldenFixtures.uuid(10),
                    duration: 3_600
                )
            )
        },
        GoldenCase("state-of-mind") {
            let stateOfMind = HKStateOfMind(
                date: GoldenFixtures.sampleStart,
                kind: .momentaryEmotion,
                valence: 0.5,
                labels: [.happy],
                associations: [.work],
                metadata: GoldenFixtures.timeZoneMetadata
            )
            return try await GoldenFixtures.export(StoredSampleFixtures.stored(stateOfMind, uuid: GoldenFixtures.uuid(11)))
        },
        GoldenCase("insulin-delivery-bolus") {
            let metadata: [String: any Sendable] = [
                HKMetadataKeyTimeZone: GoldenFixtures.timeZone,
                HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.bolus.rawValue
            ]
            return try await GoldenFixtures.export(
                GoldenFixtures.quantity(.insulinDelivery, HKQuantity(unit: .internationalUnit(), doubleValue: 2.5), uuid: GoldenFixtures.uuid(12), metadata: metadata)
            )
        },
        GoldenCase("body-mass-user-entered") {
            let metadata: [String: any Sendable] = [HKMetadataKeyTimeZone: GoldenFixtures.timeZone, HKMetadataKeyWasUserEntered: true]
            return try await GoldenFixtures.export(
                GoldenFixtures.quantity(.bodyMass, HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 71.3), uuid: GoldenFixtures.uuid(13), metadata: metadata)
            )
        },
        GoldenCase("workout-session") {
            try await GoldenFixtures.export(
                StoredSampleFixtures.stored(GoldenFixtures.workout(withEvents: true), uuid: GoldenFixtures.uuid(14))
            )
        },
        // HealthKit scores the answers itself: 0 + 1 + 2 + 3 + 0 + 1 + 2.
        GoldenCase("gad7-assessment") {
            let assessment = HKGAD7Assessment(
                date: GoldenFixtures.sampleStart,
                answers: [.notAtAll, .severalDays, .moreThanHalfTheDays, .nearlyEveryDay, .notAtAll, .severalDays, .moreThanHalfTheDays],
                metadata: GoldenFixtures.timeZoneMetadata
            )
            return try await GoldenFixtures.export(StoredSampleFixtures.stored(assessment, uuid: GoldenFixtures.uuid(15)))
        },
        // The session under every envelope link it takes (spec F1): a study, a gateway application, manual entry
        // and the watch that recorded it.
        GoldenCase("workout-session-context") {
            var inputs = ExportInputs()
            inputs.studies = [.test("study-a")]
            inputs.options.role = .gatewayApplication(.test(name: "Cuff Companion", bundleIdentifier: "com.example.cuff", version: "3.1"))
            let workout = GoldenFixtures.workout(withEvents: false, device: GoldenFixtures.watch, userEntered: true)
            return try await GoldenFixtures.export(StoredSampleFixtures.stored(workout, uuid: GoldenFixtures.uuid(16)), inputs)
        },
        // HealthKit keeps the fraction 0.282, stated as 28.2 % (spec F4-percent), never as the binary64 product
        // 28.199999999999996.
        GoldenCase("body-fat-percentage-fraction") {
            try await GoldenFixtures.export(
                GoldenFixtures.quantity(.bodyFatPercentage, HKQuantity(unit: .percent(), doubleValue: 0.282), uuid: GoldenFixtures.uuid(17))
            )
        },
        // Spec F9: the correlation states nothing, so its members state the record's zone and manual entry, and their
        // key outside the allowlist is reported.
        GoldenCase("blood-pressure-member-metadata") {
            let members: [String: any Sendable] = [
                HKMetadataKeyTimeZone: GoldenFixtures.timeZone,
                HKMetadataKeyWasUserEntered: true,
                "com.example.member": "x"
            ]
            return try await GoldenFixtures.export(bloodPressure(uuid: 18, components: (0x93, 0x94), metadata: nil, memberMetadata: members))
        },
        // HealthKit's initial-low notification over one day: the classification low is the value and the first
        // notification is the notification-occurrence component, as the guide's example states.
        GoldenCase("walking-steadiness-notification") {
            try await GoldenFixtures.export(
                GoldenFixtures.category(
                    .appleWalkingSteadinessEvent,
                    value: HKCategoryValueAppleWalkingSteadinessEvent.initialLow.rawValue,
                    uuid: GoldenFixtures.uuid(19),
                    duration: 86_400
                )
            )
        }
    ]

    /// How the sample's writer (`HKSourceRevision`) travels once the caller classified its source as an
    /// application, and what an unclassified source states.
    static let writers: [GoldenCase] = [
        GoldenCase("writer-foreign-application") {
            try await GoldenFixtures.export(
                attributedHeartRate(uuid: 20, writer: GoldenFixtures.foreignWriter),
                .applicationWriter
            )
        },
        // The converter states version 1.2.3 build 42 and HealthKit records revision version 42: the shape a real
        // device produces. Their content differs, so the writer travels as a second application Device of the same bundle.
        GoldenCase("writer-self-build-equals-revision") {
            var inputs = ExportInputs.applicationWriter
            inputs.converter = GoldenFixtures.selfConverter(version: "1.2.3", build: "42")
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 21, writer: GoldenFixtures.selfWriter(revisionVersion: "42")), inputs)
        },
        GoldenCase("writer-self-older-build") {
            var inputs = ExportInputs.applicationWriter
            inputs.converter = GoldenFixtures.selfConverter(version: "1.2.3", build: "43")
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 22, writer: GoldenFixtures.selfWriter(revisionVersion: "42")), inputs)
        },
        // No build and a version equal to the revision's: the writer states that value as its build, the converter as its
        // version, so the writer is a snapshot of its own here too.
        GoldenCase("writer-self-version-equals-revision") {
            var inputs = ExportInputs.applicationWriter
            inputs.converter = GoldenFixtures.selfConverter(version: "42", build: nil)
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 23, writer: GoldenFixtures.selfWriter(revisionVersion: "42")), inputs)
        },
        GoldenCase("writer-host-equals-converter-host") {
            var inputs = ExportInputs.applicationWriter
            inputs.converterHost = try HostDevice(operatingSystemVersion: "26.1.0", productType: "iPhone17,1")
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 24, writer: GoldenFixtures.foreignWriter), inputs)
        },
        // An unclassified source states no writer and the Provenance no author; the recording Device the sample's
        // `HKDevice` names stays.
        GoldenCase("writer-omitted") {
            var inputs = ExportInputs()
            inputs.options.writer = .omit
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 25, writer: GoldenFixtures.foreignWriter), inputs)
        },
        GoldenCase("writer-omitted-without-recording-device") {
            var inputs = ExportInputs()
            inputs.options.writer = .omit
            return try await GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(26), writer: GoldenFixtures.foreignWriter),
                inputs
            )
        },
        GoldenCase("writer-blank-name-with-sync-identity") {
            var writer = GoldenFixtures.foreignWriter
            writer.name = ""
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 27, writer: writer, metadata: syncMetadata), .applicationWriter)
        },
        GoldenCase("writer-without-version") {
            var writer = GoldenFixtures.foreignWriter
            writer.version = nil
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 28, writer: writer), .applicationWriter)
        },
        GoldenCase("sync-identity") {
            try await GoldenFixtures.export(
                attributedHeartRate(uuid: 29, writer: GoldenFixtures.foreignWriter, metadata: syncMetadata),
                .applicationWriter
            )
        },
        // A name outside ASCII with a precomposed U+00E9: the comparison is scalar by scalar, so a decomposed
        // spelling of the same name would be a different golden.
        GoldenCase("writer-non-ascii-name") {
            var writer = GoldenFixtures.foreignWriter
            writer.name = "Sant\u{E9} Journal"
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 30, writer: writer), .applicationWriter)
        }
    ]

    /// Disclosure policies, device facts, converter roles, subjects and studies.
    static let disclosures: [GoldenCase] = [
        GoldenCase("native-identifier-disclosure") {
            var inputs = ExportInputs()
            inputs.options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 40, writer: GoldenFixtures.foreignWriter), inputs)
        },
        // Every device metadata key beside an HKDevice that states only its model: the keys fill what it leaves absent.
        GoldenCase("device-metadata-facts") {
            let metadata: [String: any Sendable] = [
                HKMetadataKeyTimeZone: GoldenFixtures.timeZone,
                HKMetadataKeyDeviceName: "Bedside Cuff",
                HKMetadataKeyDeviceManufacturerName: "Example Devices",
                HKMetadataKeyDeviceSerialNumber: "SN-0042",
                HKMetadataKeyUDIDeviceIdentifier: "(01)00844588003288",
                HKMetadataKeyUDIProductionIdentifier: "(11)141231(17)150707(10)A213B1(21)1234"
            ]
            let device = HKDevice(
                name: nil,
                manufacturer: nil,
                model: "Cuff 2",
                hardwareVersion: nil,
                firmwareVersion: nil,
                softwareVersion: nil,
                localIdentifier: nil,
                udiDeviceIdentifier: nil
            )
            return try await GoldenFixtures.export(GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(41), device: device, metadata: metadata))
        },
        GoldenCase("gateway-role") {
            var inputs = ExportInputs()
            inputs.options.role = .gateway
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 42, writer: GoldenFixtures.foreignWriter), inputs)
        },
        GoldenCase("gateway-application-role") {
            var inputs = ExportInputs()
            inputs.options.role = .gatewayApplication(.test(name: "Cuff Companion", bundleIdentifier: "com.example.cuff", version: "3.1"))
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 43, writer: GoldenFixtures.foreignWriter), inputs)
        },
        GoldenCase("bundled-patient-subject") {
            var inputs = ExportInputs()
            inputs.subject = .bundled(.test(.patient, "example"), Patient())
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 44, writer: GoldenFixtures.foreignWriter), inputs)
        },
        GoldenCase("two-study-enrollments") {
            var inputs = ExportInputs()
            inputs.studies = [.test("study-a"), .test("study-b")]
            return try await GoldenFixtures.export(attributedHeartRate(uuid: 45, writer: GoldenFixtures.foreignWriter), inputs)
        }
    ]

    /// Records built from the values a grove-fhir guide example states, one per example that
    /// `Scripts/check-ig-example-containment.py` pairs with its golden, so that script can check that the golden contains
    /// everything the example states.
    static let guideExamples: [GoldenCase] = [
        // HealthKitHeartRateObservationExample: 72/min at 10:30:00.251 Los Angeles time while sedentary, from the
        // watch, in a study.
        GoldenCase("guide-example-heart-rate") {
            let start = Date(timeIntervalSince1970: 1_787_160_600.251)
            let sample = HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: GoldenFixtures.beatsPerMinute, doubleValue: 72),
                start: start,
                end: start,
                device: GoldenFixtures.watch,
                metadata: [
                    HKMetadataKeyTimeZone: GoldenFixtures.timeZone,
                    HKMetadataKeyHeartRateMotionContext: HKHeartRateMotionContext.sedentary.rawValue
                ]
            )
            var inputs = ExportInputs()
            inputs.studies = [.test("study-a")]
            return try await GoldenFixtures.export(
                try StoredSampleFixtures.stored(sample, uuid: GoldenFixtures.uuid(0x78)),
                inputs
            )
        }
    ]

    static let syncMetadata: [String: any Sendable] = [
        HKMetadataKeyTimeZone: GoldenFixtures.timeZone,
        HKMetadataKeySyncIdentifier: "sync-abc",
        HKMetadataKeySyncVersion: 3
    ]

    /// A heart rate from the watch, written by `writer`.
    static func attributedHeartRate(
        uuid ordinal: UInt8,
        writer: StoredSampleFixtures.Writer,
        metadata: [String: any Sendable] = GoldenFixtures.timeZoneMetadata
    ) throws -> HKQuantitySample {
        try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(ordinal), device: GoldenFixtures.watch, metadata: metadata, writer: writer)
    }

    /// A 120/80 reading from the watch; the correlation and its two components each take one of the ordinals, and state
    /// `metadata` and `memberMetadata`.
    static func bloodPressure(
        uuid ordinal: UInt8 = 9,
        components: (systolic: UInt8, diastolic: UInt8) = (0x91, 0x92),
        metadata: [String: any Sendable]? = GoldenFixtures.timeZoneMetadata, // swiftlint:disable:this discouraged_optional_collection
        memberMetadata: [String: any Sendable] = GoldenFixtures.timeZoneMetadata
    ) throws -> HKCorrelation {
        func component(_ type: HKQuantityTypeIdentifier, _ value: Double, uuid: UInt8) throws -> HKQuantitySample {
            try GoldenFixtures.quantity(
                type,
                HKQuantity(unit: .millimeterOfMercury(), doubleValue: value),
                uuid: GoldenFixtures.uuid(uuid),
                device: GoldenFixtures.watch,
                metadata: memberMetadata
            )
        }
        let correlation = HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart,
            objects: [
                try component(.bloodPressureSystolic, 120, uuid: components.systolic),
                try component(.bloodPressureDiastolic, 80, uuid: components.diastolic)
            ],
            device: GoldenFixtures.watch,
            metadata: metadata
        )
        return try StoredSampleFixtures.stored(correlation, uuid: GoldenFixtures.uuid(ordinal))
    }
}

#endif
