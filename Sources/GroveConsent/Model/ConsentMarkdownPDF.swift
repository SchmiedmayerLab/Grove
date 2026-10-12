//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import PDFKit
import TPPDF


/// Maps Foundation's typed Markdown presentation intents to PDF text and tables.
/// The PDF remains searchable text; it is not a screenshot of the consent view.
@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
struct ConsentMarkdownPDF {
    let font: UINSFont

    /// Keep supporting wording smaller without losing its Markdown emphasis or links.
    func label(_ document: MarkdownDocument) throws -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for block in document.blocks {
            let text: NSAttributedString
            switch block {
            case .markdown(_, let contents):
                text = try label(contents)
            case .customElement(let element):
                let footnote = ConsentMarkdownPDF(font: font.withSize(font.pointSize * 0.82))
                let contents = try NSMutableAttributedString(attributedString: footnote.label(element.content.plainTextContents))
                contents.addAttribute(.foregroundColor, value: Color(white: 0.35, alpha: 1), range: NSRange(location: 0, length: contents.length))
                text = contents
            }
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n\n", attributes: [.font: font.withSize(font.pointSize * 0.5)]))
            }
            result.append(text)
        }
        return result
    }

    // Keep table and paragraph emission in one ordered pass; never reorder document content.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func append(_ markdown: String, to pdf: TPPDF.PDFDocument) throws {
        let parsed = try ConsentMarkdown.parse(markdown)
        var currentTable: Int?
        var tableRows: [[NSAttributedString]] = []
        var currentRow: Int?
        var row: [NSAttributedString] = []
        var cell: NSMutableAttributedString?
        var currentCell: Int?
        var text = NSMutableAttributedString(string: "")
        var previousIntent: PresentationIntent?

        func flushTable() throws {
            if let cell { row.append(cell) }
            if !row.isEmpty { tableRows.append(row) }
            guard let columns = tableRows.first?.count, columns > 0 else {
                return
            }
            let table = PDFTable(rows: tableRows.count, columns: columns)
            table.style = PDFTableStyleDefaults.none
            table.padding = 4
            table.widths = Array(repeating: 1 / CGFloat(columns), count: columns)
            for (rowIndex, values) in tableRows.enumerated() {
                for (columnIndex, value) in values.enumerated() {
                    table[rowIndex, columnIndex] = PDFTableCell(content: try .init(content: value), alignment: .left)
                }
            }
            pdf.add(table: table)
            pdf.add(space: font.pointSize)
            tableRows = []
            row = []
            cell = nil
            currentRow = nil
            currentCell = nil
            currentTable = nil
        }

        for run in parsed.runs {
            let intent = run.presentationIntent
            let tableID = intent?.components.first { if case .table = $0.kind { true } else { false } }?.identity
            if let tableID {
                if text.length > 0 {
                    pdf.add(attributedTextObject: PDFAttributedText(text: text))
                    pdf.add(space: font.pointSize * 0.65)
                    text = NSMutableAttributedString(string: "")
                }
                if currentTable != nil, currentTable != tableID { try flushTable() }
                currentTable = tableID
                let rowID = intent?.components.first {
                    switch $0.kind {
                    case .tableRow, .tableHeaderRow: true
                    default: false
                    }
                }?.identity
                let cellID = intent?.components.first { if case .tableCell = $0.kind { true } else { false } }?.identity
                if currentCell != cellID {
                    if let cell { row.append(cell) }
                    if currentRow != rowID, !row.isEmpty {
                        tableRows.append(row)
                        row = []
                    }
                    cell = NSMutableAttributedString(string: "")
                }
                currentCell = cellID
                currentRow = rowID
                cell?.append(styled(String(parsed[run.range].characters), run: run))
            } else {
                if currentTable != nil { try flushTable() }
                if intent != previousIntent {
                    if text.length > 0 {
                        pdf.add(attributedTextObject: PDFAttributedText(text: text))
                        pdf.add(space: font.pointSize * 0.65)
                        text = NSMutableAttributedString(string: "")
                    }
                    text.append(NSAttributedString(string: prefix(for: intent, after: previousIntent), attributes: [.font: font]))
                }
                text.append(styled(String(parsed[run.range].characters), run: run))
            }
            previousIntent = intent
        }
        if currentTable != nil { try flushTable() }
        if text.length > 0 {
            pdf.add(attributedTextObject: PDFAttributedText(text: text))
            pdf.add(space: font.pointSize * 0.65)
        }
    }

    /// Labels use the same Markdown styling as the body, including their footnotes.
    func label(_ markdown: String) throws -> NSAttributedString {
        let parsed = try ConsentMarkdown.parse(markdown)
        let result = NSMutableAttributedString(string: "")
        var previousIntent: PresentationIntent?
        for run in parsed.runs {
            if run.presentationIntent != previousIntent {
                if result.length > 0 { result.append(NSAttributedString(string: "\n\n", attributes: [.font: font])) }
                result.append(NSAttributedString(string: prefix(for: run.presentationIntent, after: previousIntent), attributes: [.font: font]))
            }
            result.append(styled(String(parsed[run.range].characters), run: run))
            previousIntent = run.presentationIntent
        }
        return result
    }

    private func prefix(for intent: PresentationIntent?, after previous: PresentationIntent?) -> String {
        guard let components = intent?.components else {
            return ""
        }
        let lists = components.filter {
            switch $0.kind {
            case .orderedList, .unorderedList: true
            default: false
            }
        }
        guard let item = components.first(where: { if case .listItem = $0.kind { true } else { false } }),
              case .listItem(let ordinal) = item.kind else {
            return ""
        }
        let indent = String(repeating: "    ", count: max(0, lists.count - 1))
        // A second paragraph in one item is not another numbered item.
        if previous?.components.contains(where: { $0.identity == item.identity }) == true {
            return indent + "    "
        }
        if let list = lists.first, case .orderedList = list.kind {
            return "\(indent)\(ordinal). "
        }
        return indent + "• "
    }

    // Each branch maps one native Markdown intent to its PDF text attribute.
    // swiftlint:disable:next cyclomatic_complexity
    private func styled(_ text: String, run: AttributedString.Runs.Run) -> NSAttributedString {
        let inline = run.inlinePresentationIntent ?? []
        var size = font.pointSize
        var bold = inline.contains(.stronglyEmphasized)
        var code = inline.contains(.code)
        var quote = false
        for component in run.presentationIntent?.components ?? [] {
            switch component.kind {
            case .header(let level):
                size *= [1.65, 1.4, 1.2, 1.1, 1.05, 1.0][min(max(level - 1, 0), 5)]
                bold = true
            case .codeBlock: code = true
            case .blockQuote: quote = true
            case .tableHeaderRow: bold = true
            default: break
            }
        }
        var chosenFont = code ? UINSFont.monospacedSystemFont(ofSize: size, weight: .regular) : font.withSize(size)
        #if canImport(UIKit)
        var traits = chosenFont.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if inline.contains(.emphasized) { traits.insert(.traitItalic) }
        if let descriptor = chosenFont.fontDescriptor.withSymbolicTraits(traits) {
            chosenFont = UINSFont(descriptor: descriptor, size: size)
        }
        #else
        var traits = chosenFont.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if inline.contains(.emphasized) { traits.insert(.italic) }
        chosenFont = UINSFont(descriptor: chosenFont.fontDescriptor.withSymbolicTraits(traits), size: size) ?? chosenFont
        #endif
        var attributes: [NSAttributedString.Key: Any] = [.font: chosenFont]
        if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = run.link {
            attributes[.link] = link
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if quote {
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = size
            paragraph.headIndent = size
            attributes[.paragraphStyle] = paragraph
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}
