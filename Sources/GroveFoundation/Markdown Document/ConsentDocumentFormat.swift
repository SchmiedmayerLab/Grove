//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Validates the structure of a Markdown consent document without UI or participant state.
///
/// Clients and servers can use this same format check before displaying or publishing a document.
/// It validates interactive fields, not consent approval, response completeness, or external assets.
public enum ConsentDocumentFormat {
    public enum ValidationError: Error, Equatable {
        case invalidControl(String)
    }

    /// Parses complete input and validates Grove's toggle, selection, signature and footnote syntax.
    /// Ordinary Markdown remains unchanged, including literal control examples in fenced code blocks.
    public static func parse(_ markdown: String) throws -> MarkdownDocument {
        let document = try MarkdownDocument(
            processing: markdown,
            customElementNames: ["toggle", "select", "signature", "option", "footnote"],
            requiresCompleteInput: true
        )
        var identifiers: Set<String> = []
        for block in document.blocks {
            guard case .customElement(let element) = block else { continue }
            let id = try identifier(element)
            guard identifiers.insert(id).inserted else { throw ValidationError.invalidControl(id) }
            try validate(element)
        }
        return document
    }

    private static func validate(_ element: MarkdownDocument.CustomElement) throws {
        switch element.name {
        case "toggle":
            try attributes(element, allowed: ["id", "initial-value", "expected-value"])
            for name in ["initial-value", "expected-value"] {
                if let value = element[attribute: name], Bool(value) == nil {
                    throw ValidationError.invalidControl(element.name)
                }
            }
            guard !element.content.isEmpty else { throw ValidationError.invalidControl(element.name) }
            try label(element.content)
        case "select":
            try selection(element)
        case "signature":
            try attributes(element, allowed: ["id"])
            guard element.content.isEmpty else { throw ValidationError.invalidControl(element.name) }
        default:
            throw ValidationError.invalidControl(element.name)
        }
    }

    private static func selection(_ element: MarkdownDocument.CustomElement) throws {
        try attributes(element, allowed: ["id", "initial-value", "expected-value"])
        var options: Set<String> = []
        for child in element.content {
            if case .element(let option) = child, option.name == "option" {
                try attributes(option, allowed: ["id"])
                let id = try identifier(option)
                guard options.insert(id).inserted, option.content.count == 1,
                      case .text(let title) = option.content.first,
                      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ValidationError.invalidControl(element.name)
                }
            } else {
                try label([child])
            }
        }
        guard !options.isEmpty else { throw ValidationError.invalidControl(element.name) }
        if let initial = element[attribute: "initial-value"], !initial.isEmpty, !options.contains(initial) {
            throw ValidationError.invalidControl(element.name)
        }
        if let expected = element[attribute: "expected-value"], expected != "*", !options.contains(expected) {
            throw ValidationError.invalidControl(element.name)
        }
    }

    private static func label(_ contents: [MarkdownDocument.CustomElement.Content]) throws {
        for content in contents {
            guard case .element(let element) = content else { continue }
            guard element.name == "footnote", !element.content.isEmpty,
                  element.content.allSatisfy({ if case .text = $0 { true } else { false } }) else {
                throw ValidationError.invalidControl(element.name)
            }
            try attributes(element, allowed: [])
        }
    }

    private static func identifier(_ element: MarkdownDocument.CustomElement) throws -> String {
        guard let id = element[attribute: "id"], !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalidControl(element.name)
        }
        return id
    }

    private static func attributes(_ element: MarkdownDocument.CustomElement, allowed: Set<String>) throws {
        let names = element.attributes.map(\.name)
        guard Set(names).count == names.count, names.allSatisfy(allowed.contains) else {
            throw ValidationError.invalidControl(element.name)
        }
    }
}
