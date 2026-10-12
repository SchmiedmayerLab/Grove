//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension MarkdownDocument.CustomElement {
    enum ConsentAttribute: String {
        case id
        case initialValue = "initial-value"
        case expectedValue = "expected-value"
    }

    func consentIdentifier() throws -> String {
        guard let id = self[consentAttribute: .id], !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(attributes.map(\.name)).count == attributes.count else {
            throw ConsentDocumentFormat.ValidationError.invalidControl(name)
        }
        return id
    }

    func validateConsentAttributes(kind: ConsentDocumentFormat.Kind, allowed: Set<ConsentAttribute>) throws {
        guard name == kind.rawValue, Set(attributes.map(\.name)).count == attributes.count,
              attributes.allSatisfy({ ConsentAttribute(rawValue: $0.name).map(allowed.contains) ?? false }) else {
            throw ConsentDocumentFormat.ValidationError.invalidControl(name)
        }
    }

    // swiftlint:disable:next discouraged_optional_boolean
    func consentBoolean(_ attribute: ConsentAttribute) throws -> Bool? {
        guard let raw = self[consentAttribute: attribute] else {
            return nil
        }
        guard let value = Bool(raw) else { throw ConsentDocumentFormat.ValidationError.invalidControl(name) }
        return value
    }

    func consentLabel() throws -> MarkdownDocument {
        let blocks = try content.map { child -> MarkdownDocument.Block in
            switch child {
            case .text(let text): return .markdown(id: nil, rawContents: text)
            case .element(let footnote):
                try footnote.validateConsentAttributes(kind: .footnote, allowed: [])
                guard !footnote.content.isEmpty,
                      footnote.content.allSatisfy({ if case .text = $0 { true } else { false } }) else {
                    throw ConsentDocumentFormat.ValidationError.invalidControl(footnote.name)
                }
                return .customElement(footnote)
            }
        }
        return MarkdownDocument(metadata: [:], blocks: blocks)
    }

    subscript(consentAttribute attribute: ConsentAttribute) -> String? {
        self[attribute: attribute.rawValue]
    }
}
