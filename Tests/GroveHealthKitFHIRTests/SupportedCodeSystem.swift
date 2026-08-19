//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// The code systems Grove's HealthKit mapping is allowed to write.
enum SupportedCodeSystem: String {
    case loinc = "http://loinc.org"
    case snomed = "http://snomed.info/sct"
    case ucum = "http://unitsofmeasure.org"
    case mdc = "urn:iso:std:iso:11073:10101"
    case observationCategory = "http://terminology.hl7.org/CodeSystem/observation-category"
    /// HealthKit sample-type identifiers, published by the Grove platform vocabulary.
    case apple = "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-sample-type"
    /// HealthKit metadata keys, published by the Grove platform vocabulary.
    case healthKitMetadataKey = "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-metadata-key"
}
