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


/// Every content-corpus vector, generated from the public catalog alone: the input coverage of the step-7 oracle
/// (synthesis section 16, O2), in a fixed order, each under a stable id.
///
/// Families: every quantity type over a value sweep (and every percent type over fractions), every category type
/// over raw values -1 through 8, effective-time edges for each effective kind, blood-pressure member variants,
/// every workout activity raw with and without statistics, State of Mind permutations, scored assessments, each
/// metadata key valid, wrongly typed and absent, ECG evidence edges, every recording and clinical document
/// builder, multi-fault precedence, retraction targets, and the catalog projections. Vectors are appended, never
/// renumbered: an id names the same input for as long as the corpus exists.
enum ContentCorpusGrid {
    /// 2026-08-17T22:30:00Z, 15:30 in Los Angeles: when every vector's record starts unless it states otherwise.
    static let start = GoldenFixtures.sampleStart.timeIntervalSince1970
    /// The default metadata: the Los Angeles zone and nothing else.
    static let zone: [String: ContentCorpusMetadataValue] = [HKMetadataKeyTimeZone: .string(GoldenFixtures.timeZone)]

    /// The quantity sweep: zero, a fraction, a negative, a tiny and a huge value, and the non-finite values.
    static let sweep: [Double] = [0, 1.5, -1, 1e-7, 1e21, .nan, .infinity, -.infinity]
    /// Fractions a percent type is stated in, among them the binary64 products that print with a tail.
    static let fractions: [Double] = [0.07, 0.14, 0.28, 0.282, 0.29, 0.55, 0.56, 0.57, 0.58, 0.98, 0.5, 1]

    /// Units for quantity types whose contract names no unit the catalog binds, tried in order.
    static let fallbackUnits: [HKUnit] = [
        .count(), .millimeterOfMercury(), .percent(), .second(), .meter(), .gramUnit(with: .kilo), .kilocalorie(),
        .degreeCelsius(), .count().unitDivided(by: .minute()), .meter().unitDivided(by: .second()), .watt(),
        .decibelAWeightedSoundPressureLevel(), .internationalUnit(), .literUnit(with: .milli), .lux(), .siemen(),
        .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)), .literUnit(with: .milli).unitDivided(by: .minute())
    ]

    /// Every generated measurement contract by id; the first catalog wins, as everywhere else.
    static let contracts: [String: MeasurementContract] = Dictionary(
        (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).map { ($0.id, $0) }
    ) { first, _ in first }

    /// Every vector, in corpus order.
    static var vectors: [ContentCorpusVector] {
        quantities + categories + times + correlations + workouts + statesOfMind + assessments + bareRows
            + metadata + precedence + electrocardiograms + recordings + clinicalDocuments + retractions + catalog + reverseProjections
    }

    /// The vectors of every quantity row: a value the contract admits, the sweep, and for a percent type the fractions.
    static var quantities: [ContentCorpusVector] {
        rows(prefix: "HKQuantityTypeIdentifier").flatMap { row -> [ContentCorpusVector] in
            let identifier = HKQuantityTypeIdentifier(rawValue: row.sourceTypeIdentifier)
            let measurement = contract(row)
            guard let type = HKObjectType.quantityType(forIdentifier: identifier), let unit = quantityUnit(type, contract: measurement) else {
                return []
            }
            let isPercent = measurement?.quantity?.code == "%"
            let values = [("row", isPercent ? 0.25 : representative(measurement))]
                + sweep.map { (String($0), $0) }
                + (isPercent ? fractions.map { ("fraction-\($0)", $0) } : [])
            return values.map { label, value in
                convert(
                    "quantity/\(row.sourceTypeIdentifier)/\(label)",
                    ContentCorpusSource(.quantity(type: row.sourceTypeIdentifier, value: value, unit: unit.unitString), end: start + span(measurement))
                )
            }
        }
    }

    /// The vectors of every category row: each raw value from -1 through 8, past the largest any table admits (7).
    static var categories: [ContentCorpusVector] {
        rows(prefix: "HKCategoryTypeIdentifier").flatMap { row -> [ContentCorpusVector] in
            guard HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: row.sourceTypeIdentifier)) != nil else {
                return []
            }
            var metadata = zone
            if row.sourceTypeIdentifier == HKCategoryTypeIdentifier.menstrualFlow.rawValue {
                metadata[HKMetadataKeyMenstrualCycleStart] = .boolean(true)
            }
            return (-1...8).map { raw in
                convert(
                    "category/\(row.sourceTypeIdentifier)/\(raw)",
                    ContentCorpusSource(.category(type: row.sourceTypeIdentifier, value: raw), end: start + span(contract(row)), metadata: metadata)
                )
            }
        }
    }

    /// Effective-time edges for a dateTime, a dateTime-or-Period, a Period and a non-zero Period measurement.
    static var times: [ContentCorpusVector] {
        let records: [ContentCorpusRecord] = [
            .quantity(type: HKQuantityTypeIdentifier.bodyMass.rawValue, value: 70, unit: "kg"),
            .quantity(type: HKQuantityTypeIdentifier.heartRate.rawValue, value: 72, unit: "count/min"),
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
                [("none", [:]), ("los-angeles", zone)].map { zoneLabel, metadata in
                    convert("time/\(type)/\(label)/\(zoneLabel)", ContentCorpusSource(record, start: instant, end: instant + duration, metadata: metadata))
                }
            }
            return intervals + zones + edges
        }
    }

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
    /// a .250 fraction, exact half-millisecond ties, the year 9999/10000 and year 1/0 boundaries, and 1500.
    static let instants: [(String, Double)] = [
        ("repeated-hour-first", 1_793_521_800), ("repeated-hour-second", 1_793_525_400), ("lmt-1800", -5_364_662_400),
        ("fraction-250", 1_787_148_600.25), ("tie-even", 1_787_148_600.0625), ("tie-odd", 1_787_148_600.1875),
        ("year-9999", 253_402_300_799), ("year-10000", 253_402_300_800), ("pre-reform-1500", -14_831_769_600),
        ("year-1", -62_135_596_800), ("year-0", -62_135_596_801)
    ]

    static func convert(_ id: String, _ source: ContentCorpusSource) -> ContentCorpusVector {
        ContentCorpusVector(id: id, input: .convert(source: source))
    }

    /// The inventory rows of one identifier family, in row order.
    static func rows(prefix: String) -> [HealthKitContractRow] {
        HealthKitContract.rows.filter { $0.sourceTypeIdentifier.hasPrefix(prefix) }
    }

    /// The generated contract of a row's first measurement, if the catalogs carry one.
    static func contract(_ row: HealthKitContractRow) -> MeasurementContract? {
        row.measurementIDs.first.flatMap { contracts[$0] }
    }

    /// How long a record of the contract lasts: a minute for a Period measurement, an instant otherwise.
    static func span(_ contract: MeasurementContract?) -> Double {
        contract?.effective == .period ? 60 : 0
    }

    /// The unit the contract's UCUM code binds, else the first fallback unit that measures the type.
    static func quantityUnit(_ type: HKQuantityType, contract: MeasurementContract?) -> HKUnit? {
        if contract?.quantity?.code == "%" {
            return .percent()
        }
        if let code = contract?.quantity?.code, let unit = HealthKitCatalog.unit(forUCUMCode: code), type.is(compatibleWith: unit) {
            return unit
        }
        return fallbackUnits.first { type.is(compatibleWith: $0) }
    }

    /// A value the contract's domain admits, so every row has one vector that converts if anything does.
    static func representative(_ contract: MeasurementContract?) -> Double {
        guard let domain = contract?.quantity?.valueDomain else {
            return 1
        }
        return [1, 50, 100, 1_000, 0.5, 0].first { domain.contains(Decimal($0)) } ?? 1
    }
}


extension ContentCorpusSource {
    /// A record under the default facts: starting at the base instant, in Los Angeles, attributed to no writer,
    /// without a device, in the default context.
    init(
        _ record: ContentCorpusRecord,
        start: Double = ContentCorpusGrid.start,
        end: Double? = nil,
        metadata: [String: ContentCorpusMetadataValue] = ContentCorpusGrid.zone,
        writer: Writer = .unattributed
    ) {
        self.init(record: record, start: start, end: end ?? start, metadata: metadata, device: nil, writer: writer, context: .plain)
    }
}

#endif
