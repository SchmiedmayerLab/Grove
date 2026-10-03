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


/// Clinical documents, retractions, the catalog projections and reverse projections.
extension ContentCorpusGrid {
    /// CDA documents and clinical records: every type and admitted release, refused releases and payloads,
    /// missing payloads, bytes kept as delivered, and every link. watchOS has neither.
    static var clinicalDocuments: [ContentCorpusVector] {
        #if os(watchOS)
        []
        #else
        cdaDocuments + clinicalRecords
        #endif
    }

    /// The deletion of a record of every inventory row.
    static var retractions: [ContentCorpusVector] {
        HealthKitContract.rows.map { row in
            ContentCorpusVector(id: "retraction/\(row.sourceTypeIdentifier)", input: .retract(type: row.sourceTypeIdentifier))
        }
    }

    /// Every inventory row with its outputs and field dispositions, the unit bindings, and both unit lookups for
    /// every spelling the bindings use plus spellings they do not.
    static var catalog: [ContentCorpusVector] {
        let entries = HealthKitContract.rows.map { row in
            ContentCorpusVector(id: "catalog/entry/\(row.sourceTypeIdentifier)", input: .catalog(projection: .entry(type: row.sourceTypeIdentifier)))
        }
        let spellings = Set(HealthKitCatalog.unitBindings.flatMap { [$0.ucumCode, $0.displayUnit] })
            .union(["", "%", "/h", "Cel", "kg", "kg/m2", "mmHg", "mm[Hg]", "beats/minute", "not-a-unit"])
            .sorted()
        return entries + [
            ContentCorpusVector(id: "catalog/unit-bindings", input: .catalog(projection: .unitBindings)),
            ContentCorpusVector(id: "catalog/unit-spellings", input: .catalog(projection: .unitSpellings(spellings: spellings)))
        ]
    }

    /// A minimal Observation of every generated measurement and of body-mass index, and the edges of the
    /// reverse projection: Period and missing effective times, missing and mismatched values, manual entry,
    /// zones, a pre-1582 date, sync identity and amendment, and blood-pressure components.
    static var reverseProjections: [ContentCorpusVector] {
        var observations = (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).map { contract in
            (contract.id, minimalObservation(contract))
        }
        observations.append(("body-mass-index", observation(code: ("http://loinc.org", "39156-5"), quantity: quantity("kg/m2", unit: "kg/m2", value: 1))))
        let projected = observations.map { id, resource in
            ContentCorpusVector(id: "reverse/\(id)", input: .catalog(projection: .reverse(observation: json(resource))))
        }
        return projected + reverseEdges.map { label, resource in
            ContentCorpusVector(id: "reverse/edge/\(label)", input: .catalog(projection: .reverse(observation: json(resource))))
        }
    }

    /// Heart-rate Observations that each change one thing the reverse projection reads.
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
            ("blood-pressure-unit-mismatch", bloodPressure(diastolic: true, unit: "kPa"))
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

    static func observation(code: (system: String, code: String), quantity: [String: Any]) -> [String: Any] {
        [
            "resourceType": "Observation",
            "status": "final",
            "code": ["coding": [["system": code.system, "code": code.code]]],
            "effectiveDateTime": "2026-08-17T15:30:00-07:00",
            "valueQuantity": quantity
        ]
    }

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

    /// The resource as compact JSON with sorted members.
    static func json(_ resource: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: resource, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            preconditionFailure("every corpus Observation is valid JSON")
        }
        return String(decoding: data, as: UTF8.self)
    }
}

#endif
