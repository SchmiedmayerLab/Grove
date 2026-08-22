//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRConverter {
    private static let correlatedSymptomTypeIdentifiers: Set<String> = [
        HKCategoryTypeIdentifier.rapidPoundingOrFlutteringHeartbeat.rawValue,
        HKCategoryTypeIdentifier.skippedHeartbeat.rawValue,
        HKCategoryTypeIdentifier.fatigue.rawValue,
        HKCategoryTypeIdentifier.shortnessOfBreath.rawValue,
        HKCategoryTypeIdentifier.chestTightnessOrPain.rawValue,
        HKCategoryTypeIdentifier.fainting.rawValue,
        HKCategoryTypeIdentifier.dizziness.rawValue
    ]

    static func validatedSymptoms(
        _ symptoms: [HKCategorySample],
        status: HKElectrocardiogram.SymptomsStatus
    ) throws -> [HealthKitECGSymptomEvidence] {
        try validatedSymptomEvidence(
            symptoms.map(symptomEvidence),
            status: status
        )
    }

    static func validatedSymptomEvidence(
        _ symptoms: [HealthKitECGSymptomEvidence],
        status: HKElectrocardiogram.SymptomsStatus
    ) throws -> [HealthKitECGSymptomEvidence] {
        try validateSymptomState(status, symptomCount: symptoms.count)
        guard symptoms.count <= 7 else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.tooManySymptoms(symptoms.count))
        }
        var sourceIDs: Set<UUID> = []
        for symptom in symptoms {
            try validate(symptom: symptom, sourceIDs: &sourceIDs)
        }
        return symptoms.sorted {
            let left = ($0.typeIdentifier, $0.sourceUUID.uuidString.lowercased())
            let right = ($1.typeIdentifier, $1.sourceUUID.uuidString.lowercased())
            return left < right
        }
    }

    static func symptomEvidence(_ symptom: HKCategorySample) throws -> HealthKitECGSymptomEvidence {
        let revision = symptom.sourceRevision
        let operatingSystemVersion = revision.operatingSystemVersion
        return HealthKitECGSymptomEvidence(
            sourceUUID: symptom.uuid,
            typeIdentifier: symptom.categoryType.identifier,
            severityValue: symptom.value,
            startDate: symptom.startDate,
            endDate: symptom.endDate,
            timeZone: try healthKitTimeZone(for: symptom),
            sourceName: revision.source.name,
            sourceBundleIdentifier: revision.source.bundleIdentifier,
            sourceVersion: revision.version,
            sourceProductType: revision.productType,
            sourceOperatingSystemMajorVersion: operatingSystemVersion.majorVersion,
            sourceOperatingSystemMinorVersion: operatingSystemVersion.minorVersion,
            sourceOperatingSystemPatchVersion: operatingSystemVersion.patchVersion
        )
    }

    static func validateSymptomSourceDisclosure(
        symptomCount: Int,
        policy: HealthKitFHIRSourceDisclosurePolicy
    ) throws {
        guard symptomCount == 0 || policy == .authorized else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(
                .symptomSourceDisclosureNotAuthorized
            )
        }
    }

    static func symptomExtension(_ symptom: HealthKitECGSymptomEvidence) throws -> Extension {
        Extension(
            extension: try symptomExtensionChildren(symptom),
            url: GroveFHIRHealthKitCatalog.electrocardiogramCorrelatedSymptomExtension
        )
    }

    private static func symptomExtensionChildren(
        _ symptom: HealthKitECGSymptomEvidence
    ) throws -> [Extension] {
        var children = try symptomValueExtensions(symptom)
        children.append(contentsOf: try requiredSymptomSourceExtensions(symptom))
        if let version = symptom.sourceVersion {
            children.append(try symptomSourceStringExtension(
                url: "sourceVersion",
                value: version,
                sourceUUID: symptom.sourceUUID
            ))
        }
        if let productType = symptom.sourceProductType {
            children.append(try symptomSourceStringExtension(
                url: "sourceProductType",
                value: productType,
                sourceUUID: symptom.sourceUUID
            ))
        }
        children.append(contentsOf: try symptomOperatingSystemExtensions(symptom))
        return children
    }

    private static func symptomValueExtensions(
        _ symptom: HealthKitECGSymptomEvidence
    ) throws -> [Extension] {
        [
            Extension(
                url: "sourceIdentifier",
                value: .identifier(Identifier(
                    system: GroveFHIRCanonical.healthKitObjectIdentifier,
                    value: symptom.sourceUUID.uuidString.lowercased().asFHIRStringPrimitive()
                ))
            ),
            Extension(
                url: "effectivePeriod",
                value: .period(Period(
                    end: FHIRPrimitive(try exactHealthKitDateTime(
                        symptom.endDate,
                        timeZone: symptom.timeZone
                    )),
                    start: FHIRPrimitive(try exactHealthKitDateTime(
                        symptom.startDate,
                        timeZone: symptom.timeZone
                    ))
                ))
            ),
            Extension(url: "symptomType", value: .code(symptom.typeIdentifier.asFHIRStringPrimitive())),
            Extension(
                url: "severity",
                value: .code(try symptomSeverityCode(
                    symptom.severityValue,
                    typeIdentifier: symptom.typeIdentifier
                ).asFHIRStringPrimitive())
            )
        ]
    }

    private static func requiredSymptomSourceExtensions(
        _ symptom: HealthKitECGSymptomEvidence
    ) throws -> [Extension] {
        [
            try symptomSourceStringExtension(
                url: "sourceName",
                value: symptom.sourceName,
                sourceUUID: symptom.sourceUUID
            ),
            try symptomSourceStringExtension(
                url: "sourceBundleIdentifier",
                value: symptom.sourceBundleIdentifier,
                sourceUUID: symptom.sourceUUID
            )
        ]
    }

    private static func symptomOperatingSystemExtensions(
        _ symptom: HealthKitECGSymptomEvidence
    ) throws -> [Extension] {
        [
            try symptomSourceIntegerExtension(
                url: "sourceOperatingSystemMajorVersion",
                value: symptom.sourceOperatingSystemMajorVersion,
                sourceUUID: symptom.sourceUUID
            ),
            try symptomSourceIntegerExtension(
                url: "sourceOperatingSystemMinorVersion",
                value: symptom.sourceOperatingSystemMinorVersion,
                sourceUUID: symptom.sourceUUID
            ),
            try symptomSourceIntegerExtension(
                url: "sourceOperatingSystemPatchVersion",
                value: symptom.sourceOperatingSystemPatchVersion,
                sourceUUID: symptom.sourceUUID
            )
        ]
    }

    private static func validateSymptomState(
        _ status: HKElectrocardiogram.SymptomsStatus,
        symptomCount: Int
    ) throws {
        switch status {
        case .present:
            guard symptomCount > 0 else {
                throw GroveHealthKitFHIRError.invalidECGEvidence(.symptomsRequired)
            }
        case .none, .notSet:
            guard symptomCount == 0 else {
                throw GroveHealthKitFHIRError.invalidECGEvidence(.unexpectedSymptoms)
            }
        @unknown default:
            throw GroveHealthKitFHIRError.invalidECGEvidence(.unsupportedSymptomsStatus(status.rawValue))
        }
    }

    private static func validate(
        symptom: HealthKitECGSymptomEvidence,
        sourceIDs: inout Set<UUID>
    ) throws {
        let identifier = symptom.typeIdentifier
        guard correlatedSymptomTypeIdentifiers.contains(identifier) else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.unsupportedSymptomType(identifier))
        }
        guard sourceIDs.insert(symptom.sourceUUID).inserted else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.duplicateSymptomSource(symptom.sourceUUID))
        }
        guard symptom.endDate >= symptom.startDate else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSymptomPeriod(symptom.sourceUUID))
        }
        _ = try symptomExtension(symptom)
    }

    private static func symptomSourceStringExtension(
        url: String,
        value: String,
        sourceUUID: UUID
    ) throws -> Extension {
        guard !value.isEmpty else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSymptomSourceRevision(
                sourceUUID: sourceUUID,
                field: url
            ))
        }
        let parsedURL: FHIRPrimitive<FHIRURI>? = url.asFHIRURIPrimitive()
        guard let extensionURL = parsedURL else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSymptomSourceRevision(
                sourceUUID: sourceUUID,
                field: url
            ))
        }
        return Extension(url: extensionURL, value: .string(value.asFHIRStringPrimitive()))
    }

    private static func symptomSourceIntegerExtension(
        url: String,
        value: Int,
        sourceUUID: UUID
    ) throws -> Extension {
        guard let exactValue = Int32(exactly: value) else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSymptomSourceRevision(
                sourceUUID: sourceUUID,
                field: url
            ))
        }
        let parsedURL: FHIRPrimitive<FHIRURI>? = url.asFHIRURIPrimitive()
        guard let extensionURL = parsedURL else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSymptomSourceRevision(
                sourceUUID: sourceUUID,
                field: url
            ))
        }
        return Extension(url: extensionURL, value: .integer(FHIRPrimitive(FHIRInteger(exactValue))))
    }

    private static func symptomSeverityCode(_ value: Int, typeIdentifier: String) throws -> String {
        switch value {
        case HKCategoryValueSeverity.unspecified.rawValue: "unspecified"
        case HKCategoryValueSeverity.notPresent.rawValue: "notPresent"
        case HKCategoryValueSeverity.mild.rawValue: "mild"
        case HKCategoryValueSeverity.moderate.rawValue: "moderate"
        case HKCategoryValueSeverity.severe.rawValue: "severe"
        default:
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSymptomSeverity(
                typeIdentifier: typeIdentifier,
                value: value
            ))
        }
    }
}

#endif
