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
/// Profile URLs and the measurement matrix are generated in ``Profile`` and
/// ``MeasurementCatalog``. This type centralizes extensions, terminology, and
/// adapter identity systems that are also normative but are not listed as profiles in
/// the package graph catalog.
public enum Canonicals {
    public static let root = ContractVersion.canonicalRoot

    // MARK: Mobile

    public static let recordingMethod = uri("/mobile/StructureDefinition/grove-recording-method")
    public static let recordingMethodCodeSystem = uri("/mobile/CodeSystem/grove-recording-method")
    public static let sleepStageCodeSystem = uri("/mobile/CodeSystem/grove-sleep-stage")
    public static let workoutActivityCodeSystem = uri("/mobile/CodeSystem/grove-workout-activity")
    public static let workoutSegmentTypeCodeSystem = uri("/mobile/CodeSystem/grove-workout-segment-type")
    public static let workoutStatisticCodeSystem = uri("/mobile/CodeSystem/grove-workout-statistic")
    public static let mobileMeasurementCodeSystem = uri("/mobile/CodeSystem/grove-mobile-measurement")
    public static let aggregationMethodCodeSystem = uri("/mobile/CodeSystem/grove-aggregation-method")
    public static let groveApplicationVersionType = uri("/mobile/CodeSystem/grove-application-version-type")
    public static let healthKitRetainedMetadata = uri("/healthkit/StructureDefinition/healthkit-retained-metadata")

    // MARK: HealthKit

    public static let healthKitObjectIdentifierSystem = "\(root)/healthkit/NamingSystem/healthkit-object-id"
    public static let appleBundleIdentifierSystem = "\(root)/healthkit/NamingSystem/apple-bundle-id"
    public static let healthKitSourceDeviceIdentifierSystem = "\(root)/healthkit/NamingSystem/healthkit-source-device-id"
    public static let healthKitObjectIdentifier: FHIRPrimitive<FHIRURI> =
        FHIRPrimitive(FHIRURI(stringLiteral: healthKitObjectIdentifierSystem))
    /// The logical record a writing application assigns, stable across the replacements a platform
    /// performs when the same writer saves a higher version of it.
    ///
    /// One namespace serves every adapter, so the same application writing the same record on more
    /// than one platform produces the same complete identifier.
    public static let writerRecordIdentifierSystem = "\(root)/mobile/NamingSystem/grove-writer-record-id"
    public static let writerRecordVersion = uri("/mobile/StructureDefinition/grove-writer-record-version")
    public static let appleBundleIdentifier: FHIRPrimitive<FHIRURI> =
        FHIRPrimitive(FHIRURI(stringLiteral: appleBundleIdentifierSystem))
    public static let healthKitMetadataKey = uri("/healthkit/CodeSystem/healthkit-metadata-key")
    public static let healthKitSourceType = HealthKitContract.sourceTypeCodeSystem
    public static let healthKitHeartRateMotionContext = uri("/healthkit/CodeSystem/healthkit-heart-rate-motion-context")
    public static let healthKitInsulinDeliveryReason = uri("/healthkit/CodeSystem/healthkit-insulin-delivery-reason")
    public static let healthKitSleepAnalysis = uri("/healthkit/CodeSystem/healthkit-sleep-analysis")
    public static let healthKitSymptomSeverity = uri("/healthkit/CodeSystem/healthkit-symptom-severity")
    public static let healthKitPresence = uri("/healthkit/CodeSystem/healthkit-presence")
    public static let healthKitAppetiteChanges = uri("/healthkit/CodeSystem/healthkit-appetite-changes")
    public static let healthKitAppleStandHourValue = uri("/healthkit/CodeSystem/healthkit-apple-stand-hour-value")
    public static let healthKitWorkoutActivity = uri("/healthkit/CodeSystem/healthkit-workout-activity")
    public static let healthKitMeasurementCodeSystem = uri("/healthkit/CodeSystem/healthkit-measurement")
    public static let healthKitCervicalMucusQuality = uri("/healthkit/CodeSystem/healthkit-cervical-mucus-quality")
    public static let healthKitContraceptive = uri("/healthkit/CodeSystem/healthkit-contraceptive")
    public static let healthKitOvulationTestResult = uri("/healthkit/CodeSystem/healthkit-ovulation-test-result")
    /// Shared by the pregnancy and progesterone test-result cases the guide retains in one system.
    public static let healthKitTestResult = uri("/healthkit/CodeSystem/healthkit-test-result")
    public static let healthKitVaginalBleeding = uri("/healthkit/CodeSystem/healthkit-vaginal-bleeding")
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
    public static let instantiatesCanonical: FHIRPrimitive<FHIRURI> =
        "http://hl7.org/fhir/StructureDefinition/workflow-instantiatesCanonical"
    public static let timezone: FHIRPrimitive<FHIRURI> =
        "http://hl7.org/fhir/StructureDefinition/timezone"
    public static let versionAlgorithm: FHIRPrimitive<FHIRURI> =
        "http://hl7.org/fhir/StructureDefinition/artifact-versionAlgorithm"
    public static let versionAlgorithmCodeSystem: FHIRPrimitive<FHIRURI> =
        "http://hl7.org/fhir/version-algorithm"


    private static func uri(_ suffix: String) -> FHIRPrimitive<FHIRURI> {
        FHIRPrimitive(FHIRURI(stringLiteral: "\(root)\(suffix)"))
    }
}
// swiftlint:enable missing_docs
