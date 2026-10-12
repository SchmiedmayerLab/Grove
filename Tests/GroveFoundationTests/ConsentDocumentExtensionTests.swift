//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
import Testing


struct ConsentDocumentExtensionTests {
    private struct Rating: ConsentDocumentElement {
        static let elementName = "rating"
        let id: String
        let maximum: Int

        init(parsing element: MarkdownDocument.CustomElement) throws {
            guard element.name == Self.elementName,
                  element.attributes.allSatisfy({ ["id", "maximum"].contains($0.name) }),
                  let id = element[attribute: "id"],
                  let maximum = element[attribute: "maximum"].flatMap(Int.init), maximum > 0,
                  element.content.isEmpty else {
                throw ConsentDocumentFormat.ValidationError.invalidControl(element.name)
            }
            self.id = id
            self.maximum = maximum
        }
    }

    private struct SignatureOverride: ConsentDocumentElement {
        static let elementName = "signature"
        let id = "ignored"
        init(parsing element: MarkdownDocument.CustomElement) {}
    }

    private struct ChangedIdentity: ConsentDocumentElement {
        static let elementName = "changed-identity"
        let id = "different"
        init(parsing element: MarkdownDocument.CustomElement) {}
    }

    @Test
    func extensionIsExplicitAndReturnsItsTypedValue() throws {
        let markdown = "<rating id=comfort maximum=5 />"
        #expect(throws: ConsentDocumentFormat.ValidationError.unsupportedElement("rating")) {
            try ConsentDocumentFormat.decode(markdown)
        }
        let document = try ConsentDocumentFormat.decode(markdown, additionalElements: [Rating.self])
        guard case .custom(let element) = document.sections.first else {
            Issue.record("Expected the registered control")
            return
        }
        let rating = try #require(element as? Rating)
        #expect(rating.id == "comfort")
        #expect(rating.maximum == 5)
        #expect(try ConsentDocumentFormat.parse(markdown, additionalElements: [Rating.self]).blocks.count == 1)
    }

    @Test(arguments: [
        "<rating id=comfort maximum=0 />",
        "<rating id=comfort maximum=5 unknown=true />",
        "<rating id=comfort maximum=5>Hidden wording</rating>",
        "<rating id=comfort maximum=5 maximum=6 />",
        "<rating id=\" \" maximum=5 />",
        "<rating maximum=5 />",
        "<toggle id=agree><rating id=nested maximum=5 /></toggle>"
    ])
    func customControlsDoNotBypassValidation(markdown: String) {
        #expect(throws: (any Error).self) {
            try ConsentDocumentFormat.decode(markdown, additionalElements: [Rating.self])
        }
    }

    @Test
    func identifiersAreUniqueAcrossBuiltInsAndExtensions() {
        #expect(throws: ConsentDocumentFormat.ValidationError.duplicateIdentifier("shared")) {
            try ConsentDocumentFormat.decode(
                "<signature id=shared />\n<rating id=shared maximum=5 />", additionalElements: [Rating.self]
            )
        }
    }

    @Test
    func cannotReplaceBuiltInsOrRegisterTwoHandlers() {
        #expect(throws: ConsentDocumentFormat.ValidationError.conflictingElementName("signature")) {
            try ConsentDocumentFormat.decode("", additionalElements: [SignatureOverride.self])
        }
        #expect(throws: ConsentDocumentFormat.ValidationError.conflictingElementName("rating")) {
            try ConsentDocumentFormat.decode("", additionalElements: [Rating.self, Rating.self])
        }
    }

    @Test
    func extensionCannotChangeTheParsedIdentity() {
        #expect(throws: ConsentDocumentFormat.ValidationError.invalidControl("changed-identity")) {
            try ConsentDocumentFormat.decode("<changed-identity id=original />", additionalElements: [ChangedIdentity.self])
        }
    }
}
