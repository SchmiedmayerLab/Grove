//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


public import Foundation
public import GroveFoundation


/// Protocol for content extraction strategies.
public protocol FHIRAttachmentContentExtractor {
    /// Determines if this extractor is compatible with the given content type.
    /// - Parameter contentType: The content type to check.
    /// - Returns: True if this extractor can handle the content type.
    func isCompatible(with contentType: MIMEType) -> Bool
    
    /// Extract readable content from data.
    /// - Parameter data: Binary data to extract content from.
    /// - Returns: Extracted text content.
    /// - Throws: Error if extraction fails.
    func extractContent(from data: Data) throws -> (MIMEType, Data)
}
