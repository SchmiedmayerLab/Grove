//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
import PDFKit
private import PencilKit
private import TPPDF


@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
struct PDFRenderer {
    enum ExportError: Error {
        case unableToProducePDF
    }
    
    private let consentDocument: ConsentDocument
    private let config: ConsentDocument.ExportConfiguration
    
    private let pdf: TPPDF.PDFDocument

    init(consentDocument: ConsentDocument, config: ConsentDocument.ExportConfiguration) {
        self.consentDocument = consentDocument
        self.config = config
        self.pdf = TPPDF.PDFDocument(format: config.paperSize.pdfPageFormat)
    }
    
    
    consuming func render() throws -> sending PDFKit.PDFDocument {
        if let title = consentDocument.metadata.title, !title.isEmpty {
            pdf.info.title = title
        }
        if config.includingTimestamp {
            pdf.add(.contentRight, attributedTextObject: renderedExportTimestamp())
            pdf.add(space: 12)
        }
        if let header = renderedHeader() {
            pdf.add(.contentCenter, attributedTextObject: header)
            pdf.add(space: 18)
        }
        for section in consentDocument.sections {
            try add(section)
        }
        let pdfData = try PDFGenerator(document: pdf).generateData()
        guard let pdfDocument = PDFKit.PDFDocument(data: pdfData) else {
            throw ExportError.unableToProducePDF // should be unreachable
        }
        return pdfDocument
    }
    
    
    private func renderedExportTimestamp() -> PDFAttributedText {
        let date = DateFormatter.localizedString(from: .now, dateStyle: .medium, timeStyle: .short)
        let text = String(localized: "Exported: \(date)", bundle: .module)
        let attributedTitle = NSMutableAttributedString(
            string: text,
            attributes: [.font: config.fontSettings.headerExportTimeStampFont]
        )
        return PDFAttributedText(text: attributedTitle)
    }
    
    /// Exports the header text (i.e., document title) as a `PDFAttributedText`
    private func renderedHeader() -> PDFAttributedText? {
        guard let title = consentDocument.metadata.title, !title.isEmpty else {
            return nil
        }
        let attributedTitle = NSMutableAttributedString(
            string: title,
            attributes: [.font: config.fontSettings.headerTitleFont]
        )
        return PDFAttributedText(text: attributedTitle)
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension PDFRenderer {
    private func add(_ section: ConsentDocument.Section) throws {
        switch section {
        case .markdown(let rawContent):
            try addMarkdownBlock(rawContent)
        case .signature(let config):
            addRenderedSignature(config)
        case .toggle(let config):
            try addToggleBlock(config)
        case .select(let config):
            try addSelectBlock(config)
        }
    }
    
    
    private func addMarkdownBlock(_ text: String) throws {
        try ConsentMarkdownPDF(font: config.fontSettings.documentContentFont).append(text, to: pdf)
    }
    
    
    private func addToggleBlock(_ toggleConfig: ConsentDocumentFormat.Toggle) throws {
        let state = consentDocument.value(for: toggleConfig)
        let cellStyle = PDFTableCellStyle(
            borders: .none,
            font: config.fontSettings.documentContentFont
        )
        let table = PDFTable(rows: 1, columns: 2)
        table.widths = [0.8, 0.2] // sadly can't make this dynamic :/
        table.style.outline = .none
        table[0, 0] = PDFTableCell(
            content: try .init(content: ConsentMarkdownPDF(font: config.fontSettings.documentContentFont).label(toggleConfig.text)),
            alignment: .left,
            style: cellStyle
        )
        table[0, 1] = PDFTableCell(
            content: try .init(content: String(localized: state ? "Yes" : "No", bundle: .module)),
            alignment: .right,
            style: cellStyle
        )
        let group = consentCard()
        group.add(.left, table: table)
        pdf.add(group: group)
        pdf.add(space: 12)
    }
    
    
    private func addSelectBlock(_ selectConfig: ConsentDocumentFormat.Selection) throws {
        let selection = consentDocument.value(for: selectConfig)
        let cellStyle = PDFTableCellStyle(
            borders: .none,
            font: config.fontSettings.documentContentFont
        )
        let table = PDFTable(rows: 1, columns: 2)
        table.widths = [0.75, 0.25] // sadly can't make this dynamic :/
        table.style.outline = .none
        table[0, 0] = PDFTableCell(
            content: try .init(content: ConsentMarkdownPDF(font: config.fontSettings.documentContentFont).label(selectConfig.text)),
            alignment: .left,
            style: cellStyle
        )
        table[0, 1] = PDFTableCell(
            content: try .init(content: ConsentMarkdownPDF(font: config.fontSettings.documentContentFont).label(
                selectConfig.options.first { $0.id == selection }?.title ?? ""
            )),
            alignment: .right,
            style: cellStyle
        )
        let group = consentCard()
        group.add(.left, table: table)
        pdf.add(group: group)
        pdf.add(space: 12)
    }
    
    /// Exports the signature as a `PDFGroup`, including the prefix ("X"), the name of the signee, the date, as well as the signature image.
    private func addRenderedSignature(_ signatureConfig: ConsentDocument.SignatureConfig) {
        let storage = consentDocument.value(for: signatureConfig)
        let personName = storage.name.formatted(.name(style: .long))
        let group = consentCard()
        #if !os(macOS)
        if storage.size.width > 0, storage.size.height > 0, !storage.signature.strokes.isEmpty {
            let scale = min(1, 60 / storage.size.height, 300 / storage.size.width)
            group.add(.left, image: PDFImage(
                image: storage.signatureImage(size: storage.size),
                size: CGSize(width: storage.size.width * scale, height: storage.size.height * scale),
                options: []
            ))
        } else {
            group.add(space: 36)
        }
        let signaturePrefix = "X"
        #else
        group.add(space: 36)
        let signaturePrefix = "X " + storage.signature
        #endif
        group.set(font: config.fontSettings.signaturePrefixFont)
        group.add(.left, text: signaturePrefix)
        group.addLineSeparator(style: PDFLineStyle(color: .black))
        // Add person name and date as the caption below the signature line
        // Sadly a quite complex table is required to have the caption within one line
        let table = PDFTable(rows: 1, columns: 2)
        table.widths = [0.5, 0.5] // Two equal-width columns for left and right alignment
        table.margin = .zero
        table.padding = 0
        table.style.outline = .none
        let cellStyle = PDFTableCellStyle(
            colors: (Color.clear, Color.black),
            borders: .none,
            font: config.fontSettings.signatureCaptionFont
        )
        // Add person name to the left cell
        table[0, 0] = PDFTableCell(
            content: try? .init(content: personName),
            alignment: .left,
            style: cellStyle
        )
        // Add formatted date to the right cell
        table[0, 1] = PDFTableCell(
            content: try? .init(content: consentDocument.signatureDate ?? ""),
            alignment: .right,
            style: cellStyle
        )
        group.add(.left, table: table)
        pdf.add(group: group)
        pdf.add(space: 12)
    }

    /// Corner-anchored geometry keeps the radius fixed as the card fits its content.
    private func consentCard() -> PDFGroup {
        let path = PDFBezierPath(ref: CGRect(x: 0, y: 0, width: 100, height: 100))
        path.move(to: .init(position: CGPoint(x: 8, y: 0), anchor: .topLeft))
        path.addLine(to: .init(position: CGPoint(x: 92, y: 0), anchor: .topRight))
        path.addQuadCurve(
            to: .init(position: CGPoint(x: 100, y: 8), anchor: .topRight),
            controlPoint: .init(position: CGPoint(x: 100, y: 0), anchor: .topRight)
        )
        path.addLine(to: .init(position: CGPoint(x: 100, y: 92), anchor: .bottomRight))
        path.addQuadCurve(
            to: .init(position: CGPoint(x: 92, y: 100), anchor: .bottomRight),
            controlPoint: .init(position: CGPoint(x: 100, y: 100), anchor: .bottomRight)
        )
        path.addLine(to: .init(position: CGPoint(x: 8, y: 100), anchor: .bottomLeft))
        path.addQuadCurve(
            to: .init(position: CGPoint(x: 0, y: 92), anchor: .bottomLeft),
            controlPoint: .init(position: CGPoint(x: 0, y: 100), anchor: .bottomLeft)
        )
        path.addLine(to: .init(position: CGPoint(x: 0, y: 8), anchor: .topLeft))
        path.addQuadCurve(
            to: .init(position: CGPoint(x: 8, y: 0), anchor: .topLeft),
            controlPoint: .init(position: .zero, anchor: .topLeft)
        )
        path.close()
        return PDFGroup(
            allowsBreaks: false,
            backgroundShape: PDFDynamicGeometryShape(path: path, fillColor: Color(white: 0.96, alpha: 1), stroke: .none),
            padding: EdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ConsentDocument.SignatureStorage {
    #if !os(macOS)
    @MainActor
    fileprivate func signatureImage(size: CGSize) -> UIImage {
        let scale: CGFloat
        #if os(iOS)
        scale = UIScreen.main.scale
        #else
        scale = 3 // retina scale is default
        #endif
        // As the `PKDrawing.image()` function automatically converts the ink color dependent on the used color scheme (light or dark mode),
        // force the tint color used in the `UIImage` to `black`.
        let image = signature.image(
            from: .init(x: 0, y: 0, width: size.width, height: size.height),
            scale: scale
        )
        return image
            .withRenderingMode(.alwaysTemplate)
            .withTintColor(.black)
    }
    #endif
}


extension Sequence where Element == MarkdownDocument.CustomElement.Content {
    var plainTextContents: String {
        reduce(into: "") { result, element in
            switch element {
            case .text(let string):
                result.append("\n\(string)")
            case .element(let customElement):
                result.append("\n\(customElement.content.plainTextContents)")
            }
        }
        .trimmingWhitespace()
    }
}
