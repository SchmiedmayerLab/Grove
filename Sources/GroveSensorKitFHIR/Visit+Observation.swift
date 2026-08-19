//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SensorKit)

import FHIRModelsExtensions
import Foundation
public import GroveSensorKit
public import ModelsR4
import SensorKit


@available(iOS 18, *)
extension SRVisit.SafeRepresentation: SensorKitObservationConvertible {
    public static let profile: FHIRPrimitive<Canonical> =
        "https://grovealliance.org/fhir/core/StructureDefinition/grove-visit-observation"
    public static let category = GroveSensorKitVocabulary.category("social-history", "Social History")

    public func hashIdentifierContent(into hasher: inout SensorKitSampleIDHasher) {
        hasher.combine(Sensor.visits.srSensor.rawValue)
        hasher.combine(locationCategory.rawValue)
        hasher.combine(distanceFromHome)
        hasher.combine(arrivalDateInterval.start)
        hasher.combine(arrivalDateInterval.end)
        hasher.combine(departureDateInterval.start)
        hasher.combine(departureDateInterval.end)
    }

    public func buildObservation(_ observation: inout Observation) throws {
        observation.code = CodeableConcept(coding: [
            sampleTypeCoding(Sensor.visits.srSensor.rawValue, "Visits")
        ])
        // SensorKit reports arrival and departure as windows, so the observation spans
        // the widest possible visit and the windows themselves are coded components.
        observation.effective = .period(Period(
            end: FHIRPrimitive(try DateTime(date: departureDateInterval.end)),
            start: FHIRPrimitive(try DateTime(date: arrivalDateInterval.start))
        ))
        let category = try locationCategory.groveCode
        observation.component = [
            ObservationComponent(
                code: GroveSensorKitVocabulary.concept("visit-location-category", "Visit Location Category"),
                value: .codeableConcept(GroveSensorKitVocabulary.value(category.code, category.display))
            ),
            ObservationComponent(
                code: GroveSensorKitVocabulary.concept("distance-from-home", "Distance From Home"),
                value: .quantity(Quantity(
                    code: "m".asFHIRStringPrimitive(),
                    system: GroveSensorKitVocabulary.ucum,
                    unit: "m".asFHIRStringPrimitive(),
                    value: try distanceFromHome.asFHIRDecimalPrimitiveSafe()
                ))
            ),
            ObservationComponent(
                code: GroveSensorKitVocabulary.concept("arrival-window", "Arrival Window"),
                value: .period(Period(
                    end: FHIRPrimitive(try DateTime(date: arrivalDateInterval.end)),
                    start: FHIRPrimitive(try DateTime(date: arrivalDateInterval.start))
                ))
            ),
            ObservationComponent(
                code: GroveSensorKitVocabulary.concept("departure-window", "Departure Window"),
                value: .period(Period(
                    end: FHIRPrimitive(try DateTime(date: departureDateInterval.end)),
                    start: FHIRPrimitive(try DateTime(date: departureDateInterval.start))
                ))
            )
        ]
    }
}

#endif
