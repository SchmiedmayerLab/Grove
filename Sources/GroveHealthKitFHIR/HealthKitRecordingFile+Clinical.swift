//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit) && !os(watchOS)

import Foundation
import GroveFHIRContract
public import HealthKit


@available(iOS 18, macOS 15, *)
extension HealthKitRecordingFile {
    /// Stages the original provider resource without changing its JSON, release or media type.
    /// HealthKit supplies the complete Data; downstream attachment conversion and upload use the staged file.
    /// The sample dates remain download-to-device facts, never a clinical service period.
    nonisolated(nonsending) public static func clinicalRecord(
        _ record: HKClinicalRecord, relativePath: String, maximumByteCount: Int
    ) async throws -> Self {
        let plan = try clinicalPlan(record, relativePath: relativePath)
        let payload = try plan.clinicalPayload(record, maximumByteCount: maximumByteCount)
        return try await stage(payload, sample: record, plan: plan, relativePath: relativePath, maximumByteCount: maximumByteCount)
    }

    /// Stages the CDA bytes returned by an authorized HealthKit document query, preserving their title and media type.
    /// The caller-supplied document sample dates are not interpreted as a download or clinical service period.
    nonisolated(nonsending) public static func cdaDocument(
        _ sample: HKCDADocumentSample, relativePath: String, maximumByteCount: Int
    ) async throws -> Self {
        let plan = try clinicalPlan(sample, relativePath: relativePath)
        let payload = try plan.clinicalPayload(sample, maximumByteCount: maximumByteCount)
        return try await stage(payload, sample: sample, plan: plan, relativePath: relativePath, maximumByteCount: maximumByteCount)
    }

    private static func clinicalPlan(_ sample: HKSample, relativePath: String) throws -> DocumentPlan {
        try Task.checkCancellation()
        guard RecordingFile.isRelativeAttachmentPath(relativePath) else { throw RecordingError.invalidRelativePath }
        guard let type = HealthKitSourceType(sample), case .clinical(let document) = HealthKitContentPlan[type].route else {
            throw HealthKitConversionError.ValueFailure.shapeInvalid
        }
        return document
    }

    private static func stage(
        _ payload: DocumentPlan.ClinicalPayload, sample: HKSample, plan: DocumentPlan, relativePath: String, maximumByteCount: Int
    ) async throws -> Self {
        let chunks = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(1)) { continuation in
            continuation.yield(payload.data)
            continuation.finish()
        }
        let file = try await RecordingFile.stage(chunks: chunks, maximumByteCount: Int64(maximumByteCount))
        return Self(
            file: file,
            relativePath: relativePath,
            format: plan.format,
            sample: sample,
            attachmentTitle: payload.title,
            attachmentContentType: payload.contentType
        )
    }
}

#endif
