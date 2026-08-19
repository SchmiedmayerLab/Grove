//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// The code and identifier systems Grove writes.
///
/// Every system Grove emits is named here rather than inline at the call site, so the
/// vocabulary the framework produces and the vocabulary the implementation guides
/// publish cannot drift apart.
public enum GroveFHIRVocabulary {
    // MARK: Standards

    /// LOINC.
    public static let loinc: FHIRPrimitive<FHIRURI> = "http://loinc.org"
    /// SNOMED CT.
    public static let snomedCT: FHIRPrimitive<FHIRURI> = "http://snomed.info/sct"
    /// UCUM.
    public static let ucum: FHIRPrimitive<FHIRURI> = "http://unitsofmeasure.org"
    /// IEEE 11073-10101 nomenclature (MDC), as registered with FHIR.
    public static let mdc: FHIRPrimitive<FHIRURI> = "urn:iso:std:iso:11073:10101"
    /// HL7's observation category system.
    public static let observationCategory: FHIRPrimitive<FHIRURI> = "http://terminology.hl7.org/CodeSystem/observation-category"

    // MARK: Grove

    /// The base URL of the Grove core implementation guide's code systems.
    public static let coreCodeSystemBase = "https://grovealliance.org/fhir/core/CodeSystem"
    /// The base URL of the Grove core implementation guide's extensions.
    public static let coreExtensionBase = "https://grovealliance.org/fhir/core/StructureDefinition"
    /// The base URL of the Grove platform-vocabulary implementation guide's code systems.
    ///
    /// Platform vocabularies (HealthKit and SensorKit sample types, their value enums,
    /// and their metadata keys) are published as Grove-owned code systems: Apple's
    /// documentation URLs are documentation, not terminology.
    public static let platformCodeSystemBase = "https://grovealliance.org/fhir/platforms/CodeSystem"
    /// The base URL of Grove's identifier systems.
    public static let identifierSystemBase = "https://grovealliance.org/fhir/sid"

    /// The code system of HealthKit sample-type identifiers (`HKQuantityTypeIdentifierStepCount`, …).
    public static let healthKitSampleType: FHIRPrimitive<FHIRURI> = FHIRPrimitive(FHIRURI(stringLiteral: "\(platformCodeSystemBase)/healthkit-sample-type"))
    /// The code system of HealthKit workout activity types.
    public static let healthKitWorkoutActivityType: FHIRPrimitive<FHIRURI> = FHIRPrimitive(FHIRURI(stringLiteral: "\(platformCodeSystemBase)/healthkit-workout-activity-type"))
    /// The code system of HealthKit electrocardiogram properties.
    public static let healthKitECGProperty: FHIRPrimitive<FHIRURI> = FHIRPrimitive(FHIRURI(stringLiteral: "\(platformCodeSystemBase)/healthkit-electrocardiogram-property"))
    /// The code system of HealthKit state-of-mind properties.
    public static let healthKitStateOfMindProperty: FHIRPrimitive<FHIRURI> = FHIRPrimitive(FHIRURI(stringLiteral: "\(platformCodeSystemBase)/healthkit-state-of-mind-property"))
    /// The code system of HealthKit metadata keys.
    ///
    /// A fragment system: HealthKit accepts arbitrary third-party keys, so codes the
    /// guide does not list are still valid codes here.
    public static let healthKitMetadataKey: FHIRPrimitive<FHIRURI> = FHIRPrimitive(FHIRURI(stringLiteral: "\(platformCodeSystemBase)/healthkit-metadata-key"))
    /// The code system of SensorKit sensor streams.
    public static let sensorKitSampleType: FHIRPrimitive<FHIRURI> = FHIRPrimitive(FHIRURI(stringLiteral: "\(platformCodeSystemBase)/sensorkit-sample-type"))
}
