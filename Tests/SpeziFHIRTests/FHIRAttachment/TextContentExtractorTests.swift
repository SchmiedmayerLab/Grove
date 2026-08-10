//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

import Foundation
@testable import SpeziFHIR
import Testing
import UniformTypeIdentifiers


@Suite
struct TextContentExtractorTests {
    private let textExtractor = TextContentExtractor()

    @Test("Successfully extracts content from text data")
    func testTextExtraction() throws {
        let input = Data("Welcome to SpeziFHIR".utf8)
        let (type, output) = try textExtractor.extractContent(from: input)
        #expect(type == .plainText)
        #expect(output == input)
    }

    @Test("Throws error when text decoding fails")
    func testTextDecodingFailure() throws {
        let invalidData = Data([0xFF, 0xFE, 0xFD])
        do {
            _ = try textExtractor.extractContent(from: invalidData)
        } catch let error as FHIRAttachmentError {
            #expect(error == .textDecodingFailed)
        }
    }

    @Test("Correctly identifies compatible content types")
    func testCompatibleContentTypes() {
        if let textPlainUTType = UTType(mimeType: "text/plain") {
            #expect(textExtractor.isCompatible(with: textPlainUTType))
        } else {
            Issue.record("Failed to create UTType for text/plain")
        }
        if let textHtmlUTType = UTType(mimeType: "text/html") {
            #expect(textExtractor.isCompatible(with: textHtmlUTType))
        } else {
            Issue.record("Failed to create UTType for text/html")
        }
        if let applicationPdfUTType = UTType(mimeType: "application/pdf") {
            #expect(!textExtractor.isCompatible(with: applicationPdfUTType))
        } else {
            Issue.record("Failed to create UTType for application/pdf")
        }
    }
}

#endif
