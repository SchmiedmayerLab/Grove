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
import HealthKit


/// Each metadata key valid, wrongly typed and absent, keys a path does not read, and multi-fault precedence.
extension ContentCorpusGrid {
    static let heartRateRecord = ContentCorpusRecord.quantity(type: heartRate, value: 72, unit: "count/min")

    /// Every metadata family, in corpus order.
    static var metadata: [ContentCorpusVector] {
        typedMetadata + userEntered + syncIdentity + unmodeledMetadata + devices
    }

    /// The four keys a single measurement reads: heart-rate motion context, insulin delivery reason, menstrual
    /// cycle start and sexual-activity protection, each absent, at every admitted value, out of range and mistyped.
    static var typedMetadata: [ContentCorpusVector] {
        func family(_ name: String, _ record: ContentCorpusRecord, key: String, _ values: [(String, ContentCorpusMetadataValue?)]) -> [ContentCorpusVector] {
            values.map { label, value in
                var metadata = zone
                metadata[key] = value
                return convert("metadata/\(name)/\(label)", ContentCorpusSource(record, end: start + span(record), metadata: metadata))
            }
        }
        func integers(_ values: [Int], prefix: String = "") -> [(String, ContentCorpusMetadataValue?)] {
            values.map { ("\(prefix)\($0)", .integer($0)) }
        }
        let insulin = ContentCorpusRecord.quantity(type: HKQuantityTypeIdentifier.insulinDelivery.rawValue, value: 2.5, unit: "IU")
        let flow = ContentCorpusRecord.category(type: HKCategoryTypeIdentifier.menstrualFlow.rawValue, value: 2)
        let activity = ContentCorpusRecord.category(type: HKCategoryTypeIdentifier.sexualActivity.rawValue, value: 0)
        let booleans: [(String, ContentCorpusMetadataValue?)] = [("absent", nil), ("true", .boolean(true)), ("false", .boolean(false))]
        return family(
            "heart-rate-motion-context",
            heartRateRecord,
            key: HKMetadataKeyHeartRateMotionContext,
            [("absent", nil)] + integers([0, 1, 2, 3, -1]) + [("string", .string("1")), ("boolean", .boolean(true)), ("double", .double(1.5))]
        ) + family(
            "insulin-delivery-reason",
            insulin,
            key: HKMetadataKeyInsulinDeliveryReason,
            [("absent", nil)] + integers([1, 2, 0, 3]) + [("string", .string("1")), ("boolean", .boolean(true)), ("double", .double(2))]
        ) + family(
            "menstrual-cycle-start",
            flow,
            key: HKMetadataKeyMenstrualCycleStart,
            booleans + integers([1, 0, 2], prefix: "integer-") + [("string", .string("true")), ("double", .double(1))]
        ) + family(
            "sexual-activity-protection",
            activity,
            key: HKMetadataKeySexualActivityProtectionUsed,
            booleans + integers([1, 2], prefix: "integer-") + [("string", .string("yes"))]
        )
    }

    /// `HKMetadataKeyWasUserEntered` on an Observation path in every type, and on a document, which never carries it.
    static var userEntered: [ContentCorpusVector] {
        let values: [(String, ContentCorpusMetadataValue)] = [
            ("true", .boolean(true)), ("false", .boolean(false)), ("integer-1", .integer(1)), ("integer-2", .integer(2)), ("string", .string("true"))
        ]
        let observations = values.map { label, value in
            convert("metadata/was-user-entered/\(label)", ContentCorpusSource(heartRateRecord, metadata: zone.merging([HKMetadataKeyWasUserEntered: value]) { $1 }))
        }
        let document = convert(
            "metadata/was-user-entered/heartbeat-series",
            ContentCorpusSource(.heartbeatSeries(beats: heartbeats), end: start + 2, metadata: zone.merging([HKMetadataKeyWasUserEntered: .boolean(true)]) { $1 })
        )
        return observations + [document]
    }

    /// The sync pair whole, halved, empty and mistyped, with and without a writer to attribute it to.
    static var syncIdentity: [ContentCorpusVector] {
        func pair(_ identifier: ContentCorpusMetadataValue?, _ version: ContentCorpusMetadataValue?) -> [String: ContentCorpusMetadataValue] {
            var metadata = zone
            metadata[HKMetadataKeySyncIdentifier] = identifier
            metadata[HKMetadataKeySyncVersion] = version
            return metadata
        }
        let identifier = ContentCorpusMetadataValue.string("sync-abc")
        let pairs: [(String, [String: ContentCorpusMetadataValue])] = [
            ("pair", pair(identifier, .integer(3))), ("identifier-only", pair(identifier, nil)), ("version-only", pair(nil, .integer(3))),
            ("empty-identifier", pair(.string(""), .integer(3))), ("identifier-number", pair(.integer(7), .integer(3))),
            ("version-string", pair(identifier, .string("3"))), ("version-boolean", pair(identifier, .boolean(true))),
            ("version-negative", pair(identifier, .integer(-1))), ("version-fractional", pair(identifier, .double(2.5))),
            ("version-zero", pair(identifier, .integer(0))), ("version-integral-double", pair(identifier, .double(3)))
        ]
        let attributed = pairs.map { label, metadata in
            convert("metadata/sync/\(label)", ContentCorpusSource(heartRateRecord, metadata: metadata, writer: .foreign))
        }
        return attributed + [convert("metadata/sync/pair-without-writer", ContentCorpusSource(heartRateRecord, metadata: pair(identifier, .integer(3))))]
    }

    /// Keys no path reads, and keys one path reads stated on another: today every allowlisted key passes silently.
    static var unmodeledMetadata: [ContentCorpusVector] {
        func with(_ keys: [String: ContentCorpusMetadataValue]) -> [String: ContentCorpusMetadataValue] {
            zone.merging(keys) { _, new in new }
        }
        let bodyMass = ContentCorpusRecord.quantity(type: HKQuantityTypeIdentifier.bodyMass.rawValue, value: 70, unit: "kg")
        let steps = ContentCorpusRecord.quantity(type: HKQuantityTypeIdentifier.stepCount.rawValue, value: 120, unit: "count")
        let series = ContentCorpusRecord.heartbeatSeries(beats: heartbeats)
        let external: [String: ContentCorpusMetadataValue] = [HKMetadataKeyExternalUUID: .string("external-1")]
        let custom: [String: ContentCorpusMetadataValue] = ["org.example.flag": .boolean(true)]
        let cases: [(String, ContentCorpusSource)] = [
            ("heart-rate/external-uuid", ContentCorpusSource(heartRateRecord, metadata: with(external))),
            ("heart-rate/custom", ContentCorpusSource(heartRateRecord, metadata: with(custom))),
            ("heart-rate/both", ContentCorpusSource(heartRateRecord, metadata: with(external.merging(custom) { _, new in new }))),
            ("heart-rate/menstrual-cycle-start", ContentCorpusSource(heartRateRecord, metadata: with([HKMetadataKeyMenstrualCycleStart: .boolean(true)]))),
            ("heart-rate/insulin-delivery-reason", ContentCorpusSource(heartRateRecord, metadata: with([HKMetadataKeyInsulinDeliveryReason: .integer(1)]))),
            ("heart-rate/ecg-algorithm-version", ContentCorpusSource(heartRateRecord, metadata: with([HKMetadataKeyAppleECGAlgorithmVersion: .integer(2)]))),
            (
                "heart-rate/sexual-activity-protection",
                ContentCorpusSource(heartRateRecord, metadata: with([HKMetadataKeySexualActivityProtectionUsed: .boolean(true)]))
            ),
            ("body-mass/heart-rate-motion-context", ContentCorpusSource(bodyMass, metadata: with([HKMetadataKeyHeartRateMotionContext: .integer(1)]))),
            (
                "step-count/insulin-delivery-reason",
                ContentCorpusSource(steps, end: start + 60, metadata: with([HKMetadataKeyInsulinDeliveryReason: .integer(1)]))
            ),
            ("heartbeat-series/custom", ContentCorpusSource(series, end: start + 2, metadata: with(custom))),
            (
                "heartbeat-series/menstrual-cycle-start",
                ContentCorpusSource(series, end: start + 2, metadata: with([HKMetadataKeyMenstrualCycleStart: .boolean(true)]))
            ),
            ("heartbeat-series/zone-only", ContentCorpusSource(series, end: start + 2))
        ]
        return cases.map { label, source in
            convert("metadata/unmodeled/\(label)", source)
        }
    }

    /// A recording device with and without a per-unit token.
    static var devices: [ContentCorpusVector] {
        [(ContentCorpusSource.Device.watch, "watch"), (.watchWithoutUnitToken, "watch-without-unit-token")].map { device, label in
            var source = ContentCorpusSource(heartRateRecord)
            source.device = device
            return convert("metadata/device/\(label)", source)
        }
    }

    /// Two faults at once: which one the conversion reports pins the order its checks run in.
    static var precedence: [ContentCorpusVector] {
        let invalidZone: [String: ContentCorpusMetadataValue] = [HKMetadataKeyTimeZone: .string("Not/A-Time-Zone")]
        let nanHeartRate = ContentCorpusRecord.quantity(type: heartRate, value: .nan, unit: "count/min")
        let steps = HKQuantityTypeIdentifier.stepCount.rawValue
        let badSync: [String: ContentCorpusMetadataValue] = [HKMetadataKeySyncIdentifier: .string("sync-abc"), HKMetadataKeySyncVersion: .string("3")]
        let motion: [String: ContentCorpusMetadataValue] = [HKMetadataKeyHeartRateMotionContext: .integer(3)]
        let cases: [(String, ContentCorpusSource)] = [
            ("zone-before-value", ContentCorpusSource(nanHeartRate, metadata: invalidZone)),
            ("zone-before-motion-context", ContentCorpusSource(heartRateRecord, metadata: invalidZone.merging(motion) { $1 })),
            ("value-before-motion-context", ContentCorpusSource(nanHeartRate, metadata: zone.merging(motion) { $1 })),
            ("effective-before-value", ContentCorpusSource(.quantity(type: steps, value: .nan, unit: "count"))),
            ("zone-before-effective", ContentCorpusSource(.quantity(type: steps, value: 120, unit: "count"), end: start - 60, metadata: invalidZone)),
            ("value-before-protection", ContentCorpusSource(
                .category(type: HKCategoryTypeIdentifier.sexualActivity.rawValue, value: 1),
                metadata: zone.merging([HKMetadataKeySexualActivityProtectionUsed: .string("yes")]) { $1 }
            )),
            ("value-before-cycle-start", ContentCorpusSource(.category(type: HKCategoryTypeIdentifier.menstrualFlow.rawValue, value: 9), end: start + 60)),
            ("value-before-insulin-reason", ContentCorpusSource(.quantity(type: HKQuantityTypeIdentifier.insulinDelivery.rawValue, value: .nan, unit: "IU"))),
            ("value-before-sync", ContentCorpusSource(nanHeartRate, metadata: zone.merging(badSync) { $1 }, writer: .foreign)),
            ("motion-context-before-sync", ContentCorpusSource(heartRateRecord, metadata: zone.merging(badSync.merging(motion) { $1 }) { $1 }, writer: .foreign)),
            ("zone-before-missing-member", ContentCorpusSource(
                .correlation(type: bloodPressure, members: [ContentCorpusMember(type: HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue, value: 80)]),
                metadata: invalidZone
            )),
            ("first-member-first", ContentCorpusSource(.correlation(type: bloodPressure, members: [
                ContentCorpusMember(type: HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue, value: .nan),
                ContentCorpusMember(type: HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue, value: -1)
            ]))),
            ("effective-before-value-year-10000", ContentCorpusSource(nanHeartRate, start: 253_402_300_800, metadata: [:])),
            ("effective-before-category-value", ContentCorpusSource(
                .category(type: HKCategoryTypeIdentifier.sleepAnalysis.rawValue, value: 9),
                end: start - 60
            )),
            ("zone-before-workout-duration", ContentCorpusSource(
                .workout(activity: HKWorkoutActivityType.running.rawValue, duration: .nan, statistics: []),
                end: start + 3_600,
                metadata: invalidZone
            )),
            ("zone-before-assessment-score", ContentCorpusSource(
                .assessment(type: HKScoredAssessmentTypeIdentifier.GAD7.rawValue, score: 99),
                metadata: invalidZone
            )),
            ("empty-series-before-sync", ContentCorpusSource(.heartbeatSeries(beats: []), end: start + 2, metadata: zone.merging(badSync) { $1 }, writer: .foreign)),
            ("value-before-unmodeled-warning", ContentCorpusSource(nanHeartRate, metadata: zone.merging(["org.example.flag": .boolean(true)]) { $1 }))
        ]
        var deviceOmission = ContentCorpusSource(nanHeartRate)
        deviceOmission.device = .watchWithoutUnitToken
        return (cases + [("value-before-device-omission", deviceOmission)]).map { label, source in
            convert("precedence/\(label)", source)
        }
    }

    /// How long a record of the row lasts; a record of another kind is an instant.
    static func span(_ record: ContentCorpusRecord) -> Double {
        let type: String? = switch record {
        case .quantity(let type, _, _), .category(let type, _): type
        default: nil
        }
        return span(HealthKitContract.rows.first { $0.sourceTypeIdentifier == type }.flatMap(contract))
    }
}

#endif
