//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

public import Foundation
public import UniformTypeIdentifiers


/// Extractor for plain text content types.
public struct TextContentExtractor: FHIRAttachmentContentExtractor {
    public func isCompatible(with contentType: UTType) -> Bool {
        contentType.conforms(to: .text)
    }
    
    public func extractContent(from data: Data) throws -> (UTType, Data) {
        // TODO is this step really still needed?
        guard let string = String(data: data, encoding: .utf8) else {
            throw FHIRAttachmentError.textDecodingFailed
        }
        return (.plainText, Data(string.utf8))
    }
}


extension FHIRAttachmentContentExtractor where Self == TextContentExtractor {
    public static var text: Self {
        Self()
    }
}

#endif
