//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract
import HealthKit


/// What the adapter does with one source field.
public enum FieldDisposition: String, Hashable, Sendable {
    /// Carried into the graph.
    case carried
    /// Read only as an identity preimage component; never emitted.
    case identityOnly
    /// Carried only when a disclosure policy authorizes it.
    case governed
    /// Read and never emitted.
    case withheld
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitCatalog {
    /// The disposition of every source field, per source type, keyed by the HealthKit property name.
    ///
    /// Hand-written until the adapter catalog carries it; the shape follows the Health Connect table.
    public static let fieldDispositions: [HealthKitSourceType: [String: FieldDisposition]] = Dictionary(
        uniqueKeysWithValues: HealthKitSourceType.allCases.map { type in
            (type, dispositions(for: type))
        }
    )

    private static func dispositions(for type: HealthKitSourceType) -> [String: FieldDisposition] {
        let identifier = type.rawValue
        if identifier.hasPrefix("HKCharacteristicTypeIdentifier") {
            return ["value": .withheld]
        }
        var fields: [String: FieldDisposition] = [
            "uuid": .identityOnly,
            "startDate": .carried,
            "endDate": .carried,
            "device": .carried,
            "sourceRevision": .carried,
            "metadata": .governed
        ]
        switch type {
        case .electrocardiogram:
            fields.merge([
                "classification": .carried, "symptomsStatus": .carried, "averageHeartRate": .carried,
                "samplingFrequency": .carried, "numberOfVoltageMeasurements": .carried, "voltageMeasurements": .carried
            ]) { _, new in new }
        case .heartbeatSeries:
            fields["heartbeats"] = .carried
        case .workoutRoute:
            fields["locations"] = .governed
        case .workout:
            fields.merge([
                "workoutActivityType": .carried, "duration": .carried, "statistics": .carried,
                "workoutEvents": .carried, "workoutActivities": .carried
            ]) { _, new in new }
        case .bloodPressure:
            fields["objects"] = .carried
        case .stateOfMind:
            fields.merge(["kind": .carried, "valence": .carried, "labels": .carried, "associations": .carried]) { _, new in new }
        case .cda:
            fields["document"] = .carried
        default:
            fields.merge(prefixDispositions(for: identifier)) { _, new in new }
        }
        return fields
    }

    private static func prefixDispositions(for identifier: String) -> [String: FieldDisposition] {
        if identifier.hasPrefix("HKQuantityTypeIdentifier") {
            ["quantity": .carried, "count": .withheld]
        } else if identifier.hasPrefix("HKCategoryTypeIdentifier") {
            ["value": .carried]
        } else if identifier.hasPrefix("HKClinicalTypeIdentifier") {
            ["fhirResource": .carried, "displayName": .withheld]
        } else if identifier.hasPrefix("HKScoredAssessmentTypeIdentifier") {
            ["score": .carried, "answers": .withheld]
        } else {
            [:]
        }
    }
}

#endif
