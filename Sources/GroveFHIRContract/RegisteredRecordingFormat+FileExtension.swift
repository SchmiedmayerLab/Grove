//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


extension RegisteredRecordingFormat {
    /// A conventional filename extension for this format's registered representation.
    ///
    /// It is transport metadata only; `DocumentReference.content.format` and `contentType` remain
    /// authoritative. PPG uses generic `bin` so new Grove bytes cannot be mistaken for a legacy
    /// application-specific PPG encoding.
    public var fileExtension: String {
        if Self.tabularFormats.contains(self) {
            return "csv"
        }
        return switch self {
        case .clinicalDocument: "xml"
        case .fhirCollectionBundle, .fhirResource, .nativeRecording, .providerRecording: "json"
        default: "bin"
        }
    }
}
