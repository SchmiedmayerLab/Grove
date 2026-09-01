//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

import Foundation
@testable import GroveFHIR
import GroveFoundation
import Testing
import UniformTypeIdentifiers


@Suite
struct TextContentExtractorTests {
    private let textExtractor = TextContentExtractor()

    @Test("Successfully extracts content from text data")
    func testTextExtraction() throws {
        let input = Data("Welcome to GroveFHIR".utf8)
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
        #expect(textExtractor.isCompatible(with: .plainText))
        #expect(textExtractor.isCompatible(with: "text/html"))
        #expect(!textExtractor.isCompatible(with: .pdf))
    }
}

#endif
