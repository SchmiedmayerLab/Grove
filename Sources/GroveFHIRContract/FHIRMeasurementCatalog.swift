//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// One HealthKit guide inventory row, independent of SDK presence and converter implementation.
public struct HealthKitSourceDefinition: Sendable {
    /// The exact SDK source-type identifier in the guide.
    public let sourceTypeIdentifier: String
    /// The guide's title, not an application-localized consent label.
    public let title: String
    /// All declared measurement identifiers; some have no descriptor in the generated measurement catalogs.
    public let measurementIDs: [String]
    /// The row's complete direct profile claims or alternatives, not a claim that all apply simultaneously.
    public let profiles: [FHIRPrimitive<Canonical>]
    /// Admission in the guide. In particular, `supported` does not promise that the exporter accepts the input.
    public let guideStatus: HealthKitImplementationStatus
    /// Additional source-specific requirements or refusal explanation from the guide.
    public let requirement: String?

    package init(_ row: HealthKitContractRow) {
        sourceTypeIdentifier = row.sourceTypeIdentifier
        title = row.title
        measurementIDs = row.measurementIDs
        profiles = row.profiles
        guideStatus = row.implementationStatus
        requirement = row.requirement
    }
}


/// Read-only measurement and HealthKit inventory facts from the pinned guide, available without an Apple SDK.
///
/// A guide declaration is neither producer availability nor permission to collect or receive a resource.
/// Applications select their own implemented capabilities and validate complete resources against the guide.
/// This view does not replace the adapter's conversion plans or interpret every possible FHIR value datatype.
public enum FHIRMeasurementCatalog {
    /// The HealthKit adapter's optional heart-rate component, whose code is outside the shared measurement catalog.
    /// Its coding system is `Canonicals.healthKitMetadataKey`; its values use `Canonicals.healthKitHeartRateMotionContext`.
    public static let healthKitHeartRateMotionContextCode = "HKMetadataKeyHeartRateMotionContext"

    /// Every measurement in the generated Mobile, HealthKit and provider contracts, including the standard BMI claim.
    /// Duplicate identifiers follow the producer compiler's precedence: the first catalog wins.
    public static let measurements: [FHIRMeasurementDefinition] = {
        var seen: Set<String> = []
        return generatedMeasurements.filter { seen.insert($0.id).inserted }.map(FHIRMeasurementDefinition.init)
    }()

    /// Every HealthKit source row, including guide-admitted inputs the current producer cannot convert.
    public static let healthKitSources: [HealthKitSourceDefinition] = HealthKitContract.rows.map(HealthKitSourceDefinition.init)

    /// Provider-owned semantics remain separately selectable from native platform measurements.
    public static let providerMeasurements = generatedProviderMeasurements.map(FHIRMeasurementDefinition.init)

    private static let generatedProviderMeasurements =
        GoogleHealthMeasurementCatalog.all + OuraMeasurementCatalog.all + WithingsMeasurementCatalog.all
    private static let generatedMeasurements =
        MeasurementCatalog.all + HealthKitMeasurementCatalog.all + [HealthKitContract.bodyMassIndex] + generatedProviderMeasurements
    private static let byID = Dictionary(uniqueKeysWithValues: measurements.map { ($0.id, $0) })
    private static let sourcesByID = Dictionary(uniqueKeysWithValues: healthKitSources.map { ($0.sourceTypeIdentifier, $0) })

    /// The declared measurement with this exact identifier, or `nil` for an unknown identifier.
    public static func measurement(id: String) -> FHIRMeasurementDefinition? {
        byID[id]
    }

    /// Every measurement directly declaring this profile, without choosing one when a profile is shared.
    /// Adapter-wide and inherited profile claims do not select a measurement through this lookup.
    public static func measurements(profile: FHIRPrimitive<Canonical>) -> [FHIRMeasurementDefinition] {
        measurements.filter { $0.profile == profile }
    }

    /// The exact HealthKit inventory row. Apple callers can pass their typed source identifier's `rawValue`.
    /// Unknown identifiers return `nil`; no prefix matching or inferred source type is performed.
    public static func healthKitSource(identifier: String) -> HealthKitSourceDefinition? {
        sourcesByID[identifier]
    }
}
