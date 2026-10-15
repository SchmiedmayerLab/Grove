//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveConsent
import GroveFoundation
import Testing


struct ConsentDocumentFormatTests {
    @Test(arguments: ["```", "~~~~"])
    func preservesFencedExamplesInsideLabels(fence: String) throws {
        let source = "<toggle id=agree>\nExample:\n\(fence)html\n<signature id=example />\n</toggle>\n\(fence)\n</toggle>"
        let parsed = try ConsentDocumentFormat.decode(source)
        #expect(parsed.sections.count == 1)
        guard case .toggle(let toggle) = parsed.sections.first else {
            Issue.record("Missing toggle")
            return
        }
        let text = toggle.text.blocks.compactMap { block -> String? in
            if case .markdown(_, let raw) = block { raw } else { nil }
        }
        .joined()
        #expect(text.contains("<signature id=example />"))
        #expect(text.contains("</toggle>"))
    }

    @Test(arguments: [
        "<toggle id=a expected-value=maybe>Agree</toggle>",
        "<toggle id=a>Unclosed",
        "<signature id=a>Ignored</signature>",
        "<signature id=a />\n<signature id=a />",
        "<signature id=a id=b />",
        "<select id=a><option id=x>One</option><option id=x>Two</option></select>",
        "<select id=a expected-value=missing><option id=x>One</option></select>",
        "<select id=a />",
        "<toggle id=a><footnote><footnote>Nested</footnote></footnote></toggle>",
        "<toggle id=a initial-value=maybe>Agree</toggle>",
        "<toggle id=a unexpected=true>Agree</toggle>",
        "<toggle id=a><unknown>Hidden</unknown></toggle>",
        "<select id=a initial-value=missing><option id=x>One</option></select>",
        "<select id=a><option id=\"\">Empty</option></select>",
        "<select id=a><option id=x><signature id=hidden /></option></select>",
        "<option id=outside>Outside a selection</option>",
        "<footnote>Outside a label</footnote>"
    ])
    func rejectsInvalidControls(markdown: String) {
        #expect(throws: (any Error).self) { try ConsentDocumentFormat.parse(markdown) }
    }

    @Test
    func preservesFencedExamplesWithoutCreatingControls() throws {
        let markdown = "```html\n<signature id=example />\n# Literal heading\n```\n\n<signature id=real />"
        let document = try ConsentDocumentFormat.parse(markdown)
        let controls = document.blocks.compactMap { block -> String? in
            if case .customElement(let element) = block { element[attribute: "id"] } else { nil }
        }
        #expect(controls == ["real"])
        guard case .markdown(_, let example) = document.blocks.first else {
            Issue.record("Missing literal example")
            return
        }
        #expect(example.contains("<signature id=example />"))
        #expect(example.contains("# Literal heading"))
    }

    @Test
    func supportsMetadataAndAllControls() throws {
        let document = try ConsentDocumentFormat.parse("""
            ---
            title: Study Consent
            version: 1.0.0
            ---
            # Participation
            <toggle id=agree expected-value=true>**I agree.**<footnote>Optional *explanation*.</footnote></toggle>
            <select id=choice initial-value=yes expected-value="*">
            Choose one.
            <option id=yes>Yes</option>
            <option id=no>No</option>
            </select>
            <signature id=participant />
            """)
        #expect(document.metadata.title == "Study Consent")
        #expect(document.blocks.count == 4)
    }

    @Test
    func decodesTypedValuesWithoutReparsing() throws {
        let document = try ConsentDocumentFormat.decode("""
            <toggle id=agree initial-value=true expected-value=false>Agree<footnote>Details</footnote></toggle>
            <select id=choice initial-value=yes expected-value="*"><option id=yes>Yes</option></select>
            <signature id=participant />
            """)
        guard case .toggle(let toggle) = document.sections[0],
              case .select(let selection) = document.sections[1],
              case .signature(let signature) = document.sections[2] else {
            Issue.record("Expected typed controls in document order")
            return
        }
        #expect(toggle.id == "agree")
        #expect(toggle.initialValue)
        #expect(toggle.expectedValue == false)
        #expect(toggle.text.blocks.count == 2)
        #expect(selection.initialValue == "yes")
        #expect(selection.expectedSelection == .anything(allowEmptySelection: false))
        #expect(selection.options.map(\.title) == ["Yes"])
        #expect(signature.id == "participant")
    }

    @Test
    func optionIdentifiersAreScopedToTheirSelection() throws {
        _ = try ConsentDocumentFormat.decode("""
            <select id=first><option id=yes>Yes</option></select>
            <select id=second><option id=yes>Yes</option></select>
            <signature id=yes />
            """)
    }

    @Test
    func directElementConstructionStillValidates() throws {
        let markdown = try MarkdownDocument(processing: "<toggle id=a expected-value=maybe>Agree</toggle>", customElementNames: ["toggle"])
        guard case .customElement(let element) = markdown.blocks.first else {
            Issue.record("Expected parsed toggle")
            return
        }
        #expect(throws: ConsentDocumentFormat.ValidationError.invalidControl("toggle")) {
            try ConsentDocumentFormat.Toggle(parsing: element)
        }
        #expect(throws: ConsentDocumentFormat.ValidationError.invalidControl("toggle")) {
            try ConsentDocumentFormat.Signature(parsing: element)
        }
    }
}
