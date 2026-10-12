//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
import Testing


struct ConsentDocumentFormatTests {
    @Test(arguments: [
        "<toggle id=a expected-value=maybe>Agree</toggle>",
        "<toggle id=a>Unclosed",
        "<signature id=a>Ignored</signature>",
        "<signature id=a />\n<signature id=a />",
        "<signature id=a id=b />",
        "<select id=a><option id=x>One</option><option id=x>Two</option></select>",
        "<select id=a expected-value=missing><option id=x>One</option></select>",
        "<select id=a />",
        "<toggle id=a><footnote><footnote>Nested</footnote></footnote></toggle>"
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
}
