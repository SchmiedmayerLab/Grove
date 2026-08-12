//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(PDFKit) && canImport(UniformTypeIdentifiers)

@testable import GroveFHIR
import PDFKit
import Testing
import UniformTypeIdentifiers


private struct MockFHIRAttachment: FHIRAttachment {
    var _contentTypeString: String? // swiftlint:disable:this identifier_name
    var _base64String: String? // swiftlint:disable:this identifier_name
    
    init() {}
    
    init(data: Data, mimeType: UTType) {
        self.init()
        self.setData(data, mimeType: mimeType)
    }
}


@Suite
struct FHIRAttachmentServiceTests {
    @Test("Successfully stringifies text content")
    func testStringifyTextContent() throws {
        let textType = try #require(UTType(mimeType: "text/plain"))
        #expect(textType == .plainText)
        
        var attachment = MockFHIRAttachment(
            data: Data("Welcome to GroveFHIR".utf8),
            mimeType: textType
        )
        
        #expect(attachment.mimeType == .plainText)
        #expect(attachment._base64String == "V2VsY29tZSB0byBHcm92ZUZISVI=")
        #expect(attachment.data() == Data("Welcome to GroveFHIR".utf8))
        
        try attachment.stringify(using: .init())
        #expect(attachment.mimeType == .plainText)
        #expect(attachment._base64String == "V2VsY29tZSB0byBHcm92ZUZISVI=")
        #expect(attachment.data() == Data("Welcome to GroveFHIR".utf8))
        
        try attachment.stringify(using: .init(skipBase64EncodeIfPossible: true))
        #expect(attachment.mimeType == .plainText)
        #expect(attachment._base64String == "Welcome to GroveFHIR")
        #expect(attachment.data() == nil)
    }
    
    
    @Test("Successfully stringifies PDF content")
    func testStringifyPDFContent() throws {
        let pdfType = try #require(UTType(mimeType: "application/pdf"))
        #expect(pdfType == .pdf)
        // swiftlint:disable:next line_length
        let pdfBase64 = "JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNzkyXSAvUmVzb3VyY2VzIDw8IC9Gb250IDw8IC9GMSA0IDAgUiA+PiA+PiAvQ29udGVudHMgNSAwIFIgPj4KZW5kb2JqCjQgMCBvYmoKPDwgL1R5cGUgL0ZvbnQgL1N1YnR5cGUgL1R5cGUxIC9CYXNlRm9udCAvSGVsdmV0aWNhID4+CmVuZG9iago1IDAgb2JqCjw8IC9MZW5ndGggNDQgPj4Kc3RyZWFtCkJUCi9GMSAxNiBUZgo1MCA3MDAgVGQKKFBERjogV2VsY29tZSB0byBHcm92ZUZISVIpIFRqCkVUCmVuZHN0cmVhbQplbmRvYmoKeHJlZgowIDYKMDAwMDAwMDAwMCA2NTUzNSBmCjAwMDAwMDAwMDkgMDAwMDAgbgowMDAwMDAwMDU4IDAwMDAwIG4KMDAwMDAwMDExNSAwMDAwMCBuCjAwMDAwMDAyMjkgMDAwMDAgbgowMDAwMDAwMjk1IDAwMDAwIG4KdHJhaWxlcgo8PCAvU2l6ZSA2IC9Sb290IDEgMCBSID4+CnN0YXJ0eHJlZgozOTEKJSVFT0Y="
        var attachment = MockFHIRAttachment(
            data: try #require(Data(base64Encoded: pdfBase64)),
            mimeType: pdfType
        )
        #expect(attachment._base64String == pdfBase64)
        #expect(attachment.mimeType == .pdf)
        
        try attachment.stringify(using: .init())
        #expect(attachment.data() == Data("PDF: Welcome to GroveFHIR".utf8))
        #expect(attachment.mimeType == .plainText)
        
        try attachment.stringify(using: .init(skipBase64EncodeIfPossible: true))
        #expect(attachment.mimeType == .plainText)
        #expect(attachment._base64String == "PDF: Welcome to GroveFHIR")
    }
    
    
    @Test("Throws error when MIME type is missing")
    func testMissingMimeType() {
        var attachment = MockFHIRAttachment()
        attachment._contentTypeString = nil
        attachment._base64String = "V2VsY29tZSB0byBHcm92ZUZISVI="
        #expect(throws: FHIRAttachmentError.missingMimeType) {
            try attachment.stringify(using: .init())
        }
    }
    
    
    @Test("Throws error when base64 string is missing")
    func testMissingBase64String() throws {
        var attachment = MockFHIRAttachment()
        attachment._contentTypeString = try #require(UTType(mimeType: "text/plain")).preferredMIMEType
        attachment._base64String = nil
        #expect(throws: FHIRAttachmentError.noData) {
            try attachment.stringify(using: .init())
        }
    }
    
    
    @Test("Throws error when base64 data is invalid")
    func testInvalidBase64Data() throws {
        var attachment = MockFHIRAttachment()
        attachment._contentTypeString = try #require(UTType(mimeType: "text/plain")).preferredMIMEType
        attachment._base64String = "invalid-base64-string"
        #expect(throws: FHIRAttachmentError.noData) {
            try attachment.stringify(using: .init())
        }
    }
    
    
    @Test("Throws error when content type is unsupported")
    func testUnsupportedContentType() throws {
        let customType = try #require(UTType(mimeType: "application/custom"))
        var attachment = MockFHIRAttachment()
        attachment._contentTypeString = customType.preferredMIMEType
        attachment._base64String = "V2VsY29tZSB0byBHcm92ZUZISVI="
        #expect(throws: FHIRAttachmentError.unsupportedContentType(customType)) {
            try attachment.stringify(using: .init(contentExtractors: [.text]))
        }
    }
    
    
    @Test("Throws error when no extractors are available")
    func testServiceWithEmptyExtractors() throws {
        let textPlainType = try #require(UTType(mimeType: "text/plain"))
        var attachment = MockFHIRAttachment()
        attachment._contentTypeString = textPlainType.preferredMIMEType
        attachment._base64String = "SGVsbG8sIHdvcmxkIQ=="
        #expect(throws: FHIRAttachmentError.unsupportedContentType(textPlainType)) {
            try attachment.stringify(using: .init(contentExtractors: []))
        }
    }
}

#endif
