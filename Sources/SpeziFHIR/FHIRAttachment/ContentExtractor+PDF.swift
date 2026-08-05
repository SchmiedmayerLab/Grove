//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

public import Foundation
#if canImport(PDFKit)
private import PDFKit
#endif
public import UniformTypeIdentifiers


/// Extractor for PDF document content types.
public struct PDFContentExtractor: FHIRAttachmentContentExtractor {
    private struct NotAvailableError: Error {}
    
    private let documentProvider: any PDFDocumentProviding
    
    init() {
        self.documentProvider = DefaultPDFDocumentProvider()
    }
    
    init(documentProvider: any PDFDocumentProviding) {
        self.documentProvider = documentProvider
    }
    
    public func isCompatible(with contentType: UTType) -> Bool {
        #if canImport(PDFKit)
        contentType.conforms(to: .pdf)
        #else
        false
        #endif
    }
    
    public func extractContent(from data: Data) throws -> (UTType, Data) {
        #if canImport(PDFKit)
        guard let pdf = documentProvider.createPDFDocument(from: data) else {
            throw FHIRAttachmentError.pdfParsingFailed
        }
        let documentContent = NSMutableAttributedString()
        for pageIdx in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIdx), let content = page.attributedString else {
                continue
            }
            documentContent.append(content)
        }
        return (.plainText, Data(documentContent.string.utf8))
        #else
        throw NotAvailableError()
        #endif
    }
}


extension FHIRAttachmentContentExtractor where Self == PDFContentExtractor {
    /// A content extractor that transforms PDF documents into plain text.
    public static var pdf: Self {
        Self()
    }
}

#endif
