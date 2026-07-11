//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziFoundation

@available(iOS 18, macOS 15, watchOS 11, *)
extension ConsentDocument.Section {
    enum ConstructSectionError: Error {
        case missingAttribute(String)
        case missingField(String)
        case unexpectedElement(String)
        case other(String)
    }
    
    /// The HTML tag names that are allowed to appear in a `toggle` or `select` element's children that should be used to build up the element's text content.
    private static let allowedNestedTextContentTagNames: Set = ["footnote"]
    
    static func toggle(_ element: MarkdownDocument.CustomElement, in document: MarkdownDocument) throws(ConstructSectionError) -> Self {
        guard let id = element[attribute: "id"], !id.isEmpty else {
            throw .missingAttribute("id")
        }
        guard !element.content.isEmpty else {
            throw .missingField("prompt")
        }
        let defaultValue = element[attribute: "initial-value"].flatMap { Bool($0) } ?? false
        let expectedValue = element[attribute: "expected-value"].flatMap { Bool($0) }
        return .toggle(.init(
            id: id,
            text: MarkdownDocument(
                blocks: element.content,
                allowedNestedCustomElements: allowedNestedTextContentTagNames,
                baseUrl: document.baseUrl
            ),
            initialValue: defaultValue,
            expectedValue: expectedValue
        ))
    }
    
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func select(_ element: MarkdownDocument.CustomElement, in document: MarkdownDocument) throws(ConstructSectionError) -> Self {
        guard let id = element[attribute: "id"], !id.isEmpty else {
            throw .missingAttribute("id")
        }
        var options: [ConsentDocument.SelectionOption] = []
        for thing in element.content {
            switch thing {
            case .text:
                break
            case .element(let element):
                switch element.name {
                case "option":
                    guard let optionId = element[attribute: "id"], !id.isEmpty else {
                        throw .missingAttribute("option.id")
                    }
                    guard case .text(let prompt) = element.content.first else {
                        throw .missingField("option.content")
                    }
                    options.append(.init(id: optionId, title: prompt))
                default:
                    if allowedNestedTextContentTagNames.contains(element.name) {
                        break
                    } else {
                        throw .unexpectedElement(element.name)
                    }
                }
            }
        }
        let initialValue = element[attribute: "initial-value"] ?? ConsentDocument.SelectConfig.emptySelection
        guard initialValue.isEmpty || options.contains(where: { $0.id == initialValue }) else {
            throw .other("initial value references nonexisting option id '\(initialValue)'")
        }
        let expectedSelection = try { () throws (ConstructSectionError) -> ConsentDocument.SelectConfig.ExpectedSelection in
            let rawValue = element[attribute: "expected-value"]
            switch rawValue {
            case nil:
                return .anything(allowEmptySelection: true)
            case .some(""):
                throw .missingAttribute("expected-value")
            case .some("*"):
                return .anything(allowEmptySelection: false)
            case .some(let id):
                guard options.contains(where: { $0.id == id }) else {
                    throw .other("expected value references notexisting option id '\(id)'")
                }
                return .option(id: id)
            }
        }()
        return .select(.init(
            id: id,
            text: MarkdownDocument(
                blocks: element.content,
                allowedNestedCustomElements: allowedNestedTextContentTagNames,
                baseUrl: document.baseUrl
            ),
            options: options,
            initialValue: initialValue,
            expectedSelection: expectedSelection
        ))
    }
    
    static func signature(_ element: MarkdownDocument.CustomElement) throws(ConstructSectionError) -> Self {
        guard let id = element[attribute: "id"], !id.isEmpty else {
            throw .missingField("id")
        }
        return .signature(.init(id: id))
    }
}


extension MarkdownDocument {
    /// Creates a `MarkdownDocument` from the children of a `CustomElement`.
    ///
    /// - parameter children: The `MarkdownDocument.CustomElement.Content` children of the custom element
    /// - parameter allowedNestedCustomElements: The HTML tag names that are allowed to appear in `children`.
    ///     Any children whose tag names are not explicitly allowed will be skipped.
    /// - parameter baseUrl: The base URL of the resulting document.
    init(
        blocks children: some Sequence<MarkdownDocument.CustomElement.Content>,
        allowedNestedCustomElements: Set<String>,
        baseUrl: URL?
    ) {
        self.init(
            metadata: [:],
            blocks: children.compactMap { content in
                switch content {
                case .text(let text):
                    .markdown(id: nil, rawContents: text)
                case .element(let element):
                    if allowedNestedCustomElements.contains(element.name) {
                        .customElement(element)
                    } else {
                        nil
                    }
                }
            },
            baseUrl: baseUrl
        )
    }
}
