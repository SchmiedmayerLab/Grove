//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


// Individual names intentionally mirror the machine-readable IG identifiers.
// swiftlint:disable missing_docs
/// Non-profile canonical URLs shared by Grove's R4 producer implementations.
///
/// Profile URLs and the measurement matrix are generated in ``GroveFHIRProfile`` and
/// ``GroveFHIRMeasurementCatalog``. This type centralizes extensions, terminology, and
/// adapter identity systems that are also normative but are not listed as profiles in
/// the package graph catalog.
public enum GroveFHIRCanonical {
    public static let root = GroveFHIRContractVersion.canonicalRoot

    // MARK: Mobile

    public static let recordingMethod = uri("/mobile/StructureDefinition/grove-recording-method")
    public static let recordingMethodCodeSystem = uri("/mobile/CodeSystem/grove-recording-method")
    public static let sleepStageCodeSystem = uri("/mobile/CodeSystem/grove-sleep-stage")

    // MARK: HealthKit

    public static let healthKitObjectIdentifierSystem = "\(root)/healthkit/NamingSystem/healthkit-object-id"
    public static let appleBundleIdentifierSystem = "\(root)/healthkit/NamingSystem/apple-bundle-id"
    public static let healthKitSourceDeviceIdentifierSystem = "\(root)/healthkit/NamingSystem/healthkit-source-device-id"
    public static let healthKitObjectIdentifier: FHIRPrimitive<FHIRURI> =
        FHIRPrimitive(FHIRURI(stringLiteral: healthKitObjectIdentifierSystem))
    public static let appleBundleIdentifier: FHIRPrimitive<FHIRURI> =
        FHIRPrimitive(FHIRURI(stringLiteral: appleBundleIdentifierSystem))
    public static let healthKitMetadataKey = uri("/healthkit/CodeSystem/healthkit-metadata-key")
    public static let healthKitSourceType = GroveFHIRHealthKitCatalog.sourceTypeCodeSystem
    public static let healthKitHeartRateMotionContext = uri("/healthkit/CodeSystem/healthkit-heart-rate-motion-context")
    public static let healthKitSleepAnalysis = uri("/healthkit/CodeSystem/healthkit-sleep-analysis")
    public static let healthKitECGClassificationExtension = uri("/healthkit/StructureDefinition/healthkit-ecg-classification")
    public static let healthKitECGSymptomsStatusExtension = uri("/healthkit/StructureDefinition/healthkit-ecg-symptoms-status")
    public static let healthKitECGAverageHeartRateExtension = uri("/healthkit/StructureDefinition/healthkit-ecg-average-heart-rate")
    public static let healthKitECGSamplingFrequencyExtension = uri("/healthkit/StructureDefinition/healthkit-ecg-sampling-frequency")
    public static let healthKitECGCountExtension = uri("/healthkit/StructureDefinition/healthkit-ecg-voltage-measurement-count")
    public static let healthKitECGAlgorithmVersionExtension = uri("/healthkit/StructureDefinition/healthkit-ecg-algorithm-version")
    public static let healthKitECGSourcePeriodExtension = uri("/healthkit/StructureDefinition/healthkit-ecg-source-period")

    // MARK: Standard R4 extensions and terminology

    public static let gatewayDevice: FHIRPrimitive<FHIRURI> =
        "http://hl7.org/fhir/StructureDefinition/observation-gatewayDevice"
    public static let researchStudy: FHIRPrimitive<FHIRURI> =
        "http://hl7.org/fhir/StructureDefinition/workflow-researchStudy"
    public static let timezone: FHIRPrimitive<FHIRURI> =
        "http://hl7.org/fhir/StructureDefinition/timezone"
    public static let versionAlgorithm: FHIRPrimitive<FHIRURI> =
        "http://hl7.org/fhir/StructureDefinition/artifact-versionAlgorithm"
    public static let versionAlgorithmCodeSystem: FHIRPrimitive<FHIRURI> =
        "http://hl7.org/fhir/version-algorithm"

    private static func canonical(_ suffix: String) -> FHIRPrimitive<Canonical> {
        FHIRPrimitive(Canonical(stringLiteral: "\(root)\(suffix)"))
    }

    private static func uri(_ suffix: String) -> FHIRPrimitive<FHIRURI> {
        FHIRPrimitive(FHIRURI(stringLiteral: "\(root)\(suffix)"))
    }
}
// swiftlint:enable missing_docs
