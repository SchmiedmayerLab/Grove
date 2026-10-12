//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveConsent
import PDFKit
import SwiftUI
import Testing
#if canImport(UIKit)
import PencilKit
#endif


struct ConsentMarkdownTests {
    @Test
    @MainActor
    func retainsDuplicateIdentifierError() {
        #expect {
            try ConsentDocument(markdown: "<signature id=participant />\n<signature id=participant />")
        } throws: { error in
            guard case ConsentDocument.LoadError.duplicateCustomElementId("participant") = error else {
                return false
            }
            return true
        }
    }

    @Test
    @MainActor
    func sharedControlsInitializeResponsesAndCheckCompletion() throws {
        let document = try ConsentDocument(markdown: """
            <toggle id=agree expected-value=true>Agree</toggle>
            <select id=choice expected-value="*"><option id=yes>Yes</option></select>
            """)
        guard case .toggle(let toggle) = document.sections[0], case .select(let selection) = document.sections[1] else {
            Issue.record("Expected shared controls")
            return
        }
        #expect(document.userResponses.toggles["agree"] == false)
        #expect(document.userResponses.selects["choice"]?.isEmpty == true)
        #expect(document.completionState == .incomplete(firstIncompleteId: "agree"))
        document.binding(for: toggle).wrappedValue = true
        #expect(document.completionState == .incomplete(firstIncompleteId: "choice"))
        document.binding(for: selection).wrappedValue = "unknown"
        #expect(document.completionState == .incomplete(firstIncompleteId: "choice"))
        document.binding(for: selection).wrappedValue = "yes"
        #expect(document.completionState == .complete)
    }

    #if canImport(UIKit)
    @Test
    @MainActor
    func includesDrawnSignatureInCard() throws {
        let document = try ConsentDocument(markdown: "<signature id=participant />")
        let config = ConsentDocument.SignatureConfig(id: "participant")
        let binding = document.binding(for: config)
        binding.wrappedValue.name = .init(givenName: "Example", familyName: "Participant")
        binding.wrappedValue.size = CGSize(width: 300, height: 100)
        let unsigned = try document.export(using: .init(includingTimestamp: false))
        let points = [CGPoint(x: 20, y: 70), CGPoint(x: 100, y: 20), CGPoint(x: 180, y: 70)].enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: Double(index) * 0.1,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))
        )
        binding.wrappedValue.signature = PKDrawing(strokes: [stroke])
        let signed = try document.export(using: .init(includingTimestamp: false))
        #expect(signed.pdf.pageCount == 1)
        #expect(signed.pdf.string?.contains("Example Participant") == true)
        #expect(signed.userResponses.signatures["participant"]?.signature.strokes.count == 1)
        let unsignedPage = try #require(unsigned.pdf.page(at: 0))
        let signedPage = try #require(signed.pdf.page(at: 0))
        let size = CGSize(width: 612, height: 792)
        #expect(unsignedPage.thumbnail(of: size, for: .mediaBox).pngData() != signedPage.thumbnail(of: size, for: .mediaBox).pngData())
    }
    #endif

    @Test
    @MainActor
    func rendersFootnotesAsSecondaryText() throws {
        let document = try ConsentDocument(markdown: """
            <toggle id=agree>
            **I agree** to participate.
            <footnote>Ask [questions](mailto:study@example.com) before signing.</footnote>
            </toggle>
            """)
        guard case .toggle(let toggle) = try #require(document.sections.first) else {
            Issue.record("Expected a toggle")
            return
        }
        let label = try ConsentMarkdownPDF(font: .systemFont(ofSize: 11)).label(toggle.text)
        let body = (label.string as NSString).range(of: "I agree")
        let footnote = (label.string as NSString).range(of: "questions")
        #expect((label.attribute(.font, at: body.location, effectiveRange: nil) as? UINSFont)?.pointSize == 11)
        let font = try #require(label.attribute(.font, at: footnote.location, effectiveRange: nil) as? UINSFont)
        #expect(abs(font.pointSize - 9.02) < 0.01)
        #expect(label.attribute(.foregroundColor, at: footnote.location, effectiveRange: nil) != nil)
        #expect(label.attribute(.link, at: footnote.location, effectiveRange: nil) as? URL == URL(string: "mailto:study@example.com"))
        #expect(!label.string.contains("<footnote>"))
    }

    @Test(arguments: [ConsentDocument.ExportConfiguration.PaperSize.usLetter, .dinA4])
    @MainActor
    func preservesCardsAcrossPageBoundaries(paperSize: ConsentDocument.ExportConfiguration.PaperSize) throws {
        let markdown = (0..<30).map { index in
            """
            ## Section \(index)

            Participation is voluntary. You can ask questions before deciding.

            <toggle id=choice\(index) initial-value=true>
            Response \(index).
            <footnote>Supporting information \(index).</footnote>
            </toggle>
            """
        }
        .joined(separator: "\n\n")
        let document = try ConsentDocument(markdown: markdown)
        let exported = try document.export(using: .init(paperSize: paperSize, includingTimestamp: false))
        #expect(exported.pdf.pageCount > 1)
        let text = try #require(exported.pdf.string)
        for index in 0..<30 {
            #expect(text.components(separatedBy: "Response \(index).").count == 2)
            #expect(text.components(separatedBy: "Supporting information \(index).").count == 2)
            #expect(exported.userResponses.toggles["choice\(index)"] == true)
        }
        for index in 0..<exported.pdf.pageCount {
            let page = try #require(exported.pdf.page(at: index))
            let content = try #require(page.selection(for: page.bounds(for: .mediaBox)))
            #expect(page.bounds(for: .mediaBox).contains(content.bounds(for: page)))
        }
    }

    @Test
    @MainActor
    func exportsStructuredMarkdownAndFieldLabels() throws {
        let document = try ConsentDocument(markdown: """
            # Your Participation

            Participation is **voluntary** and *confidential*.

            - First item
            - Second item

            1. Read the document
            2. Ask questions

            > You may withdraw.

            [Contact us](mailto:study@example.com).

            | Measure | Frequency |
            | --- | --- |
            | Heart rate | Daily |

            ```
            literal example
            ```

            <toggle id=agree initial-value=true expected-value=true>
            **I agree** to participate.
            <footnote>Read the *complete* information.</footnote>
            </toggle>
            <select id=contact initial-value=email>
            Preferred **contact**.
            <option id=email>**Email**</option>
            </select>
            """)
        let exported = try document.export(using: .init(includingTimestamp: false))
        let text = try #require(exported.pdf.string)
        for expected in [
            "Your Participation", "voluntary", "First item", "Second item", "withdraw", "Heart rate", "Daily",
            "literal example", "I agree", "complete", "Email"
        ] {
            #expect(text.contains(expected))
        }
        #expect(!text.contains("**"))
        #expect(!text.contains("# Your"))
        #expect(!text.contains("<footnote>"))
        #expect(exported.userResponses.toggles["agree"] == true)
        #expect(exported.userResponses.selects["contact"] == "email")
    }

    @Test(arguments: [
        "![image](https://example.com/image.png)", "<div>HTML</div>", "Text <b>HTML</b>",
        "[Link](javascript:alert(1))", "![image][ref]\n\n[ref]: image.png"
    ])
    @MainActor
    func rejectsContentThatCannotBePreserved(markdown: String) {
        #expect(throws: ConsentDocument.LoadError.self) { try ConsentDocument(markdown: markdown) }
    }

    @Test
    @MainActor
    func preservesInlineStylesAndLinkTargets() throws {
        let renderer = ConsentMarkdownPDF(font: .systemFont(ofSize: 12))
        let result = try renderer.label("**Bold**, *emphasis*, ~~removed~~ and [contact](mailto:study@example.com)")
        #expect(result.string == "Bold, emphasis, removed and contact")
        let range = (result.string as NSString).range(of: "contact")
        #expect(result.attribute(.link, at: range.location, effectiveRange: nil) as? URL == URL(string: "mailto:study@example.com"))
        let removed = (result.string as NSString).range(of: "removed")
        #expect(result.attribute(.strikethroughStyle, at: removed.location, effectiveRange: nil) as? Int == 1)
    }

    @Test
    @MainActor
    func preservesParagraphsWithinOneListItem() throws {
        let renderer = ConsentMarkdownPDF(font: .systemFont(ofSize: 12))
        let result = try renderer.label("1. First paragraph\n\n   Continued paragraph\n\n2. Second item")
        #expect(result.string == "1. First paragraph\n\n    Continued paragraph\n\n2. Second item")
        // Unstyled paragraph separators can collapse to the PDF renderer's default font size.
        for (offset, character) in result.string.utf16.enumerated() where character == 10 {
            #expect(result.attribute(.font, at: offset, effectiveRange: nil) != nil)
        }
    }
}
