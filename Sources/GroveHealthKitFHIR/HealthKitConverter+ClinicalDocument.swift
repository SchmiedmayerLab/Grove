//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit) && !os(watchOS)

import Foundation
public import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// Carries one CDA document exactly as HealthKit delivered it.
    ///
    /// The bytes are another issuer's document. Grove identifies it and records who wrote it, and
    /// never rewrites, reserializes, or asserts conformance over it — the same treatment a
    /// provider-issued clinical record receives.
    ///
    /// - Note: `HKCDADocumentSample.document` is populated only for a sample returned by an
    ///   `HKDocumentQuery` that asked for document data, so a sample from any other query fails
    ///   closed rather than converting to an empty payload.
    public func convert(
        _ sample: HKCDADocumentSample,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitDocumentConversion {
        do {
            guard let document = sample.document,
                  let data = document.documentData,
                  !data.isEmpty else {
                throw HealthKitConversionError.missingClinicalDocumentData(sample.uuid)
            }
            let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return try Self.assembleDocumentGraph(
                for: sample,
                evidence: HealthKitRecordingEvidence(
                    format: .clinicalDocument,
                    title: title.isEmpty ? "Clinical document" : title,
                    payload: data
                ),
                context: context
            )
        } catch {
            throw HealthKitConversionError(conversionFailure: error)
        }
    }
}

#endif
