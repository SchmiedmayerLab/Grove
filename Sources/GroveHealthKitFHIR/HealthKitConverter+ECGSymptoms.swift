//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    private static let correlatedSymptomTypeIdentifiers: Set<String> = [
        HKCategoryTypeIdentifier.rapidPoundingOrFlutteringHeartbeat.rawValue,
        HKCategoryTypeIdentifier.skippedHeartbeat.rawValue,
        HKCategoryTypeIdentifier.fatigue.rawValue,
        HKCategoryTypeIdentifier.shortnessOfBreath.rawValue,
        HKCategoryTypeIdentifier.chestTightnessOrPain.rawValue,
        HKCategoryTypeIdentifier.fainting.rawValue,
        HKCategoryTypeIdentifier.dizziness.rawValue
    ]

    /// Validates the ECG relationship and returns a deterministic ordering of the original samples.
    ///
    /// Clinical content is validated again by each symptom's normal catalog-driven conversion. The
    /// ECG layer owns only relationship constraints: admitted symptom types, status consistency,
    /// and uniqueness of source revisions. The seven entries below are admitted *types*, not a
    /// cardinality cap: HealthKit may provide multiple distinct samples of the same symptom type.
    static func validatedSymptomSamples(
        _ symptoms: [HKCategorySample],
        status: HKElectrocardiogram.SymptomsStatus
    ) throws -> [HKCategorySample] {
        try validateSymptomState(status, symptomCount: symptoms.count)
        var sourceIDs: Set<UUID> = []
        for symptom in symptoms {
            let identifier = symptom.categoryType.identifier
            guard correlatedSymptomTypeIdentifiers.contains(identifier) else {
                throw HealthKitConversionError.invalidECGEvidence(.unsupportedSymptomType(identifier))
            }
            guard sourceIDs.insert(symptom.uuid).inserted else {
                throw HealthKitConversionError.invalidECGEvidence(.duplicateSymptomSource(symptom.uuid))
            }
        }
        return symptoms.sorted {
            let left = ($0.categoryType.identifier, $0.uuid.uuidString.lowercased())
            let right = ($1.categoryType.identifier, $1.uuid.uuidString.lowercased())
            return left < right
        }
    }

    private static func validateSymptomState(
        _ status: HKElectrocardiogram.SymptomsStatus,
        symptomCount: Int
    ) throws {
        switch status {
        case .present:
            guard symptomCount > 0 else {
                throw HealthKitConversionError.invalidECGEvidence(.symptomsRequired)
            }
        case .none, .notSet:
            guard symptomCount == 0 else {
                throw HealthKitConversionError.invalidECGEvidence(.unexpectedSymptoms)
            }
        @unknown default:
            throw HealthKitConversionError.invalidECGEvidence(.unsupportedSymptomsStatus(status.rawValue))
        }
    }
}

#endif
