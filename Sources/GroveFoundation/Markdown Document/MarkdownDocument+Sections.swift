//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension MarkdownDocument {
    /// A unit of content within a ``MarkdownDocument``.
    ///
    /// See ``MarkdownDocument`` for more information about blocks.
    ///
    /// ## Topics
    ///
    /// ### Enumeration Cases
    /// - ``markdown(id:rawContents:)``
    /// - ``customElement(_:)``
    ///
    /// ### Instance Properties
    /// - ``id``
    /// - ``isMarkdown``
    /// - ``isCustomElement``
    /// - ``customElement``
    public enum Block: Hashable, Sendable {
        /// A block consisting of Markdown text
        case markdown(id: String?, rawContents: String)
        /// A block consisting of a parsed custom element.
        case customElement(CustomElement)
        
        /// The block's stable identifier, if available.
        public var id: String? {
            switch self {
            case .markdown(let id, _):
                id
            case .customElement(let element):
                element[attribute: "id"]
            }
        }
        
        /// Whether this is a Markdown block.
        public var isMarkdown: Bool {
            switch self {
            case .markdown: true
            case .customElement: false
            }
        }
        
        /// Whether this is a ``MarkdownDocument/CustomElement`` block.
        public var isCustomElement: Bool {
            switch self {
            case .customElement: true
            case .markdown: false
            }
        }
        
        /// The block's ``MarkdownDocument/CustomElement``, if applicable.
        public var customElement: CustomElement? {
            switch self {
            case .customElement(let element):
                element
            case .markdown:
                nil
            }
        }
    }
    
    
    /// A custom element that was parsed from a Markdown string.
    public struct CustomElement: Hashable, Sendable {
        /// The element's content
        public indirect enum Content: Hashable, Sendable {
            /// A piece of plain-text content
            case text(String)
            /// Another element.
            case element(CustomElement)
        }
        
        /// An attribute within a parsed element.
        ///
        /// Attributes are modeled after HTML attributes, and are simple key-value pairs of the form `name=value`.
        public struct ParsedAttribute: Hashable, Sendable {
            /// The attribute's name
            public let name: String
            /// The attribute's value
            public let value: String
        }
        
        /// The element name.
        public internal(set) var name: String
        /// The element's attributes.
        public internal(set) var attributes: [ParsedAttribute] = []
        /// The element's content.
        public internal(set) var content: [Content] = []
        /// The unprocessed raw text from which this element was parsed.
        public internal(set) var raw: String
        
        /// Reads the value of the first attribute with the specified name, if available.
        @inlinable
        public subscript(attribute name: String) -> String? {
            attributes.first { $0.name == name }?.value
        }
    }
}
