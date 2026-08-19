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
extension SensorKitOnWristEventSample: SensorKitObservationConvertible {
    public static let profile: FHIRPrimitive<Canonical> =
        "https://grovealliance.org/fhir/core/StructureDefinition/grove-wear-state-observation"
    public static let category = GroveSensorKitVocabulary.category("activity", "Activity")

    /// The start of the state this sample asserts.
    ///
    /// SensorKit reports the two states' start dates side by side rather than as a
    /// bracket: whichever state is current carries the date it began, while the other
    /// still carries the date the *previous* state began. The interval over which the
    /// asserted value holds therefore runs from the current state's start to the
    /// sample's own timestamp — taking both dates as a bracket spans the opposite state.
    private var stateStart: Date? {
        onWrist ? onWristDate : offWristDate
    }

    public func hashIdentifierContent(into hasher: inout SensorKitSampleIDHasher) {
        hasher.combine(Sensor.onWrist.srSensor.rawValue)
        hasher.combine(timestamp)
        hasher.combine(onWrist ? 1 : 0)
        hasher.combine(wristLocation.rawValue)
        hasher.combine(crownOrientation.rawValue)
        hasher.combine(stateStart)
    }

    public func buildObservation(_ observation: inout Observation) throws {
        observation.code = CodeableConcept(coding: [
            sampleTypeCoding(Sensor.onWrist.srSensor.rawValue, "On-Wrist State")
        ])
        // The state is the value; the placement rides as coded components.
        observation.value = .codeableConcept(onWrist
            ? GroveSensorKitVocabulary.value("on-wrist", "On Wrist")
            : GroveSensorKitVocabulary.value("off-wrist", "Off Wrist"))
        if let stateStart, stateStart < timestamp {
            observation.effective = .period(Period(
                end: FHIRPrimitive(try DateTime(date: timestamp)),
                start: FHIRPrimitive(try DateTime(date: stateStart))
            ))
        } else {
            observation.effective = .dateTime(FHIRPrimitive(try DateTime(date: timestamp)))
        }
        let wrist = try wristLocation.groveCode
        let crown = try crownOrientation.groveCode
        observation.component = [
            ObservationComponent(
                code: GroveSensorKitVocabulary.concept("wrist-location", "Wrist Location"),
                value: .codeableConcept(GroveSensorKitVocabulary.value(wrist.code, wrist.display))
            ),
            ObservationComponent(
                code: GroveSensorKitVocabulary.concept("crown-orientation", "Crown Orientation"),
                value: .codeableConcept(GroveSensorKitVocabulary.value(crown.code, crown.display))
            )
        ]
    }
}

#endif
