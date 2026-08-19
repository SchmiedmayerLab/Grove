//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SensorKit)

public import ModelsR4


/// The code and identifier systems the SensorKit mapping writes.
///
/// Sensor streams are coded by their SensorKit identifiers, published as a Grove code
/// system; the concept and value systems cover what SensorKit reports and no
/// established vocabulary names (wearable placement, visit windows, usage counters).
public enum GroveSensorKitVocabulary {
    /// SensorKit sensor streams, coded by `SRSensor` raw values.
    public static let sampleType: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/platforms/CodeSystem/sensorkit-sample-type"
    /// Observation and component codes for SensorKit-specific concepts.
    public static let concepts: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/core/CodeSystem/grove-sensorkit-concepts"
    /// Coded values for those concepts.
    public static let values: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/core/CodeSystem/grove-sensorkit-values"
    /// The identifier system of SensorKit-derived records.
    ///
    /// SensorKit assigns no record identity, so Grove derives a deterministic one from
    /// the sample's own content — re-fetching the same window cannot create duplicates.
    public static let sampleId: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/sid/sensorkit-sample-id"

    static let observationCategory: FHIRPrimitive<FHIRURI> = "http://terminology.hl7.org/CodeSystem/observation-category"
    static let ucum: FHIRPrimitive<FHIRURI> = "http://unitsofmeasure.org"

    static func concept(_ code: String, _ display: String) -> CodeableConcept {
        CodeableConcept(coding: [
            Coding(
            code: code.asFHIRStringPrimitive(),
            display: display.asFHIRStringPrimitive(),
            system: concepts
        )
        ])
    }

    static func value(_ code: String, _ display: String) -> CodeableConcept {
        CodeableConcept(coding: [
            Coding(
            code: code.asFHIRStringPrimitive(),
            display: display.asFHIRStringPrimitive(),
            system: values
        )
        ])
    }

    static func category(_ code: String, _ display: String) -> CodeableConcept {
        CodeableConcept(coding: [
            Coding(
            code: code.asFHIRStringPrimitive(),
            display: display.asFHIRStringPrimitive(),
            system: observationCategory
        )
        ])
    }
}

#endif
