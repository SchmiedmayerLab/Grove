//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract
import ModelsR4


/// The parts of a source type's recording or clinical document that every document of the type shares.
///
/// The bytes are carried exactly as HealthKit delivered them; the guide: "Do not parse and reserialize, relabel,
/// upgrade, downgrade, or otherwise rewrite those bytes."
@available(iOS 18, macOS 15, watchOS 11, *)
struct DocumentPlan: Sendable {
    /// The registered format of the carried bytes.
    let format: RegisteredRecordingFormat
    /// The DocumentReference before its content: status current, its profiles, its type and the source-type extension.
    let skeleton: DocumentReference
    /// The content's format coding.
    let formatCoding: Coding
    /// The attachment's title; a CDA document states its own and falls back to this one.
    let title: String

    /// The plan of documents of `format` claiming `profiles`, typed by `typeCoding`, else by their format.
    init(
        sourceType: HealthKitSourceType,
        format: RegisteredRecordingFormat,
        profiles: [FHIRPrimitive<Canonical>],
        typeCoding: Coding? = nil,
        title: String
    ) {
        let formatCoding = Coding(format.rawValue, system: RecordingFormatContract.recordingFormatCodeSystem)
        var skeleton = DocumentReference(
            content: [],
            meta: Meta(profile: profiles),
            status: FHIRPrimitive(.current),
            type: CodeableConcept(coding: [typeCoding ?? formatCoding])
        )
        skeleton.extension = [sourceType.lineage]
        self.format = format
        self.skeleton = skeleton
        self.formatCoding = formatCoding
        self.title = title
    }
}

#endif
