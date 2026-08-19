//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension MarkdownDocument {
    /// A key-value mapping containing the metadata parsed from a consent form.
    public struct Metadata: Hashable, Sendable {
        public typealias Storage = [String: String]
        
        private let storage: Storage
        
        /// Creates a new, empty `Metadata` object.
        public init() {
            storage = .init()
        }
        
        /// Creates a `Metadata` object from the specified key-value pairs
        public init(_ values: [String: String]) {
            self.storage = values
        }
        
        /// Parses only  the frontmatter of a Markdown `String`.
        public init(parsing markdown: String) throws(ParseError) {
            var parser = Parser(input: markdown, customElementNames: [])
            self.init(try parser.parseFrontmatter())
        }
        
        /// Fetches the metadata value associated with the specified key.
        public subscript(key: String) -> String? {
            storage[key]
        }
    }
}


extension MarkdownDocument.Metadata {
    /// The document's title, if present in the metadata
    public var title: String? {
        self["title"]
    }
    
    /// The document's version, if present in the metadata
    @available(iOS 18, macOS 15, watchOS 11, *)
    public var version: Version? {
        self["version"].flatMap { Version($0) }
    }
}


extension MarkdownDocument.Metadata: Collection {
    public var startIndex: Storage.Index {
        storage.startIndex
    }
    
    public var endIndex: Storage.Index {
        storage.endIndex
    }
    
    public func index(after idx: Storage.Index) -> Storage.Index {
        storage.index(after: idx)
    }
    
    public subscript(position: Storage.Index) -> Storage.Element  {
        storage[position]
    }
}


extension MarkdownDocument.Metadata: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, String)...) {
        self.init(Dictionary(uniqueKeysWithValues: elements))
    }
}


extension MarkdownDocument.Metadata: Codable {
    public init(from decoder: any Decoder) throws {
        storage = try Storage(from: decoder)
    }
    
    public func encode(to encoder: any Encoder) throws {
        try storage.encode(to: encoder)
    }
}
