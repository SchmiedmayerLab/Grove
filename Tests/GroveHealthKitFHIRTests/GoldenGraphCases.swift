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
    static let all: [GoldenCase] = observations + writers + disclosures + documents + retractions + exporter

    /// Sequences 1-19: the measurement shapes under the default context.
    static let observations: [GoldenCase] = [
        GoldenCase("heart-rate-minimal", sequence: 1) { sequence in
            try GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(1), metadata: nil, writer: .unattributed),
                sequence: sequence
            )
        },
        GoldenCase("heart-rate-study", sequence: 2) { sequence in
            var inputs = ExportInputs()
            inputs.studies = [.test("study-a")]
            return try GoldenFixtures.export(GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(2)), sequence: sequence, inputs)
        },
        GoldenCase("heart-rate-recording-device", sequence: 3) { sequence in
            try GoldenFixtures.export(GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(3), device: GoldenFixtures.watch), sequence: sequence)
        },
        GoldenCase("heart-rate-device-without-unit-token", sequence: 4) { sequence in
            try GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(4), device: GoldenFixtures.watchWithoutUnitToken),
                sequence: sequence
            )
        },
        GoldenCase("heart-rate-no-time-zone", sequence: 5) { sequence in
            try GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(5), device: GoldenFixtures.watch, metadata: nil),
                sequence: sequence
            )
        },
        GoldenCase("heart-rate-interval", sequence: 6) { sequence in
            try GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(6), end: GoldenFixtures.sampleStart.addingTimeInterval(45)),
                sequence: sequence
            )
        },
        GoldenCase("heart-rate-motion-context", sequence: 7) { sequence in
            let metadata: [String: any Sendable] = [
                HKMetadataKeyTimeZone: GoldenFixtures.timeZone,
                HKMetadataKeyHeartRateMotionContext: HKHeartRateMotionContext.active.rawValue
            ]
            return try GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(7), device: GoldenFixtures.watch, metadata: metadata),
                sequence: sequence
            )
        },
        GoldenCase("step-count-period", sequence: 8) { sequence in
            let steps = HKQuantitySample(
                type: HKQuantityType(.stepCount),
                quantity: HKQuantity(unit: .count(), doubleValue: 120),
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart.addingTimeInterval(60),
                device: GoldenFixtures.watch,
                metadata: GoldenFixtures.timeZoneMetadata
            )
            return try GoldenFixtures.export(StoredSampleFixtures.stored(steps, uuid: GoldenFixtures.uuid(8)), sequence: sequence)
        },
        GoldenCase("blood-pressure-correlation", sequence: 9) { sequence in
            try GoldenFixtures.export(bloodPressure(), sequence: sequence)
        },
        GoldenCase("sleep-analysis", sequence: 10) { sequence in
            try GoldenFixtures.export(
                GoldenFixtures.category(.sleepAnalysis, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, uuid: GoldenFixtures.uuid(10), duration: 3_600),
                sequence: sequence
            )
        },
        GoldenCase("state-of-mind", sequence: 11) { sequence in
            let stateOfMind = HKStateOfMind(
                date: GoldenFixtures.sampleStart,
                kind: .momentaryEmotion,
                valence: 0.5,
                labels: [.happy],
                associations: [.work],
                metadata: GoldenFixtures.timeZoneMetadata
            )
            return try GoldenFixtures.export(StoredSampleFixtures.stored(stateOfMind, uuid: GoldenFixtures.uuid(11)), sequence: sequence)
        },
        GoldenCase("insulin-delivery-bolus", sequence: 12) { sequence in
            let metadata: [String: any Sendable] = [
                HKMetadataKeyTimeZone: GoldenFixtures.timeZone,
                HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.bolus.rawValue
            ]
            return try GoldenFixtures.export(
                GoldenFixtures.quantity(.insulinDelivery, HKQuantity(unit: .internationalUnit(), doubleValue: 2.5), uuid: GoldenFixtures.uuid(12), metadata: metadata),
                sequence: sequence
            )
        },
        GoldenCase("body-mass-user-entered", sequence: 13) { sequence in
            let metadata: [String: any Sendable] = [HKMetadataKeyTimeZone: GoldenFixtures.timeZone, HKMetadataKeyWasUserEntered: true]
            return try GoldenFixtures.export(
                GoldenFixtures.quantity(.bodyMass, HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 71.3), uuid: GoldenFixtures.uuid(13), metadata: metadata),
                sequence: sequence
            )
        },
        GoldenCase("workout-session", sequence: 14) { sequence in
            try GoldenFixtures.export(
                StoredSampleFixtures.stored(GoldenFixtures.workout(withEvents: true), uuid: GoldenFixtures.uuid(14)),
                sequence: sequence
            )
        },
        // HealthKit scores the answers itself: 0 + 1 + 2 + 3 + 0 + 1 + 2.
        GoldenCase("gad7-assessment", sequence: 15) { sequence in
            let assessment = HKGAD7Assessment(
                date: GoldenFixtures.sampleStart,
                answers: [.notAtAll, .severalDays, .moreThanHalfTheDays, .nearlyEveryDay, .notAtAll, .severalDays, .moreThanHalfTheDays],
                metadata: GoldenFixtures.timeZoneMetadata
            )
            return try GoldenFixtures.export(StoredSampleFixtures.stored(assessment, uuid: GoldenFixtures.uuid(15)), sequence: sequence)
        },
        // The session under every envelope link it takes (spec F1): a study, a gateway application, manual entry
        // and the watch that recorded it.
        GoldenCase("workout-session-context", sequence: 16) { sequence in
            var inputs = ExportInputs()
            inputs.studies = [.test("study-a")]
            inputs.options.role = .gatewayApplication(.test(name: "Cuff Companion", bundleIdentifier: "com.example.cuff", version: "3.1"))
            let workout = GoldenFixtures.workout(withEvents: false, device: GoldenFixtures.watch, userEntered: true)
            return try GoldenFixtures.export(StoredSampleFixtures.stored(workout, uuid: GoldenFixtures.uuid(16)), sequence: sequence, inputs)
        },
        // HealthKit keeps the fraction 0.282, stated as 28.2 % (spec F4-percent), never as the binary64 product
        // 28.199999999999996.
        GoldenCase("body-fat-percentage-fraction", sequence: 17) { sequence in
            try GoldenFixtures.export(
                GoldenFixtures.quantity(.bodyFatPercentage, HKQuantity(unit: .percent(), doubleValue: 0.282), uuid: GoldenFixtures.uuid(17)),
                sequence: sequence
            )
        }
    ]

    /// Sequences 20-39: how the sample's writer (`HKSourceRevision`) travels once the caller classified its source as an
    /// application, and what an unclassified source states.
    static let writers: [GoldenCase] = [
        GoldenCase("writer-foreign-application", sequence: 20) { sequence in
            try GoldenFixtures.export(attributedHeartRate(uuid: 20, writer: GoldenFixtures.foreignWriter), sequence: sequence, .applicationWriter)
        },
        // The converter states version 1.2.3 build 42 and HealthKit records revision version 42: the shape a real
        // device produces. The tokens differ, so the writer travels as a second application Device of the same bundle.
        GoldenCase("writer-self-build-equals-revision", sequence: 21) { sequence in
            var inputs = ExportInputs.applicationWriter
            inputs.converter = GoldenFixtures.selfConverter(version: "1.2.3", build: "42")
            return try GoldenFixtures.export(attributedHeartRate(uuid: 21, writer: GoldenFixtures.selfWriter(revisionVersion: "42")), sequence: sequence, inputs)
        },
        GoldenCase("writer-self-older-build", sequence: 22) { sequence in
            var inputs = ExportInputs.applicationWriter
            inputs.converter = GoldenFixtures.selfConverter(version: "1.2.3", build: "43")
            return try GoldenFixtures.export(attributedHeartRate(uuid: 22, writer: GoldenFixtures.selfWriter(revisionVersion: "42")), sequence: sequence, inputs)
        },
        // No build and a version equal to the revision's: the only shape whose writer token equals the converter's.
        GoldenCase("writer-self-token-identical", sequence: 23) { sequence in
            var inputs = ExportInputs.applicationWriter
            inputs.converter = GoldenFixtures.selfConverter(version: "42", build: nil)
            return try GoldenFixtures.export(attributedHeartRate(uuid: 23, writer: GoldenFixtures.selfWriter(revisionVersion: "42")), sequence: sequence, inputs)
        },
        GoldenCase("writer-host-equals-converter-host", sequence: 24) { sequence in
            var inputs = ExportInputs.applicationWriter
            inputs.converterHost = try HostDevice(operatingSystemVersion: "26.1.0", name: "Phone", manufacturer: "Apple", modelNumber: "iPhone17,1")
            return try GoldenFixtures.export(attributedHeartRate(uuid: 24, writer: GoldenFixtures.foreignWriter), sequence: sequence, inputs)
        },
        // An unclassified source states no writer and the Provenance no author; the recording Device the sample's
        // `HKDevice` names stays.
        GoldenCase("writer-omitted", sequence: 25) { sequence in
            var inputs = ExportInputs()
            inputs.options.writer = .omit
            return try GoldenFixtures.export(attributedHeartRate(uuid: 25, writer: GoldenFixtures.foreignWriter), sequence: sequence, inputs)
        },
        GoldenCase("writer-omitted-without-recording-device", sequence: 26) { sequence in
            var inputs = ExportInputs()
            inputs.options.writer = .omit
            return try GoldenFixtures.export(
                GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(26), writer: GoldenFixtures.foreignWriter),
                sequence: sequence,
                inputs
            )
        },
        GoldenCase("writer-blank-name-with-sync-identity", sequence: 27) { sequence in
            var writer = GoldenFixtures.foreignWriter
            writer.name = ""
            return try GoldenFixtures.export(attributedHeartRate(uuid: 27, writer: writer, metadata: syncMetadata), sequence: sequence, .applicationWriter)
        },
        GoldenCase("writer-without-version", sequence: 28) { sequence in
            var writer = GoldenFixtures.foreignWriter
            writer.version = nil
            return try GoldenFixtures.export(attributedHeartRate(uuid: 28, writer: writer), sequence: sequence, .applicationWriter)
        },
        GoldenCase("sync-identity", sequence: 29) { sequence in
            try GoldenFixtures.export(
                attributedHeartRate(uuid: 29, writer: GoldenFixtures.foreignWriter, metadata: syncMetadata),
                sequence: sequence,
                .applicationWriter
            )
        },
        // A name outside ASCII with a precomposed U+00E9: the comparison is scalar by scalar, so a decomposed
        // spelling of the same name would be a different golden.
        GoldenCase("writer-non-ascii-name", sequence: 30) { sequence in
            var writer = GoldenFixtures.foreignWriter
            writer.name = "Sant\u{E9} Journal"
            return try GoldenFixtures.export(attributedHeartRate(uuid: 30, writer: writer), sequence: sequence, .applicationWriter)
        }
    ]

    /// Sequences 40-59: disclosure policies, converter roles, subjects and studies. (Sequence 46 pinned repository ids on
    /// every node, which only the deleted context API could state.)
    static let disclosures: [GoldenCase] = [
        GoldenCase("native-identifier-disclosure", sequence: 40) { sequence in
            var inputs = ExportInputs()
            inputs.options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
            return try GoldenFixtures.export(attributedHeartRate(uuid: 40, writer: GoldenFixtures.foreignWriter), sequence: sequence, inputs)
        },
        GoldenCase("udi-disclosure", sequence: 41) { sequence in
            var inputs = ExportInputs()
            inputs.options.udi = .authorized
            return try GoldenFixtures.export(attributedHeartRate(uuid: 41, writer: GoldenFixtures.foreignWriter), sequence: sequence, inputs)
        },
        GoldenCase("gateway-role", sequence: 42) { sequence in
            var inputs = ExportInputs()
            inputs.options.role = .gateway
            return try GoldenFixtures.export(attributedHeartRate(uuid: 42, writer: GoldenFixtures.foreignWriter), sequence: sequence, inputs)
        },
        GoldenCase("gateway-application-role", sequence: 43) { sequence in
            var inputs = ExportInputs()
            inputs.options.role = .gatewayApplication(.test(name: "Cuff Companion", bundleIdentifier: "com.example.cuff", version: "3.1"))
            return try GoldenFixtures.export(attributedHeartRate(uuid: 43, writer: GoldenFixtures.foreignWriter), sequence: sequence, inputs)
        },
        GoldenCase("bundled-patient-subject", sequence: 44) { sequence in
            var inputs = ExportInputs()
            inputs.subject = .bundled(.test(.patient, "example"), Patient())
            return try GoldenFixtures.export(attributedHeartRate(uuid: 44, writer: GoldenFixtures.foreignWriter), sequence: sequence, inputs)
        },
        GoldenCase("two-study-enrollments", sequence: 45) { sequence in
            var inputs = ExportInputs()
            inputs.studies = [.test("study-a"), .test("study-b")]
            return try GoldenFixtures.export(attributedHeartRate(uuid: 45, writer: GoldenFixtures.foreignWriter), sequence: sequence, inputs)
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

    /// A 120/80 reading from the watch; the correlation and its two components each take one of the ordinals.
    static func bloodPressure(uuid ordinal: UInt8 = 9, components: (systolic: UInt8, diastolic: UInt8) = (0x91, 0x92)) throws -> HKCorrelation {
        func component(_ type: HKQuantityTypeIdentifier, _ value: Double, uuid: UInt8) throws -> HKQuantitySample {
            try GoldenFixtures.quantity(type, HKQuantity(unit: .millimeterOfMercury(), doubleValue: value), uuid: GoldenFixtures.uuid(uuid), device: GoldenFixtures.watch)
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
            metadata: GoldenFixtures.timeZoneMetadata
        )
        return try StoredSampleFixtures.stored(correlation, uuid: GoldenFixtures.uuid(ordinal))
    }
}

#endif
