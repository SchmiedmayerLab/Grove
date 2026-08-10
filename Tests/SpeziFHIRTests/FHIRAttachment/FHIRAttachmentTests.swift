//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

import ModelsDSTU2
import ModelsR4
@testable import SpeziFHIR
import Testing
import UniformTypeIdentifiers


enum FHIRModel {
    case dstu2
    case r4  // swiftlint:disable:this identifier_name

    var description: String {
        switch self {
        case .dstu2: return "DSTU2"
        case .r4: return "R4"
        }
    }
}

enum FHIRAttachmentTestHelper {
    static func createAttachment(model: FHIRModel) -> any FHIRAttachment {
        switch model {
        case .dstu2:
            return ModelsDSTU2.Attachment()
        case .r4:
            return ModelsR4.Attachment()
        }
    }

    static func createAttachment(contentType: String, model: FHIRModel) -> any FHIRAttachment {
        switch model {
        case .dstu2:
            ModelsDSTU2.Attachment(contentType: contentType.asFHIRStringPrimitive())
        case .r4:
            ModelsR4.Attachment(contentType: contentType.asFHIRStringPrimitive())
        }
    }

    static func createAttachment(data: String, contentType: UTType, model: FHIRModel) -> any FHIRAttachment {
        var attachment: any FHIRAttachment = switch model {
        case .dstu2:
            ModelsDSTU2.Attachment()
        case .r4:
            ModelsR4.Attachment()
        }
        attachment.setData(Data(data.utf8), mimeType: contentType)
        return attachment
    }
}

@Suite
struct FHIRAttachmentTests {
    @Test(
        "Attachment returns correct mime type",
        arguments: [FHIRModel.dstu2, FHIRModel.r4]
    )
    func testMimeType(_ model: FHIRModel) {
        let attachment = FHIRAttachmentTestHelper.createAttachment(contentType: "text/plain", model: model)
        let mimeType = attachment.mimeType
        #expect(mimeType != nil, "\(model.description) attachment should have non-nil MIME type")
        #expect(mimeType?.preferredMIMEType == "text/plain", "\(model.description) attachment should have correct MIME type")
    }
    
    
    @Test(
        "Attachment returns nil for empty mime type",
        arguments: [FHIRModel.dstu2, FHIRModel.r4]
    )
    func testEmptyMimeType(_ model: FHIRModel) {
        let attachment = FHIRAttachmentTestHelper.createAttachment(contentType: "", model: model)
        let mimeType = attachment.mimeType
        #expect(mimeType == nil, "\(model.description) attachment should return nil for empty MIME type")
    }
    
    
    @Test(
        "Attachment returns nil for missing mime type",
        arguments: [FHIRModel.dstu2, FHIRModel.r4]
    )
    func testMissingMimeType(_ model: FHIRModel) {
        let attachment = FHIRAttachmentTestHelper.createAttachment(model: model)
        let mimeType = attachment.mimeType
        #expect(mimeType == nil, "\(model.description) attachment should return nil for missing MIME type")
    }
    
    
    @Test(
        "Attachment returns base64 string",
        arguments: [FHIRModel.dstu2, FHIRModel.r4]
    )
    func testBase64String(_ model: FHIRModel) throws {
        let testString = "Test content"
        let attachment = FHIRAttachmentTestHelper.createAttachment(
            data: testString,
            contentType: .plainText,
            model: model
        )
        let content = String(decoding: try #require(attachment.data()), as: UTF8.self)
        #expect(content == testString)
    }
    
    
    @Test(
        "Attachment returns nil for missing base64 string",
        arguments: [FHIRModel.dstu2, FHIRModel.r4]
    )
    func testMissingBase64String(_ model: FHIRModel) {
        let attachment = FHIRAttachmentTestHelper.createAttachment(model: model)
        #expect(attachment.data() == nil)
    }
    
    
    @Test(
        "Attachment encodes content correctly",
        arguments: [FHIRModel.dstu2, FHIRModel.r4]
    )
    func testEncodeContent(_ model: FHIRModel) {
        var attachment = FHIRAttachmentTestHelper.createAttachment(model: model)
        let testContent = Data("This is test content".utf8)
        attachment.setData(testContent, mimeType: .text)
        #expect(attachment.data() == testContent, "\(model.description) attachment should encode content correctly")
    }
}

#endif
