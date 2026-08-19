//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

// swiftlint:disable type_body_length function_body_length file_types_order


@testable import GroveFHIR
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsDSTU2
import ModelsR4
import Testing


enum FHIRTestVersion {
    case r4 // swiftlint:disable:this identifier_name
    case dstu2
}


extension ModelsR4::Base64Binary {
    fileprivate var decodedContents: String? {
        Data(base64Encoded: self.dataString).flatMap { String(data: $0, encoding: .utf8) }
    }
}

extension ModelsDSTU2::Base64Binary {
    fileprivate var decodedContents: String? {
        Data(base64Encoded: self.dataString).flatMap { String(data: $0, encoding: .utf8) }
    }
}


@Suite
struct FHIRResourceAttachmentProcessingTests {
    @Test(
        "Document Reference: Should fill multiple empty attachments sequentially",
        arguments: [FHIRTestVersion.r4, FHIRTestVersion.dstu2]
    )
    func testDocumentReferenceMultipleEmptyAttachments(_ version: FHIRTestVersion) throws {
        switch version {
        case .r4:
            var docRef = try ModelsR4Mocks.createDocumentReference()
            docRef.content = [
                DocumentReferenceContent(
                    attachment: Attachment(contentType: "application/pdf".asFHIRStringPrimitive())
                ),
                DocumentReferenceContent(
                    attachment: Attachment(contentType: "text/plain".asFHIRStringPrimitive())
                ),
                DocumentReferenceContent(
                    attachment: Attachment(contentType: "application/pdf".asFHIRStringPrimitive())
                )
            ]
            do {
                let attachments = [
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content-1".utf8)),
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content-2".utf8))
                ]
                var resource: any ModelsR4::Resource = docRef
                try FHIRResource.process(attachments, into: &resource)
                docRef = try #require(resource as? ModelsR4::DocumentReference)
            }
            #expect(docRef.content.count == 3, "Should have the original 3 attachments")
            
            let firstPdfAttachment = docRef.content[0].attachment
            #expect(firstPdfAttachment.contentType?.value?.string == "application/pdf")
            #expect(firstPdfAttachment.data?.value?.decodedContents == "pdf-content-1")
            
            let wordAttachment = docRef.content[1].attachment
            #expect(wordAttachment.contentType?.value?.string == "text/plain")
            #expect(wordAttachment.data == nil)
            
            let secondPdfAttachment = docRef.content[2].attachment
            #expect(secondPdfAttachment.contentType?.value?.string == "application/pdf")
            #expect(secondPdfAttachment.data?.value?.decodedContents == "pdf-content-2")
        case .dstu2:
            let emptyPdfAttachment1 = ModelsDSTU2.Attachment(
                contentType: "application/pdf".asFHIRStringPrimitive()
            )
            let emptyWordAttachment = ModelsDSTU2.Attachment(
                contentType: "text/plain".asFHIRStringPrimitive()
            )
            let emptyPdfAttachment2 = ModelsDSTU2.Attachment(
                contentType: "application/pdf".asFHIRStringPrimitive()
            )
            var docRef = try ModelsDSTU2Mocks.createDocumentReference(attachments: [
                emptyPdfAttachment1,
                emptyWordAttachment,
                emptyPdfAttachment2
            ])
            do {
                let attachments = [
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content-1".utf8)),
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content-2".utf8))
                ]
                var resource: any ModelsDSTU2::Resource = docRef
                try FHIRResource.process(attachments, into: &resource)
                docRef = try #require(resource as? ModelsDSTU2::DocumentReference)
            }
            #expect(docRef.content.count == 3, "Should still have the original 3 attachments")
            
            let firstPdfAttachment = docRef.content[0].attachment
            #expect(firstPdfAttachment.contentType?.value?.string == "application/pdf")
            #expect(firstPdfAttachment.data?.value?.decodedContents == "pdf-content-1")
            
            let textAttachment = docRef.content[1].attachment
            #expect(textAttachment.contentType?.value?.string == "text/plain")
            #expect(textAttachment.data == nil)
            
            let secondPdfAttachment = docRef.content[2].attachment
            #expect(secondPdfAttachment.contentType?.value?.string == "application/pdf")
            #expect(secondPdfAttachment.data?.value?.decodedContents == "pdf-content-2")
        }
    }
    
    
    @Test(
        "Diagnostic Report: Should fill multiple empty attachments sequentially",
        arguments: [FHIRTestVersion.r4, FHIRTestVersion.dstu2]
    )
    func testDiagnosticReportMultipleEmptyAttachments(_ version: FHIRTestVersion) throws {
        switch version {
        case .r4:
            var diagReport = try ModelsR4Mocks.createDiagnosticReport()
            diagReport.presentedForm = [
                Attachment(contentType: "application/pdf".asFHIRStringPrimitive()),
                Attachment(contentType: "text/plain".asFHIRStringPrimitive()),
                Attachment(contentType: "application/pdf".asFHIRStringPrimitive())
            ]
            do {
                let attachments = [
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content-1".utf8)),
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content-2".utf8))
                ]
                var resource: any ModelsR4::Resource = diagReport
                try FHIRResource.process(attachments, into: &resource)
                diagReport = try #require(resource as? ModelsR4::DiagnosticReport)
            }
            #expect(diagReport.presentedForm?.count == 3, "Should have the original 3 attachments")
            
            if let presentedForms = diagReport.presentedForm {
                let firstPdfAttachment = presentedForms[0]
                #expect(firstPdfAttachment.contentType?.value?.string == "application/pdf")
                #expect(firstPdfAttachment.data?.value?.decodedContents == "pdf-content-1")
                
                let textAttachment = presentedForms[1]
                #expect(textAttachment.contentType?.value?.string == "text/plain")
                #expect(textAttachment.data == nil)
                
                let secondPdfAttachment = presentedForms[2]
                #expect(secondPdfAttachment.contentType?.value?.string == "application/pdf")
                #expect(secondPdfAttachment.data?.value?.decodedContents == "pdf-content-2")
            }
        case .dstu2:
            var diagReport = try ModelsDSTU2Mocks.createDiagnosticReport()
            diagReport.presentedForm = [
                Attachment(contentType: "application/pdf".asFHIRStringPrimitive()),
                Attachment(contentType: "text/plain".asFHIRStringPrimitive()),
                Attachment(contentType: "application/pdf".asFHIRStringPrimitive())
            ]
            do {
                let attachments = [
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content-1".utf8)),
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content-2".utf8))
                ]
                var resource: any ModelsDSTU2::Resource = diagReport
                try FHIRResource.process(attachments, into: &resource)
                diagReport = try #require(resource as? ModelsDSTU2::DiagnosticReport)
            }
            #expect(diagReport.presentedForm?.count == 3, "Should have the original 3 attachments")
            
            if let presentedForms = diagReport.presentedForm {
                let firstPdfAttachment = presentedForms[0]
                #expect(firstPdfAttachment.contentType?.value?.string == "application/pdf")
                #expect(firstPdfAttachment.data?.value?.decodedContents == "pdf-content-1")
                
                let textAttachment = presentedForms[1]
                #expect(textAttachment.contentType?.value?.string == "text/plain")
                #expect(textAttachment.data == nil)
                
                let secondPdfAttachment = presentedForms[2]
                #expect(secondPdfAttachment.contentType?.value?.string == "application/pdf")
                #expect(secondPdfAttachment.data?.value?.decodedContents == "pdf-content-2")
            }
        }
    }
    
    
    @Test(
        "Should create new attachment when all existing ones are filled",
        arguments: [FHIRTestVersion.r4, FHIRTestVersion.dstu2]
    )
    func testCreateNewAttachmentWhenAllFilled(_ version: FHIRTestVersion) throws {
        switch version {
        case .r4:
            var docRef = try ModelsR4Mocks.createDocumentReference()
            let filledPdfAttachment = Attachment(
                contentType: "application/pdf".asFHIRStringPrimitive(),
                data: FHIRPrimitive(ModelsR4.Base64Binary("pdf-content-1"))
            )
            docRef.content = [
                DocumentReferenceContent(attachment: filledPdfAttachment)
            ]
            do {
                let attachments = [
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content-2".utf8))
                ]
                var resource: any ModelsR4::Resource = docRef
                try FHIRResource.process(attachments, into: &resource)
                docRef = try #require(resource as? ModelsR4::DocumentReference)
            }
            #expect(docRef.content.count == 2, "Should have 2 attachments")
            
            let originalPdfAttachment = docRef.content[0].attachment
            #expect(originalPdfAttachment.contentType?.value?.string == "application/pdf")
            #expect(originalPdfAttachment.data?.value?.dataString == "pdf-content-1")
            
            let newPdfAttachment = docRef.content[1].attachment
            #expect(newPdfAttachment.contentType?.value?.string == "application/pdf")
            #expect(newPdfAttachment.data?.value?.decodedContents == "pdf-content-2")
            
        case .dstu2:
            let filledPdfAttachment = ModelsDSTU2.Attachment(
                contentType: "application/pdf".asFHIRStringPrimitive(),
                data: FHIRPrimitive(ModelsDSTU2.Base64Binary("pdf-content-1"))
            )
            var docRef = try ModelsDSTU2Mocks.createDocumentReference(attachments: [filledPdfAttachment])
            do {
                let attachments = [
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content-2".utf8))
                ]
                var resource: any ModelsDSTU2::Resource = docRef
                try FHIRResource.process(attachments, into: &resource)
                docRef = try #require(resource as? ModelsDSTU2::DocumentReference)
            }
            #expect(docRef.content.count == 2, "Should have 2 attachments")
            
            let originalPdfAttachment = docRef.content[0].attachment
            #expect(originalPdfAttachment.contentType?.value?.string == "application/pdf")
            #expect(originalPdfAttachment.data?.value?.dataString == "pdf-content-1")
            
            let newPdfAttachment = docRef.content[1].attachment
            #expect(newPdfAttachment.contentType?.value?.string == "application/pdf")
            #expect(newPdfAttachment.data?.value?.decodedContents == "pdf-content-2")
        }
    }
    
    
    @Test(
        "Diagnostic Report: Should create new presentedForm array when none exists",
        arguments: [FHIRTestVersion.r4, FHIRTestVersion.dstu2]
    )
    func testDiagnosticReportCreateNewPresentedForm(_ version: FHIRTestVersion) throws {
        switch version {
        case .r4:
            var diagReport = try ModelsR4Mocks.createDiagnosticReport()
            diagReport.presentedForm = nil
            do {
                let attachments = [
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content".utf8))
                ]
                var resource: any ModelsR4::Resource = diagReport
                try FHIRResource.process(attachments, into: &resource)
                diagReport = try #require(resource as? ModelsR4::DiagnosticReport)
            }
            #expect(diagReport.presentedForm?.count == 1, "Should have 1 attachment")
            if let presentedForms = diagReport.presentedForm {
                let attachment = presentedForms[0]
                #expect(attachment.contentType?.value?.string == "application/pdf")
                #expect(attachment.data?.value?.decodedContents == "pdf-content")
            }

        case .dstu2:
            var diagReport = try ModelsDSTU2Mocks.createDiagnosticReport()
            diagReport.presentedForm = nil
            do {
                let attachments = [
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content".utf8))
                ]
                var resource: any ModelsDSTU2::Resource = diagReport
                try FHIRResource.process(attachments, into: &resource)
                diagReport = try #require(resource as? ModelsDSTU2::DiagnosticReport)
            }
            #expect(diagReport.presentedForm?.count == 1, "Should have 1 attachment")
            if let presentedForms = diagReport.presentedForm {
                let attachment = presentedForms[0]
                #expect(attachment.contentType?.value?.string == "application/pdf")
                #expect(attachment.data?.value?.decodedContents == "pdf-content")
            }
        }
    }
    
    
    @Test(
        "Diagnostic Report: Should append new attachment to existing presentedForm when no matching empty slots",
        arguments: [FHIRTestVersion.r4, FHIRTestVersion.dstu2]
    )
    func testDiagnosticReportAppendNewAttachment(_ version: FHIRTestVersion) throws {
        switch version {
        case .r4:
            var diagReport = try ModelsR4Mocks.createDiagnosticReport()
            diagReport.presentedForm = [
                Attachment(
                    contentType: "text/plain".asFHIRStringPrimitive(),
                    data: FHIRPrimitive(ModelsR4.Base64Binary("text-content"))
                )
            ]
            do {
                let attachments = [
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content".utf8))
                ]
                var resource: any ModelsR4::Resource = diagReport
                try FHIRResource.process(attachments, into: &resource)
                diagReport = try #require(resource as? ModelsR4::DiagnosticReport)
            }
            #expect(diagReport.presentedForm?.count == 2, "Should have 2 attachments")
            if let presentedForms = diagReport.presentedForm {
                let originalAttachment = presentedForms[0]
                #expect(originalAttachment.contentType?.value?.string == "text/plain")
                #expect(originalAttachment.data?.value?.dataString == "text-content")
                let newAttachment = presentedForms[1]
                #expect(newAttachment.contentType?.value?.string == "application/pdf")
                #expect(newAttachment.data?.value?.decodedContents == "pdf-content")
            }

        case .dstu2:
            var diagReport = try ModelsDSTU2Mocks.createDiagnosticReport()
            diagReport.presentedForm = [
                ModelsDSTU2.Attachment(
                    contentType: "text/plain".asFHIRStringPrimitive(),
                    data: FHIRPrimitive(ModelsDSTU2.Base64Binary("text-content"))
                )
            ]
            do {
                let attachments = [
                    HKSample.LoadedAttachment(contentType: .pdf, data: Data("pdf-content".utf8))
                ]
                var resource: any ModelsDSTU2::Resource = diagReport
                try FHIRResource.process(attachments, into: &resource)
                diagReport = try #require(resource as? ModelsDSTU2::DiagnosticReport)
            }
            #expect(diagReport.presentedForm?.count == 2, "Should have 2 attachments")
            if let presentedForms = diagReport.presentedForm {
                let originalAttachment = presentedForms[0]
                #expect(originalAttachment.contentType?.value?.string == "text/plain")
                #expect(originalAttachment.data?.value?.dataString == "text-content")
                let newAttachment = presentedForms[1]
                #expect(newAttachment.contentType?.value?.string == "application/pdf")
                #expect(newAttachment.data?.value?.decodedContents == "pdf-content")
            }
        }
    }
}

#endif
