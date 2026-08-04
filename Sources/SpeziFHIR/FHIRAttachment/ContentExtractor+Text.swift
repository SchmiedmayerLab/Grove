//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

import Foundation
import UniformTypeIdentifiers


/// Extractor for plain text content types.
struct TextContentExtractor: ContentExtractor {
    func isCompatible(with contentType: UTType) -> Bool {
        contentType.conforms(to: .text)
    }
    
    func extractContent(from data: Data) throws -> (UTType, Data) {
        // TODO is this step really still needed?
        guard let string = String(data: data, encoding: .utf8) else {
            throw FHIRAttachmentError.textDecodingFailed
        }
        return (.text, Data(string.utf8))
    }
}

#endif
