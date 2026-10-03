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


/// Every content-corpus vector, generated from the public catalog and the generated contracts: the input coverage
/// of the step-7 oracle (synthesis section 16, O2), in a fixed order, each under a stable id. The grid is the same
/// on every platform; a platform without a record type skips its vectors when it rebuilds them.
///
/// Families: every quantity type over a value sweep (every percent type also over fractions, insulin delivery also
/// with its required reason, every unit-bound type also in another unit), every category type over raw values -1
/// through 8, effective-time edges for each effective kind, blood-pressure member variants, every workout activity
/// raw with and without statistics, State of Mind permutations, scored assessments, each metadata key valid,
/// wrongly typed and absent, ECG evidence and time edges, every recording and clinical document builder,
/// multi-fault precedence, retraction targets, the catalog projections, reverse projections, and round trips of
/// converted heart-rate and body-mass Observations.
///
/// Ids are stable: an id names one input for as long as the corpus exists. A regeneration may add vectors (each
/// inside its family, so later lines move) but never drops an id or restates its input; `ContentCorpusChanges`
/// enforces both. Inputs derived from what the rewrite regenerates are frozen here: the unit spellings are listed,
/// and the body-mass-index vectors keep the inputs they were recorded with. Generator G3 (M1) generates the BMI
/// contract as `HealthKitContract.bodyMassIndex` and refuses a catalog measurement named `body-mass-index`, so
/// neither `MeasurementCatalog.all` nor `HealthKitMeasurementCatalog.all` lists it:
/// `quantity/HKQuantityTypeIdentifierBodyMassIndex/...` keep their fallback unit and value, and
/// `reverse/body-mass-index` keeps its literal Observation.
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

    /// Another unit of the same dimension for each bound unit, by the bound unit's string, so the reading converts.
    /// A bound unit without one (count, IU, dB SPL, the effort score) has no such vector. No alternate is a molar
    /// unit: its unit string prints the molar mass rounded, so the corpus could not restate it exactly.
    static let alternateUnits: [String: String] = [
        "kg": "lb", "g": "oz", "mg": "g", "mcg": "mg", "m": "ft", "cm": "in", "m/s": "km/hr", "count/min": "count/s",
        "min": "hr", "ms": "s", "degC": "degF", "kcal": "kJ", "W": "kW", "L": "mL", "mL": "fl_oz_us",
        "mg/dL": "g/L", "mcS": "S", "mL/min·kg": "L/min·kg", "kcal/hr·kg": "kJ/hr·kg",
        "L/min": "mL/min", "%": "count"
    ]

    /// Every generated measurement contract by id, the first catalog winning, as everywhere else.
    static let contracts: [String: MeasurementContract] = Dictionary(
        (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).map { ($0.id, $0) }
    ) { first, _ in first }

    /// The measurement id of body-mass index, whose contract no generated catalog lists.
    static let bodyMassIndexID = "body-mass-index"

    /// Every vector, in corpus order.
    static var vectors: [ContentCorpusVector] {
        quantities + categories + times + correlations + workouts + statesOfMind + assessments + bareRows
            + metadata + precedence + electrocardiograms + recordings + clinicalDocuments + retractions + catalog + reverseProjections
            + roundTrips
    }

    /// The vectors of every quantity row: a value the contract admits, the sweep, a percent type's fractions, insulin
    /// delivery's sweep again with the reason it requires, and the admitted value in another unit.
    static var quantities: [ContentCorpusVector] {
        rows(prefix: "HKQuantityTypeIdentifier").flatMap { row -> [ContentCorpusVector] in
            let identifier = HKQuantityTypeIdentifier(rawValue: row.sourceTypeIdentifier)
            let measurement = contract(row)
            guard let type = HKObjectType.quantityType(forIdentifier: identifier), let unit = quantityUnit(type, contract: measurement) else {
                return []
            }
            let isPercent = measurement?.quantity?.code == "%"
            let admitted = isPercent ? 0.25 : representative(measurement)
            let values = [("row", admitted)] + sweep.map { (String($0), $0) } + (isPercent ? fractions.map { ("fraction-\($0)", $0) } : [])
            func vector(_ label: String, _ value: Double, unit: HKUnit, metadata: [String: ContentCorpusMetadataValue] = zone) -> ContentCorpusVector {
                let record = ContentCorpusRecord.quantity(type: row.sourceTypeIdentifier, value: value, unit: unit.unitString)
                return convert("quantity/\(row.sourceTypeIdentifier)/\(label)", ContentCorpusSource(record, end: start + span(measurement), metadata: metadata))
            }
            var vectors = values.map { vector($0, $1, unit: unit) }
            if identifier == .insulinDelivery {
                let basal = zone.merging([HKMetadataKeyInsulinDeliveryReason: .integer(HKInsulinDeliveryReason.basal.rawValue)]) { $1 }
                vectors += values.map { vector("basal/\($0)", $1, unit: unit, metadata: basal) }
            }
            if let alternate = alternateUnit(type, bound: unit, contract: measurement) {
                let converted = HKQuantity(unit: unit, doubleValue: admitted).doubleValue(for: alternate)
                vectors.append(vector("alternate-unit", converted, unit: alternate))
            }
            return vectors
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

    /// The vector converting `source`, under `id`.
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

    /// Another unit measuring `type` than the one its contract binds, when it binds one and ``alternateUnits``
    /// names another of its dimension.
    static func alternateUnit(_ type: HKQuantityType, bound: HKUnit, contract: MeasurementContract?) -> HKUnit? {
        guard let code = contract?.quantity?.code, code == "%" || HealthKitCatalog.unit(forUCUMCode: code) == bound,
              let alternate = alternateUnits[bound.unitString].map(HKUnit.init(from:)), type.is(compatibleWith: alternate) else {
            return nil
        }
        return alternate
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
