//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_length

import Algorithms
import Foundation


extension MarkdownDocument {
    /// An error that occurred when parsing markdown text.
    public struct ParseError: Error, Hashable {
        /// The parse error's kind
        public enum Kind: Hashable, Sendable {
            /// The parse input wasn't encoded as valid UTF-8 text.
            case nonUTF8Input
            /// The parser reached the end of the input file, even though it may have been expecting further content.
            case eof
            /// The parser ran into an unexpected character
            case unexpectedCharacter
            /// Some other issue.
            case other(String)
        }
        
        /// A location within a markdown document, expressed as a line and column number.
        public struct SourceLocation: Hashable, Comparable, Sendable {
            static let zero = Self(line: 0, column: 0)
            
            /// The location's line number, starting at 0.
            public let line: UInt
            /// The location's column number, i.e., its offset within its line, starting at 0.
            public let column: UInt
            
            fileprivate init(line: UInt, column: UInt) {
                self.line = line
                self.column = column
            }
            
            public static func < (lhs: Self, rhs: Self) -> Bool {
                if lhs.line < rhs.line {
                    true
                } else if lhs.line == rhs.line {
                    lhs.column < rhs.column
                } else {
                    false
                }
            }
        }
        
        /// The specific kind of error
        public let kind: Kind
        /// The source location at which the error occurred
        public let sourceLoc: SourceLocation
    }
}


extension MarkdownDocument {
    struct Parser: ~Copyable {
        typealias ParseError = MarkdownDocument.ParseError
        typealias CustomElement = MarkdownDocument.CustomElement
        
        private let input: String
        private let customElementNames: Set<String>
        private var position: String.Index
        
        init(input: String, customElementNames: Set<String>) {
            self.input = input
            self.customElementNames = customElementNames
            self.position = input.startIndex
        }
    }
}


extension MarkdownDocument.Parser {
    consuming func parse(baseUrl: URL?) throws(ParseError) -> MarkdownDocument { // swiftlint:disable:this function_body_length cyclomatic_complexity
        typealias Block = MarkdownDocument.Block
        let frontmatter = try parseFrontmatter()
        var blocks: [Block] = []
        var currentBlockText = ""
        func terminateCurrentBlock(id: String? = nil) {
            blocks.append(.markdown(
                id: id ?? Self.markdownBlockId(currentBlockText),
                rawContents: currentBlockText
            ))
            currentBlockText.removeAll(keepingCapacity: true)
        }
        do {
            while let currentChar {
                if isAtBeginningOfLine, Self.markdownBlockId(remainingInput) != nil {
                    // terminate current block, if we're at the start of a new one whith would get an id of its own.
                    terminateCurrentBlock()
                }
                if currentChar == "<", isAtBeginningOfLine,
                   let element = try parseCustomElement() {
                    if customElementNames.contains(element.name) {
                        terminateCurrentBlock()
                        blocks.append(.customElement(element))
                    } else {
                        // continue parsing as if this were normal markdown; the downstream markdown parser will have to deal w/ this.
                        currentBlockText.append(element.raw)
                    }
                } else if try skipCommentIfApplicable() {
                    // we ignore the comment
                } else {
                    currentBlockText.append(currentChar)
                    consume()
                }
            }
        } catch {
            switch error.kind {
            case .eof:
                break
            default:
                throw error
            }
        }
        terminateCurrentBlock()
        blocks = blocks.compactMap { block -> Block? in
            switch block {
            case let .markdown(id, rawContents):
                let trimmed = rawContents.trimmingWhitespace()
                if trimmed.isEmpty {
                    return nil
                } else {
                    return .markdown(id: id, rawContents: String(trimmed))
                }
            case .customElement:
                return block
            }
        }
        return MarkdownDocument(metadata: .init(frontmatter), blocks: blocks, baseUrl: baseUrl)
    }
    
    
    mutating func parseFrontmatter() throws(ParseError) -> [String: String] {
        guard currentLine == "---" else {
            return [:]
        }
        var frontmatter: [String: String] = [:]
        consumeLine()
        while let key = try? parseIdentifier() {
            try expectAndConsume(":")
            consume(while: { $0.isWhitespace && !$0.isNewline })
            guard let value = currentLine else {
                try emitError(.eof)
            }
            consumeLine()
            frontmatter[key] = String(value)
            while let currentLine, currentLine.isEmpty {
                consumeLine()
            }
        }
        guard currentLine == "---" else {
            try emitError(.other("Unable to find end of frontmatter"))
        }
        consumeLine()
        return frontmatter
    }
    
    
    private mutating func parseIdentifier() throws(ParseError) -> String {
        var identifier = ""
        if let currentChar, currentChar.isValidIdentStart {
            identifier.append(currentChar)
            consume()
        } else {
            try emitError(.unexpectedCharacter)
        }
        while let currentChar, currentChar.isValidIdent {
            identifier.append(currentChar)
            consume()
        }
        return identifier
    }
    
    private mutating func parseInteger() -> Int? {
        let initialPos = position
        var value = 0
        let negative: Bool
        if let currentChar, currentChar == "-" {
            negative = true
            consume()
        } else {
            negative = false
        }
        let posFirstPotentialDigit = position
        while let currentChar, currentChar.isASCII, let digit = currentChar.wholeNumberValue {
            value *= 10
            value += digit
            consume()
        }
        if position == posFirstPotentialDigit {
            // if we weren't able to read any digits, we restore the initial position and return nil
            position = initialPos
            return nil
        } else {
            // otherwise, we were able to parse a value, and will return that.
            return value * (negative ? -1 : 1)
        }
    }
    
    
    private mutating func parseAttrValue() throws(ParseError) -> String {
        if currentChar == "\"" {
            try parseStringLiteral()
        } else if let ident = try? parseIdentifier() {
            ident
        } else if let value = parseInteger() {
            String(value)
        } else {
            ""
        }
    }
    
    
    private mutating func parseStringLiteral() throws(ParseError) -> String {
        try expectAndConsume("\"")
        var text = ""
        while true {
            guard let currentChar else {
                try emitError(.eof)
            }
            let isEscaped = !text.suffix { $0 == #"\"# }.count.isMultiple(of: 2)
            if currentChar == "\"" && !isEscaped {
                break
            }
            consume()
            text.append(currentChar)
        }
        try expectAndConsume("\"")
        return text
    }
    
    
    private mutating func parseCustomElement() throws(ParseError) -> CustomElement? {
        // swiftlint:disable:previous function_body_length cyclomatic_complexity
        consume(while: \.isWhitespace)
        let startPos = self.position
        guard currentChar == "<", let next = peek(), next.isValidIdentStart else {
            return nil
        }
        try expectAndConsume("<")
        let name = try parseIdentifier()
        var parsedElement = CustomElement(name: name, raw: "")
        var elementIsClosed = false
        // parse the opening tag of the custom element
        loop: while true {
            switch currentChar {
            case .none:
                break loop
            case ">":
                // end of opening tag
                consume()
                break loop
            case "/" where peek() == ">":
                // upcoming end of opening tag
                consume(2)
                elementIsClosed = true
                break loop
            case .some(let char) where char.isWhitespace:
                // whitespace/newlines between things
                consume()
            case .some:
                let attrName = try parseIdentifier()
                let attrValue: String
                if currentChar == "=" {
                    consume()
                    attrValue = try parseAttrValue()
                } else {
                    // attr w/out a value
                    attrValue = ""
                }
                parsedElement.attributes.append(.init(name: attrName, value: attrValue))
            }
        }
        if elementIsClosed {
            parsedElement.raw = String(input[startPos..<position])
            return parsedElement
        }
        if let element = _attemptToCloseCustomElement(parsedElement, elementStartPos: startPos) {
            return element
        } else {
            while true {
                if let element = try parseCustomElement() {
                    if customElementNames.contains(element.name) {
                        parsedElement.content.append(.element(element))
                    } else {
                        parsedElement.content.append(.text(element.raw))
                    }
                } else {
                    let text = parseElementTextContents().trimmingWhitespace()
                    if !text.isEmpty {
                        parsedElement.content.append(.text(String(text)))
                    } else {
                        // unable to parse an element, but also no text-only content in there...
                        if let element = _attemptToCloseCustomElement(parsedElement, elementStartPos: startPos) {
                            return element
                        } else {
                            try emitError(.other("unable to close \(name)"))
                        }
                    }
                }
            }
        }
        try emitError(.other("Unable to find closing tag for \(parsedElement)"))
    }
    
    private mutating func _attemptToCloseCustomElement(_ element: CustomElement, elementStartPos: String.Index) -> CustomElement? {
        let possibleClosingTags = ["</>", "</\(element.name)>"]
        for tag in possibleClosingTags {
            if remainingInput.starts(with: tag) { // swiftlint:disable:this for_where
                consume(tag.count)
                var element = element
                element.raw = String(input[elementStartPos..<position])
                return element
            }
        }
        return nil
    }
    
    
    /// Parses the `{X}` part in `<element>{X}</element>`.
    private mutating func parseElementTextContents() -> String {
        var text = ""
        while let currentChar, currentChar != "<" {
            text.append(currentChar)
            consume()
        }
        return text.trimmingWhitespace()
    }
    
    
    /// Parses an HTML comment starting at the current position.
    ///
    /// Since HTML doesn't support nested comments, this function in effect simply consumes all text until the next `-->` character sequence.
    ///
    /// - returns: the contents of the parsed comment, excluding the leading `<!--` and the trailing `-->`.
    ///     if no comment starts at the current position, the function returns `nil`.
    private mutating func parseComment() throws(ParseError) -> String? {
        guard remainingInput.starts(with: "<!--") else {
            return nil
        }
        consume(4)
        var commentBody = ""
        while let currentChar {
            if remainingInput.starts(with: "-->") {
                consume(3)
                return commentBody
            } else {
                commentBody.append(currentChar)
                consume()
            }
        }
        // we ran out of characters before closing the comment.
        try emitError(.other("Unterminated Comment"))
    }
    
    
    /// Skips a comment, if one starts at the current position
    ///
    /// - returns: `true` iff a comment was skipped, `false` otherwise.
    @discardableResult
    private mutating func skipCommentIfApplicable() throws(ParseError) -> Bool {
        try parseComment() != nil
    }
}

extension MarkdownDocument.Parser {
    private func emitError(_ kind: ParseError.Kind) throws(ParseError) -> Never {
        throw .init(kind: kind, sourceLoc: currentSourceLoc)
    }
}


extension MarkdownDocument.Parser {
    private var currentChar: Character? {
        input[safe: position]
    }
    
    private var remainingInput: Substring {
        input[position...]
    }
    
    private var currentLine: Substring? {
        remainingInput.isEmpty ? nil : remainingInput.prefix { !$0.isNewline }
    }
    
    private var isAtBeginningOfLine: Bool {
        position == input.startIndex && position < input.endIndex || input[input.index(before: position)].isNewline
    }
    
    private func peek(_ offset: Int = 1) -> Character? {
        input[safe: input.index(position, offsetBy: offset)]
    }
    
    private mutating func consume(_ count: Int = 1) {
        guard count > 0 else {
            return
        }
        let newIndex = input.index(position, offsetBy: count)
        position = min(input.endIndex, newIndex)
    }
    
    private mutating func consume(while predicate: (Character) -> Bool) {
        while let currentChar, predicate(currentChar) {
            consume()
        }
    }
    
    private mutating func expectAndConsume(_ char: Character) throws(ParseError) {
        guard currentChar == char else {
            try emitError(.unexpectedCharacter)
        }
        consume()
    }
    
    /// Consumes all upcoming characters up to (and including) the next newline character.
    private mutating func consumeLine() {
        while let currentChar, !currentChar.isNewline {
            consume()
        }
        if currentChar?.isNewline == true {
            consume()
        }
    }
}


extension MarkdownDocument.Parser {
    private var currentSourceLoc: ParseError.SourceLocation {
        let lineNumber = input[..<position].count(where: \.isNewline)
        let wholeCurrentLine = { () -> Substring in
            let startIdx = input[..<position].lastIndex(where: \.isNewline).map { input.index(after: $0) }
            let endIdx = remainingInput.firstIndex(where: \.isNewline)
            return switch (startIdx, endIdx) {
            case (nil, nil):
                input[...]
            case let (.some(startIdx), .none):
                input[startIdx...]
            case let (.none, .some(endIdx)):
                input[...endIdx]
            case let (.some(startIdx), .some(endIdx)):
                input[startIdx...endIdx]
            }
        }()
        return .init(
            line: UInt(lineNumber),
            column: UInt(wholeCurrentLine.distance(from: wholeCurrentLine.startIndex, to: position))
        )
    }
}


extension MarkdownDocument.Parser {
    /// Attempts to determine a suitable id for a markdown block with the specified content.
    ///
    /// The id produced here is not necessarily suitable for uniquely identifying the block within a ``MarkdownDocument``;
    /// rather we match the behaviour of e.g. GitHub, which turn headings into hyphen-separated identifiers.
    fileprivate static func markdownBlockId(_ content: some StringProtocol) -> String? {
        func makeId(title: some StringProtocol) -> String? {
            let title = title.trimmingWhitespace()
            let isValidChar = { (char: Character) in
                char.isASCII && char.isLetter
            }
            return if title.isEmpty {
                nil
            } else {
                title.lazy
                    .map { $0.asciiLowercased ?? $0 }
                    .trimming { !isValidChar($0) }
                    .reduce(into: "") { id, char in
                        id.append(isValidChar(char) ? char : "-")
                    }
            }
        }
        
        // a heading can take either of the two following forms: (https://daringfireball.net/projects/markdown/syntax#header)
        // ```markdown
        // # This is my heading
        // ```
        //
        // ```markdown
        // This is my heading
        // ==================
        // ```
        if content.starts(with: "#") {
            let fstLineEnd = content.firstIndex(where: \.isNewline) ?? content.endIndex
            let fstLine = content[..<fstLineEnd]
            guard let headingTitleStart = fstLine.firstIndex(of: " ").flatMap({ fstLine.index($0, offsetBy: 1, limitedBy: fstLine.endIndex) }) else {
                return nil
            }
            let headingTitle = fstLine[headingTitleStart..<fstLineEnd]
            return makeId(title: headingTitle)
        } else {
            guard let fstLineEnd = content.firstIndex(where: \.isNewline) else {
                return nil
            }
            let sndLineEnd = content[content.index(after: fstLineEnd)...].firstIndex(where: \.isNewline) ?? content.endIndex
            let fstLine = content[..<fstLineEnd]
            let sndLine = content[content.index(after: fstLineEnd)..<sndLineEnd]
            if !sndLine.isEmpty && (sndLine.allSatisfy { $0 == "=" } || sndLine.allSatisfy { $0 == "-" }) {
                return makeId(title: fstLine)
            } else {
                return nil
            }
        }
    }
}


extension Character {
    fileprivate var isValidIdentStart: Bool {
        (self >= "a" && self <= "z") || (self >= "A" && self <= "Z") || self == "_"
    }
    
    fileprivate var isValidIdent: Bool {
        isValidIdentStart || (self >= "0" && self <= "9") || self == "-"
    }
    
    fileprivate var asciiLowercased: Character? {
        guard let asciiValue, self >= "A" && self <= "Z" else {
            return nil
        }
        return Character(Unicode.Scalar(asciiValue + 32))
    }
}
