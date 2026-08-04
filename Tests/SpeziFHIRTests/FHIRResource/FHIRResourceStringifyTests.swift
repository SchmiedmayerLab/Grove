//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(PDFKit) && canImport(UniformTypeIdentifiers)

import ModelsDSTU2
import ModelsR4
@testable import SpeziFHIR
import Testing
import UniformTypeIdentifiers


@Suite
struct FHIRResourceStringifyTests {
    private let service = FHIRAttachmentService()
    
    // MARK: - R4 Tests
    
    @Test("R4 text attachment should be properly stringified")
    func testR4TextAttachmentStringification() throws {
        let docRef = try ModelsR4Mocks.createDocumentReference(
            attachments: [try ModelsR4Mocks.createTextAttachment()]
        )
        var resource = FHIRResource(versionedResource: .r4(docRef), displayName: "Text Document")
        let originalBase64 = String(
            decoding: try #require((resource.r4 as? ModelsR4.DocumentReference)?.content.first?.attachment.data()),
            as: UTF8.self
        )
        
        try resource.stringifyAttachments(using: service)
        
        #expect(resource.displayName == "Text Document") // should stay unchanged
        let transformedContent = String(
            decoding: try #require((resource.r4 as? ModelsR4.DocumentReference)?.content.first?.attachment.data()),
            as: UTF8.self
        )
        #expect(transformedContent != originalBase64, "Content should be transformed")
        #expect(transformedContent == "Welcome to SpeziFHIR", "Content should now be human-readable")
    }
    
    
    @Test
    func r4TextAttachmentStringification() throws {
        let docRef = try ModelsR4Mocks.createDocumentReference(
            attachments: [try ModelsR4Mocks.createTextAttachment()]
        )
        var resource = FHIRResource(versionedResource: .r4(docRef), displayName: "R4 Document")
        var attachmentContent: String? {
            (resource.r4 as? ModelsR4.DocumentReference)?.content[0].attachment.data?.value?.dataString
        }
        #expect(attachmentContent == "V2VsY29tZSB0byBTcGV6aUZISVI=")
        try resource.stringifyAttachments(using: service)
        #expect(attachmentContent == "Welcome to SpeziFHIR")
    }
    
    
    @Test("R4 PDF attachment should extract text content")
    func testR4PDFAttachmentStringification() throws {
        let docRef = try ModelsR4Mocks.createDocumentReference(
            attachments: [try ModelsR4Mocks.createPDFAttachment()]
        )
        var resource = FHIRResource(versionedResource: .r4(docRef), displayName: "PDF Document")
        let originalBase64 = String(
            decoding: try #require((resource.r4 as? ModelsR4.DocumentReference)?.content.first?.attachment.data()),
            as: UTF8.self
        )
        
        try resource.stringifyAttachments(using: service)
        
        let transformedContent = String(
            decoding: try #require((resource.r4 as? ModelsR4.DocumentReference)?.content.first?.attachment.data()),
            as: UTF8.self
        )
        #expect(transformedContent != originalBase64, "Content should be transformed")
        #expect(transformedContent == "PDF: Welcome to SpeziFHIR", "Extracted content should contain PDF text")
    }
    
    
    @Test("R4 document with mixed attachments should process all attachments")
    func testR4MixedAttachmentsProcessing() throws {
        let docRef = try ModelsR4Mocks.createMixedDocumentReference()
        var resource = FHIRResource(versionedResource: .r4(docRef), displayName: "Mixed Document")
        let originalContents = try #require((resource.r4 as? ModelsR4.DocumentReference)?.content.compactMap { $0.attachment.data() })
        
        try resource.stringifyAttachments(using: service)
        
        let transformedContents = try #require((resource.r4 as? ModelsR4.DocumentReference)?.content.compactMap { $0.attachment.data() })
        for (index, originalContent) in originalContents.enumerated() {
            #expect(transformedContents[index] != originalContent, "Attachment \(index) should be transformed")
        }
    }
    
    
    @Test("Empty document reference should process no attachments")
    func testEmptyDocumentReferenceProcessesNoAttachments() throws {
        let docRef = try ModelsR4Mocks.createDocumentReference(attachments: [])
        var resource = FHIRResource(versionedResource: .r4(docRef), displayName: "Empty Document")

        try resource.stringifyAttachments(using: service)

        #expect(docRef.content.isEmpty, "Content array should remain empty")
    }
    
    
    // MARK: - DSTU2 Tests
    
    @Test("DSTU2 text attachment should be properly stringified")
    func testDSTU2TextAttachmentStringification() throws {
        let docRef = try ModelsDSTU2Mocks.createDocumentReference(
            attachments: [try ModelsDSTU2Mocks.createTextAttachment()]
        )
        var resource = FHIRResource(versionedResource: .dstu2(docRef), displayName: "DSTU2 Document")
        
        #expect((resource.dstu2 as? ModelsDSTU2.DocumentReference)?.content[0].attachment.data?.value?.dataString == "V2VsY29tZSB0byBTcGV6aUZISVI=")
        try resource.stringifyAttachments(using: service)
        #expect((resource.dstu2 as? ModelsDSTU2.DocumentReference)?.content[0].attachment.data?.value?.dataString == "Welcome to SpeziFHIR")
//        let transformedContent = attachment.base64String
////        attachment.data
//        #expect(transformedContent != nil)
//        #expect(transformedContent != originalBase64, "Content should be transformed")
//        #expect(transformedContent == "Welcome to SpeziFHIR", "Content should now be human-readable")
    }
    
    
    @Test("DSTU2 PDF attachment should extract text content")
    func testDSTU2PDFAttachmentStringification() throws {
        // Arrange - Create a document with a PDF attachment
        let docRef = try ModelsDSTU2Mocks.createDocumentReference(attachments: [try ModelsDSTU2Mocks.createPDFAttachment()])
        var resource = FHIRResource(versionedResource: .dstu2(docRef), displayName: "DSTU2 PDF Document")
        
        let originalBase64 = String(
            decoding: try #require((resource.dstu2 as? ModelsDSTU2.DocumentReference)?.content.first?.attachment.data()),
            as: UTF8.self
        )

        try resource.stringifyAttachments(using: service)

        let transformedContent = String(
            decoding: try #require((resource.dstu2 as? ModelsDSTU2.DocumentReference)?.content.first?.attachment.data()),
            as: UTF8.self
        )
        #expect(transformedContent != nil)
        #expect(transformedContent != originalBase64, "Content should be transformed")

        // The PDF content should now contain "PDF: Welcome to SpeziFHIR" text from the mock PDF
        #expect(transformedContent == "PDF: Welcome to SpeziFHIR", "Extracted content should contain PDF text")
    }
}

#endif
