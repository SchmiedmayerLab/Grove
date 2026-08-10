//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(PDFKit) && canImport(UniformTypeIdentifiers)

import Foundation
import PDFKit
@testable import SpeziFHIR
import Testing
import UniformTypeIdentifiers

private struct MockPDFDocumentProvider: PDFDocumentProviding {
    enum Result {
        case success(PDFDocument)
        case failure
    }

    let result: Result

    func createPDFDocument(from data: Data) -> PDFDocument? {
        switch result {
        case .success(let document):
            return document
        case .failure:
            return nil
        }
    }
}


private class MockPDFPage: PDFPage {
    private let mockAttributedString: NSAttributedString

    override var attributedString: NSAttributedString? {
        mockAttributedString
    }


    init(text: String) {
        self.mockAttributedString = NSAttributedString(string: text)
        super.init()
    }
}

private class MockPDFDocument: PDFDocument {
    private var mockPages: [MockPDFPage]

    override var pageCount: Int {
        mockPages.count
    }


    init(pages: [MockPDFPage]) {
        self.mockPages = pages
        super.init()
    }


    override func page(at index: Int) -> PDFPage? {
        guard index >= 0 && index < mockPages.count else {
            return nil
        }
        return mockPages[index]
    }
}

private class MockPartialPagesPDFDocument: PDFDocument {
    override var pageCount: Int { 3 }

    override func page(at index: Int) -> PDFPage? {
        if index == 1 {
            return nil
        }
        return MockPDFPage(text: "Page \(index + 1) content")
    }
}


@Suite
struct PDFContentExtractorTests {
    @Test("Successfully extracts text from PDF with single page")
    func testPDFSinglePageTextExtraction() throws {
        let expectedText = "This is test content for PDF extraction"
        let mockPage = MockPDFPage(text: expectedText)
        let mockPDFDocument = MockPDFDocument(pages: [mockPage])

        let extractor = PDFContentExtractor(
            documentProvider: MockPDFDocumentProvider(result: .success(mockPDFDocument))
        )

        let (outputType, extracted) = try extractor.extractContent(from: Data())
        #expect(String(decoding: extracted, as: UTF8.self) == expectedText)
    }

    @Test("Successfully extracts and combines text from multi-page PDF")
    func testPDFMultiPageTextExtraction() throws {
        let page1Text = "Page 1 text"
        let page2Text = "Page 2 text"
        let page3Text = "Page 3 text"

        let mockPages = [
            MockPDFPage(text: page1Text),
            MockPDFPage(text: page2Text),
            MockPDFPage(text: page3Text)
        ]

        let extractor = PDFContentExtractor(
            documentProvider: MockPDFDocumentProvider(result: .success(MockPDFDocument(pages: mockPages)))
        )

        let (outputType, extracted) = try extractor.extractContent(from: Data())
        #expect(outputType == .plainText)
        let extractedText = String(decoding: extracted, as: UTF8.self)
        #expect(extractedText.contains(page1Text))
        #expect(extractedText.contains(page2Text))
        #expect(extractedText.contains(page3Text))
    }

    @Test("Successfully extracts text from PDF with missing pages")
    func testPDFWithMissingPages() throws {
        let extractor = PDFContentExtractor(
            documentProvider: MockPDFDocumentProvider(result: .success(MockPartialPagesPDFDocument()))
        )

        let (outputType, extracted) = try extractor.extractContent(from: Data())
        let extractedText = String(decoding: extracted, as: UTF8.self)
        #expect(extractedText.contains("Page 1 content"))
        #expect(!extractedText.contains("Page 2 content"))
        #expect(extractedText.contains("Page 3 content"))
    }

    @Test("Throws error when PDF parsing fails")
    func testPDFParsingFailure() throws {
        let extractor = PDFContentExtractor(documentProvider: MockPDFDocumentProvider(result: .failure))
        do {
            _ = try extractor.extractContent(from: Data())
        } catch let error as FHIRAttachmentError {
            #expect(error == .pdfParsingFailed)
        }
    }

    @Test("Correctly identifies compatible content types")
    func testCompatibleContentTypes() {
        let extractor = PDFContentExtractor()

        if let applicationPdfUTType = UTType(mimeType: "application/pdf") {
            #expect(extractor.isCompatible(with: applicationPdfUTType))
        } else {
            Issue.record("Failed to create UTType for application/pdf")
        }

        if let textPlainUTType = UTType(mimeType: "text/plain") {
            #expect(!extractor.isCompatible(with: textPlainUTType))
        } else {
            Issue.record("Failed to create UTType for text/plain")
        }
    }
}

#endif
