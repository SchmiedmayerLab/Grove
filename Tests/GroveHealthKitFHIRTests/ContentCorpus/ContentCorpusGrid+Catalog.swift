//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit


/// Retractions, the catalog projections and reverse projections.
extension ContentCorpusGrid {
    /// The spellings both unit lookups are asked for: every UCUM code and display unit the bindings used when the
    /// corpus was recorded, and spellings they do not use. Frozen, since the bindings are what the rewrite rewires;
    /// `catalog/unit-bindings` pins the bindings themselves.
    static let unitSpellings = [
        "", "%", "/h", "/min", "Cel", "IU", "L", "L/min", "UV index", "W", "[iU]", "beats/minute", "breaths/minute", "cm", "dB(SPL)",
        "dB[SPL]", "drinks", "falls", "flights", "g", "kcal", "kcal/(kg.h)", "kcal/kg/h", "kg", "kg/m2", "m", "m/s", "mL", "mL/kg/min",
        "mg", "mg/dL", "min", "mmHg", "mm[Hg]", "ms", "not-a-unit", "puffs", "pushes", "revolutions/minute", "score", "steps", "strokes",
        "uS", "ug", "{drinks}", "{falls}", "{flights}", "{puff}", "{pushes}", "{score}", "{steps}", "{strokes}", "{uvindex}"
    ]

    /// The rows whose deletion is also named with the store's UUID disclosed: one per kind of target set (a single
    /// Observation, a panel, a session, an ECG with its derived child, a recording document, a clinical record).
    static let disclosedRetractions = [
        HKQuantityTypeIdentifier.heartRate.rawValue, HKCorrelationTypeIdentifier.bloodPressure.rawValue, HKWorkoutTypeIdentifier,
        HKObjectType.electrocardiogramType().identifier, HKDataTypeIdentifierHeartbeatSeries, "HKClinicalTypeIdentifierLabResultRecord"
    ]

    /// The deletion of a record of every inventory row, then of a few rows with the native identifier disclosed.
    static var retractions: [ContentCorpusVector] {
        HealthKitContract.rows.map { row in
            ContentCorpusVector(id: "retraction/\(row.sourceTypeIdentifier)", input: .retract(type: row.sourceTypeIdentifier))
        } + disclosedRetractions.map { type in
            ContentCorpusVector(id: "retraction/native-identifier/\(type)", input: .retract(type: type, disclosure: .nativeIdentifier))
        }
    }

    /// Every inventory row with its outputs and field dispositions, the unit bindings, and both unit lookups for
    /// every spelling.
    static var catalog: [ContentCorpusVector] {
        let entries = HealthKitContract.rows.map { row in
            ContentCorpusVector(id: "catalog/entry/\(row.sourceTypeIdentifier)", input: .catalog(projection: .entry(type: row.sourceTypeIdentifier)))
        }
        return entries + [
            ContentCorpusVector(id: "catalog/unit-bindings", input: .catalog(projection: .unitBindings)),
            ContentCorpusVector(id: "catalog/unit-spellings", input: .catalog(projection: .unitSpellings(spellings: unitSpellings)))
        ]
    }

    /// A minimal Observation of every generated measurement and of body-mass index, the edges of the reverse
    /// projection (Period and missing effective times, missing and mismatched values, manual entry, zones, a pre-1582
    /// date, sync identity and amendment, blood-pressure components, and another source type's lineage), and its
    /// multi-fault precedence.
    ///
    /// Body-mass index, which no catalog lists, keeps the literal Observation it was recorded with, and every other
    /// measurement appears once, the first catalog winning.
    static var reverseProjections: [ContentCorpusVector] {
        var seen: Set<String> = []
        var observations = (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).compactMap { contract in
            seen.insert(contract.id).inserted ? (contract.id, minimalObservation(contract)) : nil
        }
        observations.append((bodyMassIndexID, observation(code: ("http://loinc.org", "39156-5"), quantity: quantity("kg/m2", unit: "kg/m2", value: 1))))
        let projected = observations.map { id, resource in
            ContentCorpusVector(id: "reverse/\(id)", input: .reverse(observation: json(resource)))
        }
        let edges = reverseEdges.map { label, resource in
            ContentCorpusVector(id: "reverse/edge/\(label)", input: .reverse(observation: json(resource)))
        }
        return projected + edges + reversePrecedence.map { label, resource in
            ContentCorpusVector(id: "reverse/precedence/\(label)", input: .reverse(observation: json(resource)))
        }
    }

    /// Heart-rate Observations that each change one thing the reverse projection reads: among them an ECG's lineage,
    /// as the ECG's average heart rate states it, and Periods of zero width, without an end and reversed.
    static var reverseEdges: [(String, [String: Any])] {
        let heartRate = minimalObservation(MeasurementCatalog.heartRate, value: 72)
        func changed(_ change: (inout [String: Any]) -> Void) -> [String: Any] {
            var resource = heartRate
            change(&resource)
            return resource
        }
        let roleCoding = ["system": Canonicals.identifierRoleCodeSystem.value?.url.absoluteString ?? "", "code": "source-output"]
        let sourceOutput: [String: Any] = ["system": "https://example.org/source-output", "value": "output-1", "type": ["coding": [roleCoding]]]
        let manualEntry: [String: Any] = [
            "url": Canonicals.recordingMethod.value?.url.absoluteString ?? "",
            "valueCoding": ["system": Canonicals.recordingMethodCodeSystem.value?.url.absoluteString ?? "", "code": "manual-entry"]
        ]
        let writerVersion: [String: Any] = ["url": Canonicals.writerRecordVersion.value?.url.absoluteString ?? "", "valueString": "5"]
        let electrocardiogramLineage: [String: Any] = [
            "url": Canonicals.healthKitSourceTypeExtension.value?.url.absoluteString ?? "",
            "valueCode": HKObjectType.electrocardiogramType().identifier
        ]
        return [
            ("period", changed { resource in
                resource["effectiveDateTime"] = nil
                resource["effectivePeriod"] = ["start": "2026-08-17T15:30:00-07:00", "end": "2026-08-17T15:30:45-07:00"]
            }),
            ("no-effective", changed { $0["effectiveDateTime"] = nil }),
            ("no-value", changed { $0["valueQuantity"] = nil }),
            ("unit-code-mismatch", changed { $0["valueQuantity"] = quantity("/s", unit: "beats/second", value: 1.2) }),
            ("unit-system-mismatch", changed { $0["valueQuantity"] = quantity("/min", unit: "beats/minute", value: 72, system: "https://example.org/units") }),
            ("unknown-code", changed { $0["code"] = ["coding": [["system": "http://loinc.org", "code": "0000-0"]]] }),
            ("decimal-value", changed { $0["valueQuantity"] = quantity("/min", unit: "beats/minute", value: 72.5) }),
            ("utc", changed { $0["effectiveDateTime"] = "2026-08-17T22:30:00Z" }),
            ("fraction", changed { $0["effectiveDateTime"] = "2026-08-17T22:30:00.250Z" }),
            ("date-only", changed { $0["effectiveDateTime"] = "2026-08-17" }),
            ("pre-reform", changed { $0["effectiveDateTime"] = "1500-01-01T00:00:00Z" }),
            ("manual-entry", changed { $0["extension"] = [manualEntry] }),
            ("sync-identity", changed { resource in
                resource["identifier"] = [sourceOutput]
                resource["extension"] = [writerVersion]
            }),
            ("amended-sync-identity", changed { resource in
                resource["identifier"] = [sourceOutput]
                resource["status"] = "amended"
            }),
            ("blood-pressure-missing-diastolic", bloodPressure(diastolic: false)),
            ("blood-pressure-unit-mismatch", bloodPressure(diastolic: true, unit: "kPa")),
            ("electrocardiogram-lineage", changed { $0["extension"] = [electrocardiogramLineage] }),
            ("period-zero-width", changed { resource in
                resource["effectiveDateTime"] = nil
                resource["effectivePeriod"] = ["start": "2026-08-17T15:30:00-07:00", "end": "2026-08-17T15:30:00-07:00"]
            }),
            ("period-without-end", changed { resource in
                resource["effectiveDateTime"] = nil
                resource["effectivePeriod"] = ["start": "2026-08-17T15:30:00-07:00"]
            }),
            ("period-reversed", changed { resource in
                resource["effectiveDateTime"] = nil
                resource["effectivePeriod"] = ["start": "2026-08-17T15:30:45-07:00", "end": "2026-08-17T15:30:00-07:00"]
            })
        ]
    }

    /// Observations with two faults at once, one for every pair of adjacent checks of the reverse projection (the
    /// measurement's one quantity type, the effective time, the value, the value's number and unit, then each
    /// blood-pressure member in order): which one is reported pins their order. Speed, which several quantity types
    /// read, has no quantity type to land on. `value-before-quantity-type` keeps the id it was recorded under before
    /// spec F5 moved the quantity type first, as ids are stable; it now pins the quantity type before the value.
    static var reversePrecedence: [(String, [String: Any])] {
        let heartRate = minimalObservation(MeasurementCatalog.heartRate, value: 72)
        let speed = minimalObservation(MeasurementCatalog.speed)
        func changed(_ resource: [String: Any], _ change: (inout [String: Any]) -> Void) -> [String: Any] {
            var resource = resource
            change(&resource)
            return resource
        }
        return [
            ("effective-before-value", changed(heartRate) { resource in
                resource["effectiveDateTime"] = nil
                resource["valueQuantity"] = nil
            }),
            ("value-before-quantity-type", changed(speed) { $0["valueQuantity"] = nil }),
            ("quantity-type-before-unit", changed(speed) { $0["valueQuantity"] = quantity("/min", unit: "beats/minute", value: 72) }),
            ("number-before-unit", changed(heartRate) { $0["valueQuantity"] = ["system": "http://unitsofmeasure.org", "code": "/s", "unit": "beats/second"] }),
            ("systolic-before-diastolic", changed(bloodPressure(diastolic: true)) { $0["component"] = nil }),
            ("quantity-type-before-effective", changed(speed) { $0["effectiveDateTime"] = nil })
        ]
    }

    /// The smallest Observation of `contract` the reverse projection reads: its code, a zoned instant (a minute's
    /// Period for a Period measurement, as Grove emits it), and a value inside its domain in its unit (or a unitless
    /// one when it has none), or the components of a panel.
    static func minimalObservation(_ contract: MeasurementContract, value: Double? = nil) -> [String: Any] {
        guard contract.id != MeasurementCatalog.bloodPressure.id else {
            return bloodPressure(diastolic: true)
        }
        let unit = contract.quantity ?? QuantityContract(system: "http://unitsofmeasure.org", code: "1", unit: "1")
        let reading = value ?? unit.valueDomain.map(insideValue) ?? 1
        var resource = observation(code: (contract.code.system, contract.code.code), quantity: quantity(unit.code, unit: unit.unit, value: reading, system: unit.system))
        if contract.effective == .period {
            resource["effectiveDateTime"] = nil
            resource["effectivePeriod"] = ["start": "2026-08-17T15:30:00-07:00", "end": "2026-08-17T15:31:00-07:00"]
        }
        return resource
    }

    /// The middle of a bounded domain, or one past its lower bound, whole when the domain admits only integers.
    static func insideValue(_ domain: QuantityValueDomain) -> Double {
        var value = domain.maximum.map { (domain.minimum.value + $0.value) / 2 } ?? domain.minimum.value + 1
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, domain.integerOnly ? 0 : 3, .plain)
        return NSDecimalNumber(decimal: rounded).doubleValue
    }

    /// A final Observation of `code` at the base instant in Los Angeles, stating `quantity`.
    static func observation(code: (system: String, code: String), quantity: [String: Any]) -> [String: Any] {
        [
            "resourceType": "Observation",
            "status": "final",
            "code": ["coding": [["system": code.system, "code": code.code]]],
            "effectiveDateTime": "2026-08-17T15:30:00-07:00",
            "valueQuantity": quantity
        ]
    }

    /// A `valueQuantity` of `value` in UCUM `code`, displayed as `unit`.
    static func quantity(_ code: String, unit: String, value: Double, system: String = "http://unitsofmeasure.org") -> [String: Any] {
        ["system": system, "code": code, "unit": unit, "value": value]
    }

    /// A blood-pressure panel of 120/80, or of the systolic reading alone, in `unit`.
    static func bloodPressure(diastolic: Bool, unit: String = "mm[Hg]") -> [String: Any] {
        let contract = MeasurementCatalog.bloodPressure
        let components = contract.components.filter { diastolic || $0.id == "systolic" }.map { component -> [String: Any] in
            [
                "code": ["coding": [["system": component.system, "code": component.code]]],
                "valueQuantity": quantity(unit, unit: unit, value: component.id == "systolic" ? 120 : 80)
            ]
        }
        var resource = observation(code: (contract.code.system, contract.code.code), quantity: [:])
        resource["valueQuantity"] = nil
        resource["component"] = components
        return resource
    }

    /// The resource as the nested JSON an input states.
    static func json(_ resource: [String: Any]) -> ContentCorpusJSON {
        guard let json = try? ContentCorpusJSON(serializing: resource) else {
            preconditionFailure("every corpus Observation is valid JSON")
        }
        return json
    }
}

#endif
