//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension ConsentDocumentFormat {
    /// A validated Boolean control. An absent expected value permits either response.
    public struct Toggle: ConsentDocumentElement, Hashable {
        public static var elementName: String { Kind.toggle.rawValue }
        public let id: String
        public let text: MarkdownDocument
        public let initialValue: Bool
        public let expectedValue: Bool? // swiftlint:disable:this discouraged_optional_boolean

        public init(parsing element: MarkdownDocument.CustomElement) throws {
            try element.validateConsentAttributes(kind: .toggle, allowed: [.id, .initialValue, .expectedValue])
            id = try element.consentIdentifier()
            guard !element.content.isEmpty else { throw ValidationError.invalidControl(element.name) }
            text = try element.consentLabel()
            initialValue = try element.consentBoolean(.initialValue) ?? false
            expectedValue = try element.consentBoolean(.expectedValue)
        }
    }

    /// A validated selection with locally unique options and checked option references.
    public struct Selection: ConsentDocumentElement, Hashable {
        public enum ExpectedSelection: Hashable, Sendable {
            case option(id: String)
            case anything(allowEmptySelection: Bool)
        }

        public static var elementName: String { Kind.select.rawValue }
        public static let emptySelection = ""
        public let id: String
        public let text: MarkdownDocument
        public let options: [SelectionOption]
        public let initialValue: String
        public let expectedSelection: ExpectedSelection

        public init(parsing element: MarkdownDocument.CustomElement) throws {
            try element.validateConsentAttributes(kind: .select, allowed: [.id, .initialValue, .expectedValue])
            id = try element.consentIdentifier()
            var options: [SelectionOption] = []
            var identifiers: Set<String> = []
            var label = element
            label.content = try element.content.filter { child in
                guard case .element(let child) = child, child.name == Kind.option.rawValue else {
                    return true
                }
                let option = try SelectionOption(parsing: child)
                guard identifiers.insert(option.id).inserted else { throw ValidationError.duplicateIdentifier(option.id) }
                options.append(option)
                return false
            }
            guard !options.isEmpty else { throw ValidationError.invalidControl(element.name) }
            self.options = options
            text = try label.consentLabel()
            initialValue = element[consentAttribute: .initialValue] ?? Self.emptySelection
            guard initialValue.isEmpty || identifiers.contains(initialValue) else { throw ValidationError.invalidControl(element.name) }
            switch element[consentAttribute: .expectedValue] {
            case nil: expectedSelection = .anything(allowEmptySelection: true)
            case "*": expectedSelection = .anything(allowEmptySelection: false)
            case .some(let id):
                guard identifiers.contains(id) else { throw ValidationError.invalidControl(element.name) }
                expectedSelection = .option(id: id)
            }
        }
    }

    /// An option within a selection; its identity is scoped to that selection.
    public struct SelectionOption: Hashable, Sendable {
        public let id: String
        public let title: String

        public init(parsing element: MarkdownDocument.CustomElement) throws {
            try element.validateConsentAttributes(kind: .option, allowed: [.id])
            id = try element.consentIdentifier()
            guard element.content.count == 1, case .text(let title) = element.content.first,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.invalidControl(element.name)
            }
            self.title = title
        }
    }

    /// A signature field's definition, independent of the platform's signature representation.
    public struct Signature: ConsentDocumentElement, Hashable {
        public static var elementName: String { Kind.signature.rawValue }
        public let id: String

        public init(parsing element: MarkdownDocument.CustomElement) throws {
            try element.validateConsentAttributes(kind: .signature, allowed: [.id])
            id = try element.consentIdentifier()
            guard element.content.isEmpty else { throw ValidationError.invalidControl(element.name) }
        }
    }
}
