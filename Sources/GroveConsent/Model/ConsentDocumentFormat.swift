//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFoundation


/// A platform-independent consent control that validates its input during construction.
///
/// An implementation must reject unsupported attributes, children and values rather than discard them.
/// Supply additional types explicitly to ``ConsentDocumentFormat/decode(_:additionalElements:)``;
/// registration does not add rendering, participant-response validation or PDF support to GroveConsent.
///
/// ```swift
/// let document = try ConsentDocumentFormat.decode(markdown, additionalElements: [StudyRating.self])
/// ```
///
/// `StudyRating` implements this protocol and is returned as a typed value in the `.custom` section.
/// Extension types are trusted application code, never selected from document metadata.
public protocol ConsentDocumentElement: Sendable {
    /// The case-sensitive tag name used in Markdown.
    static var elementName: String { get }
    /// The control's document-wide identity, matching its nonempty `id` attribute.
    var id: String { get }
    /// Constructs a validated control or throws without accepting a partial representation.
    init(parsing element: MarkdownDocument.CustomElement) throws
}


/// Parses consent structure without UI or participant state.
public enum ConsentDocumentFormat {
    public enum ValidationError: Error, Equatable {
        case invalidControl(String)
        case duplicateIdentifier(String)
        case unsupportedElement(String)
        case conflictingElementName(String)
    }

    /// Validated content in document order. Custom elements require an explicit platform implementation.
    public enum Section: Sendable {
        case markdown(String)
        case toggle(Toggle)
        case select(Selection)
        case signature(Signature)
        case custom(any ConsentDocumentElement)
    }

    /// Original Markdown structure together with its validated, typed controls.
    public struct ParsedDocument: Sendable {
        public let markdownDocument: MarkdownDocument
        public let sections: [Section]
    }

    enum Kind: String {
        case toggle, select, signature, option, footnote
    }

    /// Validates the complete input and returns its Markdown representation.
    public static func parse(
        _ markdown: String,
        additionalElements: [any ConsentDocumentElement.Type] = []
    ) throws -> MarkdownDocument {
        try decode(markdown, additionalElements: additionalElements).markdownDocument
    }

    /// Parses once into typed controls. Unknown block-level tags and duplicate registrations are rejected.
    ///
    /// Additional types apply only to top-level controls and cannot replace built-ins, including
    /// the nested `option` and `footnote` elements. Each type owns validation of its complete subtree.
    /// Callers must use the same explicit set of extensions when publishing and consuming a document.
    public static func decode(
        _ markdown: String,
        additionalElements: [any ConsentDocumentElement.Type] = []
    ) throws -> ParsedDocument {
        var extensions: [String: any ConsentDocumentElement.Type] = [:]
        for type in additionalElements {
            let name = type.elementName
            guard Kind(rawValue: name) == nil, extensions[name] == nil else {
                throw ValidationError.conflictingElementName(name)
            }
            extensions[name] = type
        }
        // Capture every tag so an unregistered control cannot silently become ordinary Markdown.
        let document = try MarkdownDocument(processing: markdown, customElements: .all, requiresCompleteInput: true)
        var identifiers: Set<String> = []
        let sections = try document.blocks.map { block -> Section in
            switch block {
            case .markdown(_, let text): return .markdown(text)
            case .customElement(let element):
                let id = try element.consentIdentifier()
                guard identifiers.insert(id).inserted else { throw ValidationError.duplicateIdentifier(id) }
                return try section(for: element, additionalElements: extensions)
            }
        }
        return ParsedDocument(markdownDocument: document, sections: sections)
    }

    private static func section(
        for element: MarkdownDocument.CustomElement,
        additionalElements: [String: any ConsentDocumentElement.Type]
    ) throws -> Section {
        switch Kind(rawValue: element.name) {
        case .toggle: return .toggle(try Toggle(parsing: element))
        case .select: return .select(try Selection(parsing: element))
        case .signature: return .signature(try Signature(parsing: element))
        case .option, .footnote: throw ValidationError.unsupportedElement(element.name)
        case nil:
            guard let type = additionalElements[element.name] else { throw ValidationError.unsupportedElement(element.name) }
            let value = try type.init(parsing: element)
            guard value.id == element[consentAttribute: .id] else { throw ValidationError.invalidControl(element.name) }
            return .custom(value)
        }
    }
}
