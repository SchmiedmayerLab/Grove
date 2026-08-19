//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A Markdown document.
///
/// The ``MarkdownDocument`` struct is a lightweight data type representing a (potentially pre-processed) Markdown document,
/// consisting of optional metadata, and contents which are represented as a series of ``Block``s.
///
/// ### Metadata
///
/// When using any of the `processing:` initializers to create a ``MarkdownDocument`` (e.g.: ``init(processing:customElementNames:baseUrl:)-(String,_,_)``),
/// any frontmatter-style metadata entries at the very beginning of the input will be parsed into a ``Metadata-swift.struct`` object.
///
/// The frontmatter-style metadata takes the following format:
/// ```
/// ---
/// key1: value1
/// key2: value2
/// ---
/// ```
/// I.e., the metadata is a simple String-based key-value mapping, with one entry per line, that is enclosed within two `---` lines.
///
/// - Tip: If you just want to extract the metadata from a Markdown file and don't care about the rest of the document, you can use ``Metadata-swift.struct/init(parsing:)``.
///
/// ### Content Blocks
///
/// The ``blocks`` property stores the Markdown document's content, split up into a series of ``Block``s.
/// A block is either a section of Markdown-formatted text (``Block/markdown(id:rawContents:)``, or an extracted ``CustomElement`` (``Block/customElement(_:)``).
///
/// > Important: The ``MarkdownDocument`` does not perform any Markdown _parsing_;
///     it only performs _processing_ of the Markdown input, in the sense that it splits up the input text into a series of sections of Markdown text, and parses any custom tags that may be contained in the Markdown.
///
/// For example, creating a ``MarkdownDocument`` from the following Markdown input (which ostensibly consists of two "parts": a markdown part with two sections, and a custom element part with a single signature field):
/// ```markdown
/// # Study Consent Form
/// Welcome to our study. As part of your participation, you will need to fill out and sign this consent form.
///
/// ## Your rights
/// You have the right to revoke this consent at any time; if you wish to do so, contact us at studies@acme.org
///
/// <signature id=sig />
/// ```
/// would result in a ``MarkdownDocument`` consisting of a total of three blocks: two markdown blocks (one per section) and one custom element block for the signature.
///
/// ``Block``s can have an ``Block/id``, which is determined based on the block's contents:
/// - for markdown blocks, the block will have an `id` if the block's markdown text starts with a heading, in which case the `id` will be derived from the heading's text;
/// - for custom element components, the block's `id` will derived from the element's `id` attribute, if present.
///
/// ### Custom Elements
///
/// The ``MarkdownDocument`` supports the handling of custom elements embedded within the Markdown input.
/// This behaviour is opt-in, on a per-element-name basis: the parser will only process custom elements whose name
/// matches one of the `customElementNames` passed to the ``MarkdownDocument`` initializer.
/// Any eligible custom elements are parsed into ``Block/customElement(_:)`` blocks;
/// ineligible elements (i.e., those with names not listed in `customElementNames`) are treated as if they were normal Markdown text,
/// allowing a downstream Markdown parser to handle them instead.
///
/// Custom elements (which are in the parsing result represented by the ``CustomElement`` type) are written using a simple HTML-style syntax, consisting of the following components:
/// - name: the name of the HTML tag
/// - attributes: a list of string-based key-value pairs
/// - content: a list of ``CustomElement/Content-swift.enum`` values,
///     each of which is either raw text (which itself could possibly be markdown), or another, nested ``CustomElement``.
///
/// Some examples:
/// ```html
/// <toggle id=toggle-1 initial-value=false>
///     Do you agree to the terms stated above?
/// </toggle>
///
/// <select id=s1>
///     What's your preference for a nice vacation?
///     <option id=o1>Mountains</>
///     <option id=o2>Beach</option>
/// </select>
///
/// <signature id=s1 />
/// ```
///
/// The parser, while not being a fully fledged HTML parser, can handle parsing of the elements like shown above,
/// and also comments and some syntactic sugar like omitting the name in the closing tag (e.g., `</>`),
/// self-closing tags (e.g., `<signature />`), and omitting explicit quotes (`"`) for attribute values that are also valid identifiers
/// (eg: `id=consent-sig` instead of `id="consent-sig`; both of these will result in the same attribute value.
///
///
/// ## Topics
///
/// ### Initializers
/// - ``init(metadata:blocks:baseUrl:)``
/// - ``init(processing:customElementNames:baseUrl:)-(String,_,_)``
/// - ``init(processing:customElementNames:baseUrl:)-(Data,_,_)``
/// - ``init(contentsOf:customElementNames:baseUrl:)``
/// - ``ParseError``
///
/// ### Instance Properties
/// - ``metadata``
/// - ``blocks``
/// - ``baseUrl``
///
/// ### Supporting Types
/// - ``Metadata``
/// - ``Block``
public struct MarkdownDocument: Hashable, Sendable {
    /// The document's metadata.
    public var metadata: Metadata
    /// The document's content blocks.
    public var blocks: [Block]
    /// The `URL` that should be used when resolving relative links and references in the Markdown content.
    public var baseUrl: URL?
    
    /// Creates a new Markdown document.
    public init(metadata: Metadata, blocks: [Block], baseUrl: URL? = nil) {
        self.metadata = metadata
        self.blocks = blocks
        self.baseUrl = baseUrl
    }
    
    /// Creates a new Markdown document by processing a `String`.
    ///
    /// Note that thie doesn't perform any Markdown parsing on its own; rather, it splits up a markdown file into a sequence of blocks,
    /// each of which is either markdown content or a custom HTML element.
    ///
    /// - parameter text: The Markdown string to process.
    /// - parameter customElementNames: A `Set` of HTML tag names which should be processed into custom elements.
    ///     Any HTML tags encountered that aren't specified in the set will be treated as if they were part of the normal markdown text.
    /// - parameter baseUrl: The document's base url.
    public init(processing text: String, customElementNames: Set<String> = [], baseUrl: URL? = nil) throws(ParseError) {
        let parser = Parser(input: text, customElementNames: customElementNames)
        self = try parser.parse(baseUrl: baseUrl)
    }
    
    /// Creates a new Markdown document by processing a `Data` object.
    ///
    /// Note that thie doesn't perform any Markdown parsing on its own; rather, it splits up a markdown file into a sequence of blocks,
    /// each of which is either markdown content or a custom HTML element.
    ///
    /// - parameter data: The Markdown data to process.
    /// - parameter customElementNames: A `Set` of HTML tag names which should be processed into custom elements.
    ///     Any HTML tags encountered that aren't specified in the set will be treated as if they were part of the normal markdown text.
    /// - parameter baseUrl: The document's base url.
    public init(processing data: Data, customElementNames: Set<String> = [], baseUrl: URL? = nil) throws(ParseError) {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ParseError(kind: .nonUTF8Input, sourceLoc: .zero)
        }
        try self.init(processing: text, customElementNames: customElementNames, baseUrl: baseUrl)
    }
    
    /// Creates a new Markdown document by processing the contents of a file.
    ///
    /// Note that thie doesn't perform any Markdown parsing on its own; rather, it splits up a markdown file into a sequence of blocks,
    /// each of which is either markdown content or a custom HTML element.
    ///
    /// - parameter url: The URL of the markdown file to process.
    /// - parameter customElementNames: A `Set` of HTML tag names which should be processed into custom elements.
    ///     Any HTML tags encountered that aren't specified in the set will be treated as if they were part of the normal markdown text.
    /// - parameter baseUrl: The document's base url. If `nil`, `url` will be used instead, with the last path component (the file itself) omitted.
    public init(contentsOf url: URL, customElementNames: Set<String> = [], baseUrl: URL? = nil) throws {
        try self.init(
            processing: Data(contentsOf: url),
            customElementNames: customElementNames,
            baseUrl: baseUrl ?? url.deletingLastPathComponent()
        )
    }
    
    /// Creates a new Markdown document by processing the contents of a file.
    ///
    /// Note that thie doesn't perform any Markdown parsing on its own; rather, it splits up a markdown file into a sequence of blocks,
    /// each of which is either markdown content or a custom HTML element.
    ///
    /// - parameter url: The URL of the markdown file to process.
    /// - parameter customElementNames: A `Set` of HTML tag names which should be processed into custom elements.
    ///     Any HTML tags encountered that aren't specified in the set will be treated as if they were part of the normal markdown text.
    /// - parameter baseUrl: The document's base url. If `nil`, `url` will be used instead, with the last path component (the file itself) omitted
    @_documentation(visibility: internal)
    @available(*, deprecated, renamed: "init(contentsOf:customElementNames:baseUrl:)")
    public init(processingContentsOf url: URL, customElementNames: Set<String> = [], baseUrl: URL? = nil) throws {
        try self.init(contentsOf: url, customElementNames: customElementNames, baseUrl: baseUrl)
    }
}
