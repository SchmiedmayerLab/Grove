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


/// Effective-time edges, and the round trips that read converted Observations back.
extension ContentCorpusGrid {
    /// No zone, an unknown name, a number, and named zones with odd, half-hour and quarter-hour offsets.
    static let timeZones: [(String, [String: ContentCorpusMetadataValue])] = [
        ("none", [:]),
        ("invalid", [HKMetadataKeyTimeZone: .string("Not/A-Time-Zone")]),
        ("wrong-type", [HKMetadataKeyTimeZone: .integer(42)]),
        ("los-angeles", [HKMetadataKeyTimeZone: .string("America/Los_Angeles")]),
        ("kolkata", [HKMetadataKeyTimeZone: .string("Asia/Kolkata")]),
        ("kathmandu", [HKMetadataKeyTimeZone: .string("Asia/Kathmandu")]),
        ("st-johns", [HKMetadataKeyTimeZone: .string("America/St_Johns")]),
        ("utc", [HKMetadataKeyTimeZone: .string("UTC")])
    ]

    /// Both occurrences of Los Angeles's repeated 2026 hour, its local mean time in 1800 (a non-minute offset),
    /// a .250 fraction, exact half-millisecond ties, the year 9999/10000 and year 1/0 boundaries, 1500, and
    /// 1960-01-01T12:00:00Z, before 1970 at a whole-hour offset.
    static let instants: [(String, Double)] = [
        ("repeated-hour-first", 1_793_521_800), ("repeated-hour-second", 1_793_525_400), ("lmt-1800", -5_364_662_400),
        ("fraction-250", 1_787_148_600.25), ("tie-even", 1_787_148_600.0625), ("tie-odd", 1_787_148_600.1875),
        ("year-9999", 253_402_300_799), ("year-10000", 253_402_300_800), ("pre-reform-1500", -14_831_769_600),
        ("year-1", -62_135_596_800), ("year-0", -62_135_596_801), ("pre-1970", -315_576_000)
    ]

    /// The zones every instant is stated in: none, Los Angeles, and UTC by name (which keeps its `timezone`
    /// extension at any instant, also before 1970).
    static let instantZones: [(String, [String: ContentCorpusMetadataValue])] = [
        ("none", [:]), ("los-angeles", zone), ("utc", [HKMetadataKeyTimeZone: .string("UTC")])
    ]

    /// The records whose converted Observations the round trips read back: a dateTime body mass and heart rate.
    static let roundTripTypes: Set<String> = [HKQuantityTypeIdentifier.bodyMass.rawValue, heartRate]

    /// Effective-time edges for a dateTime, a dateTime-or-Period, a Period and a non-zero Period measurement.
    static var times: [ContentCorpusVector] {
        let records: [ContentCorpusRecord] = [
            .quantity(type: HKQuantityTypeIdentifier.bodyMass.rawValue, value: 70, unit: "kg"),
            .quantity(type: heartRate, value: 72, unit: "count/min"),
            .quantity(type: HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue, value: 650, unit: "kcal"),
            .quantity(type: HKQuantityTypeIdentifier.stepCount.rawValue, value: 120, unit: "count")
        ]
        return records.flatMap { record -> [ContentCorpusVector] in
            guard case .quantity(let type, _, _) = record else {
                return []
            }
            let duration = span(HealthKitContract.rows.first { $0.sourceTypeIdentifier == type }.flatMap(contract))
            let intervals = [("equal", 0.0), ("interval-45s", 45), ("reversed-45s", -45)].map { label, offset in
                convert("time/\(type)/\(label)", ContentCorpusSource(record, end: start + offset))
            }
            let zones = timeZones.map { label, metadata in
                convert("time/\(type)/zone-\(label)", ContentCorpusSource(record, end: start + 45, metadata: metadata))
            }
            let edges = instants.flatMap { label, instant in
                instantZones.map { zoneLabel, metadata in
                    convert("time/\(type)/\(label)/\(zoneLabel)", ContentCorpusSource(record, start: instant, end: instant + duration, metadata: metadata))
                }
            }
            return intervals + zones + edges
        }
    }

    /// The time and metadata vectors of a heart rate or body mass before 4000 (HealthKit creates no sample later),
    /// converted and read back from the wire bytes: zones, offsets, ties, minted identifiers, manual entry and sync
    /// identity as the reverse projection reads them.
    static var roundTrips: [ContentCorpusVector] {
        (times + metadata).compactMap { vector in
            guard case .convert(let source) = vector.input, case .quantity(let type, _, _) = source.record, roundTripTypes.contains(type),
                  max(source.start, source.end) < 64_092_211_200 else {
                return nil
            }
            return ContentCorpusVector(id: "round-trip/\(vector.id)", input: .roundTrip(source: source))
        }
    }
}

#endif
