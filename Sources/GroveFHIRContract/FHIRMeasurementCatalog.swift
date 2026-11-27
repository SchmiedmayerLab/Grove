//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// One row of the HealthKit guide's source inventory, independent of SDK presence and converter implementation.
public struct HealthKitSourceDefinition: Sendable {
    /// The exact SDK source-type identifier in the guide.
    public let sourceTypeIdentifier: String
    /// Every declared measurement identifier; some have no descriptor in the generated measurement catalogs.
    public let measurementIDs: [String]
    /// The row's direct profile claims or alternatives, not a claim that all apply at once.
    public let profiles: [FHIRPrimitive<Canonical>]
    /// The row's admission in the guide. `supported` doesn't promise that the exporter accepts the input.
    public let guideStatus: HealthKitImplementationStatus

    package init(_ row: HealthKitContractRow) {
        sourceTypeIdentifier = row.sourceTypeIdentifier
        measurementIDs = row.measurementIDs
        profiles = row.profiles
        guideStatus = row.implementationStatus
    }
}


/// The measurement and HealthKit inventory facts of the pinned guide, available without an Apple SDK.
///
/// A guide declaration is neither producer availability nor permission to collect or receive a resource. Applications
/// select their own implemented capabilities and validate complete resources against the guide. This view doesn't
/// replace the adapter's conversion plans or interpret every possible FHIR value datatype.
public enum FHIRMeasurementCatalog {
    /// The code of the HealthKit adapter's optional heart-rate motion context component, which is outside the shared
    /// measurement catalog. Its values use `Canonicals.healthKitHeartRateMotionContext`.
    public static let healthKitHeartRateMotionContextCode = FHIRMeasurementDefinition.Code(
        CodingContract(
            system: Canonicals.healthKitMetadataKeyValue,
            code: "HKMetadataKeyHeartRateMotionContext"
        )
    )

    /// Every measurement of the generated Mobile, HealthKit and connected-provider contracts, including the standard BMI
    /// claim. The guide's Health Connect measurements are not part of it, as no Grove adapter converts them.
    public static let measurements: [FHIRMeasurementDefinition] = (
        MeasurementCatalog.all + HealthKitMeasurementCatalog.all + [HealthKitContract.bodyMassIndex]
            + GoogleHealthMeasurementCatalog.all + OuraMeasurementCatalog.all + WithingsMeasurementCatalog.all
    ).map(FHIRMeasurementDefinition.init)

    /// Every HealthKit source row, including guide-admitted inputs the current producer cannot convert.
    public static let healthKitSources: [HealthKitSourceDefinition] = HealthKitContract.rows.map(HealthKitSourceDefinition.init)

    private static let measurementsByID = Dictionary(uniqueKeysWithValues: measurements.map { ($0.id, $0) })
    private static let sourcesByID = Dictionary(uniqueKeysWithValues: healthKitSources.map { ($0.sourceTypeIdentifier, $0) })

    /// The measurement with exactly this identifier, or `nil` for an unknown identifier.
    public static func measurement(id: String) -> FHIRMeasurementDefinition? {
        measurementsByID[id]
    }

    /// The HealthKit inventory row with exactly this source-type identifier, or `nil` for an unknown identifier.
    ///
    /// Apple callers can pass a `HealthKitSourceType`'s `rawValue`. No prefix matching or inference is performed.
    public static func healthKitSource(identifier: String) -> HealthKitSourceDefinition? {
        sourcesByID[identifier]
    }
}
