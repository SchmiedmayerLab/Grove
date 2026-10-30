//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

public import Foundation
public import GroveFoundation
#if canImport(PDFKit)
private import PDFKit
#endif


/// Extractor for PDF document content types.
public struct PDFContentExtractor: FHIRAttachmentContentExtractor {
    // periphery:ignore - thrown from the no-PDFKit branch (the scan indexes a destination that has PDFKit)
    private struct NotAvailableError: Error {}
    #if canImport(PDFKit)
    private let documentProvider: any PDFDocumentProviding

    init() {
        self.documentProvider = DefaultPDFDocumentProvider()
    }

    init(documentProvider: any PDFDocumentProviding) {
        self.documentProvider = documentProvider
    }
    #else
    init() {}
    #endif
    
    public func isCompatible(with contentType: MIMEType) -> Bool {
        #if canImport(PDFKit)
        contentType.utType?.conforms(to: .pdf) ?? false
        #else
        false
        #endif
    }
    
    public func extractContent(from data: Data) throws -> (MIMEType, Data) {
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
    ///
    /// On platforms where no PDFKit is available, the extractor does nothing.
    public static var pdf: Self {
        Self()
    }
}

#endif
