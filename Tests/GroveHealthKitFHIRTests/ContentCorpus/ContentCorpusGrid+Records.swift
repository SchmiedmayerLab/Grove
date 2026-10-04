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


/// Correlations, workouts, State of Mind, scored assessments and the rows only a bare sample reaches.
extension ContentCorpusGrid {
    /// The distance types a workout may total, each with its own sum so the vector shows which one is read.
    static let distanceStatistics: [ContentCorpusStatistic] = [
        HKQuantityTypeIdentifier.distanceWalkingRunning, .distanceCycling, .distanceSwimming, .distanceWheelchair,
        .distanceCrossCountrySkiing, .distanceRowing, .distanceDownhillSnowSports, .distancePaddleSports, .distanceSkatingSports
    ].enumerated().map { index, type in
        ContentCorpusStatistic(type: type.rawValue, unit: "m", sum: 1_001 + Double(index))
    }

    /// Blood pressure: the pair, missing and extra members, member values, and member metadata of every kind.
    static var correlations: [ContentCorpusVector] {
        let systolic = HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue
        let diastolic = HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue
        let kolkata: [String: ContentCorpusMetadataValue] = [HKMetadataKeyTimeZone: .string("Asia/Kolkata")]
        let kathmandu: [String: ContentCorpusMetadataValue] = [HKMetadataKeyTimeZone: .string("Asia/Kathmandu")]
        func pair(
            systolic systolicMetadata: [String: ContentCorpusMetadataValue] = [:],
            diastolic diastolicMetadata: [String: ContentCorpusMetadataValue] = [:]
        ) -> [ContentCorpusMember] {
            [
                ContentCorpusMember(type: systolic, value: 120, metadata: systolicMetadata),
                ContentCorpusMember(type: diastolic, value: 80, metadata: diastolicMetadata)
            ]
        }
        func pressure(
            _ label: String,
            _ members: [ContentCorpusMember],
            metadata: [String: ContentCorpusMetadataValue] = zone,
            end: Double = start
        ) -> ContentCorpusVector {
            convert("correlation/blood-pressure/\(label)", ContentCorpusSource(.correlation(type: bloodPressure, members: members), end: end, metadata: metadata))
        }
        let sync: [String: ContentCorpusMetadataValue] = [HKMetadataKeySyncIdentifier: .string("member-sync"), HKMetadataKeySyncVersion: .integer(1)]
        let entered: [String: ContentCorpusMetadataValue] = [HKMetadataKeyWasUserEntered: .boolean(true)]
        return [
            pressure("row", pair()), pressure("interval", pair(), end: start + 60),
            pressure("missing-systolic", [pair()[1]]), pressure("missing-diastolic", [pair()[0]]), pressure("no-members", []),
            pressure("extra-heart-rate", pair() + [ContentCorpusMember(type: heartRate, value: 60, unit: "count/min")]),
            pressure("systolic-nan", [ContentCorpusMember(type: systolic, value: .nan), pair()[1]]),
            pressure("systolic-negative", [ContentCorpusMember(type: systolic, value: -1), pair()[1]]),
            pressure("systolic-huge", [ContentCorpusMember(type: systolic, value: 1e21), pair()[1]]),
            pressure("systolic-fractional", [ContentCorpusMember(type: systolic, value: 120.5), pair()[1]]),
            pressure("systolic-hundredths", [ContentCorpusMember(type: systolic, value: 121.37), pair()[1]]),
            pressure("diastolic-zero", [pair()[0], ContentCorpusMember(type: diastolic, value: 0)]),
            pressure("member-zone-differs", pair(systolic: kolkata)),
            pressure("member-zones-agree-correlation-none", pair(systolic: kolkata, diastolic: kolkata), metadata: [:]),
            pressure("member-zones-disagree-correlation-none", pair(systolic: kolkata, diastolic: kathmandu), metadata: [:]),
            pressure("member-zone-invalid-correlation-none", pair(systolic: [HKMetadataKeyTimeZone: .string("Not/A-Time-Zone")]), metadata: [:]),
            pressure("member-user-entered", pair(systolic: [HKMetadataKeyWasUserEntered: .boolean(true)])),
            pressure(
                "member-user-entered-correlation-not",
                pair(diastolic: [HKMetadataKeyWasUserEntered: .boolean(true)]),
                metadata: zone.merging([HKMetadataKeyWasUserEntered: .boolean(false)]) { _, new in new }
            ),
            pressure("member-foreign-key", pair(diastolic: ["org.example.member": .string("x")])),
            pressure("member-sync-identity", pair(systolic: sync)),
            pressure("member-user-entered-both", pair(systolic: entered, diastolic: entered)),
            pressure(
                "member-user-entered-both-correlation-not",
                pair(systolic: entered, diastolic: entered),
                metadata: zone.merging([HKMetadataKeyWasUserEntered: .boolean(false)]) { _, new in new }
            ),
            pressure("member-zone-one-correlation-none", pair(systolic: kolkata), metadata: [:]),
            pressure(
                "member-zone-alias-correlation-none",
                pair(systolic: [HKMetadataKeyTimeZone: .string("US/Pacific")], diastolic: [HKMetadataKeyTimeZone: .string("America/Los_Angeles")]),
                metadata: [:]
            ),
            pressure("member-zone-invalid-correlation-zone", pair(systolic: [HKMetadataKeyTimeZone: .string("Not/A-Time-Zone")])),
            pressure(
                "member-foreign-keys-shared",
                pair(systolic: ["org.example.shared": .string("s")], diastolic: ["org.example.member": .string("x")]),
                metadata: zone.merging(["org.example.shared": .string("c")]) { _, new in new }
            ),
            convert("correlation/food/row", ContentCorpusSource(.correlation(
                type: HKCorrelationTypeIdentifier.food.rawValue,
                members: [ContentCorpusMember(type: HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue, value: 320, unit: "kcal")]
            )))
        ]
    }

    /// Every activity raw (with every distance type, so the vector shows which one counts), each statistic alone
    /// and together, unusual readings and durations.
    static var workouts: [ContentCorpusVector] {
        let running = HKWorkoutActivityType.running.rawValue
        let sweep = ((0...90).map(UInt.init) + [3_000, 9_999]).map { raw in
            convert("workout/activity/\(raw)", workout(raw, statistics: distanceStatistics))
        }
        let statistics = workoutStatistics.map { label, statistics in
            convert("workout/statistics/\(label)", workout(running, statistics: statistics))
        }
        let durations = [("zero", 0.0), ("fractional", 1.5), ("negative", -1), ("nan", .nan)].map { label, duration in
            convert(
                "workout/duration/\(label)",
                ContentCorpusSource(.workout(activity: running, duration: duration, statistics: []), end: start + 3_600)
            )
        }
        var reversed = workout(running, statistics: [])
        reversed.end = start - 60
        var userEntered = workout(running, statistics: [])
        userEntered.metadata[HKMetadataKeyWasUserEntered] = .boolean(true)
        return sweep + statistics + durations + [convert("workout/reversed", reversed), convert("workout/user-entered", userEntered)]
    }

    /// Each workout statistic alone, all of them, partial heart-rate readings, readings no contract admits, and a
    /// distance and an energy stated in another unit than the one the converter reads.
    static var workoutStatistics: [(String, [ContentCorpusStatistic])] {
        func statistic(_ type: HKQuantityTypeIdentifier, _ unit: String, sum: Double? = nil, average: Double? = nil) -> ContentCorpusStatistic {
            ContentCorpusStatistic(type: type.rawValue, unit: unit, sum: sum, average: average)
        }
        func heart(average: Double?, minimum: Double?, maximum: Double?) -> ContentCorpusStatistic {
            ContentCorpusStatistic(type: heartRate, unit: "count/min", average: average, minimum: minimum, maximum: maximum)
        }
        let distance = statistic(.distanceWalkingRunning, "m", sum: 10_000)
        let energy = statistic(.activeEnergyBurned, "kcal", sum: 640)
        let steps = statistic(.stepCount, "count", sum: 9_000)
        let flights = statistic(.flightsClimbed, "count", sum: 12)
        let strokes = statistic(.swimmingStrokeCount, "count", sum: 900)
        let fullHeart = heart(average: 140, minimum: 95, maximum: 171)
        return [
            ("none", []), ("distance", [distance]), ("energy", [energy]), ("steps", [steps]), ("flights", [flights]),
            ("strokes", [strokes]), ("heart-rate", [fullHeart]), ("all", [fullHeart, strokes, flights, steps, energy, distance]),
            ("heart-rate-average-only", [heart(average: 140, minimum: nil, maximum: nil)]),
            ("heart-rate-extremes-only", [heart(average: nil, minimum: 95, maximum: 171)]),
            ("heart-rate-without-readings", [heart(average: nil, minimum: nil, maximum: nil)]),
            ("heart-rate-nan-average", [heart(average: .nan, minimum: 95, maximum: 171)]),
            ("energy-nan", [statistic(.activeEnergyBurned, "kcal", sum: .nan)]), ("energy-zero", [statistic(.activeEnergyBurned, "kcal", sum: 0)]),
            ("distance-negative", [statistic(.distanceWalkingRunning, "m", sum: -1)]), ("steps-fractional", [statistic(.stepCount, "count", sum: 1.5)]),
            ("energy-average-only", [statistic(.activeEnergyBurned, "kcal", average: 320)]),
            ("distance-km", [statistic(.distanceWalkingRunning, "km", sum: 10.5)]), ("energy-kj", [statistic(.activeEnergyBurned, "kJ", sum: 2_677.76)])
        ]
    }

    /// Kinds, valences across every classification band, and label and association lists of every shape.
    static var statesOfMind: [ContentCorpusVector] {
        let happy = HKStateOfMind.Label.happy.rawValue
        let work = HKStateOfMind.Association.work.rawValue
        func reflection(
            _ label: String,
            kind: Int = 1,
            valence: Double = 0.5,
            labels: [Int] = [happy],
            associations: [Int] = [work],
            end: Double = start
        ) -> ContentCorpusVector {
            convert(
                "state-of-mind/\(label)",
                ContentCorpusSource(.stateOfMind(kind: kind, valence: valence, labels: labels, associations: associations), end: end)
            )
        }
        let unsortedLabels = [HKStateOfMind.Label.sad, .angry, .happy, .calm].map(\.rawValue)
        let unsortedAssociations = [HKStateOfMind.Association.work, .family, .health, .community].map(\.rawValue)
        return [reflection("row"), reflection("interval", end: start + 60)]
            + [2, 0, 99].map { reflection("kind/\($0)", kind: $0) }
            + [-1, -0.9, -0.6, -0.3, -0.1, 0, 0.1, 0.3, 0.6, 0.9, 1, 0.1 + 0.2].map { reflection("valence/\($0)", valence: $0) }
            + [
                reflection("labels/none", labels: []), reflection("labels/every-raw", labels: Array(0...41)),
                reflection("labels/unsorted", labels: unsortedLabels), reflection("labels/duplicate", labels: [happy, happy, unsortedLabels[1]]),
                reflection("labels/unknown", labels: [999, happy]),
                reflection("associations/none", associations: []), reflection("associations/every-raw", associations: Array(0...21)),
                reflection("associations/unsorted", associations: unsortedAssociations),
                reflection("associations/duplicate", associations: [work, work, unsortedAssociations[1]]),
                reflection("associations/unknown", associations: [999, work])
            ]
    }

    /// GAD-7 and PHQ-9 scores at and beyond both ends of their ranges.
    static var assessments: [ContentCorpusVector] {
        [(HKScoredAssessmentTypeIdentifier.GAD7, [-1, 0, 6, 21, 22]), (.PHQ9, [-1, 0, 14, 27, 28])].flatMap { type, scores in
            let row = HealthKitContract.rows.first { $0.sourceTypeIdentifier == type.rawValue }
            return scores.map { score in
                convert(
                    "assessment/\(type.rawValue)/\(score)",
                    ContentCorpusSource(.assessment(type: type.rawValue, score: score), end: start + span(row.flatMap(contract)))
                )
            }
        }
    }

    /// The sample rows no other family reaches, each as a bare sample through the plain entry point.
    static var bareRows: [ContentCorpusVector] {
        [
            (HKObjectType.audiogramSampleType().identifier, "HKAudiogramSample"),
            (HKObjectType.visionPrescriptionType().identifier, "HKVisionPrescription"),
            (HKObjectType.medicationDoseEventType().identifier, "HKMedicationDoseEvent")
        ].map { type, sampleClass in
            convert("row/\(type)", ContentCorpusSource(.bare(type: type, sampleClass: sampleClass)))
        }
    }

    /// The blood-pressure correlation type identifier.
    static let bloodPressure = HKCorrelationTypeIdentifier.bloodPressure.rawValue
    /// The heart-rate quantity type identifier.
    static let heartRate = HKQuantityTypeIdentifier.heartRate.rawValue

    /// A one-hour workout of `activity` with `statistics`.
    static func workout(_ activity: UInt, statistics: [ContentCorpusStatistic]) -> ContentCorpusSource {
        ContentCorpusSource(.workout(activity: activity, duration: 3_600, statistics: statistics), end: start + 3_600)
    }
}

#endif
