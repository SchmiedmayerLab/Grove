//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A JSON document read without losing what the receiver compares: number lexemes stay text.
indirect enum LosslessJSONValue: Equatable {
    case object([String: LosslessJSONValue])
    case array([LosslessJSONValue])
    case string(String)
    case number(String)
    case boolean(Bool)
    case null

    struct ParseError: Error {}

    private struct Parser {
        private static let simpleEscapes: [UInt8: Unicode.Scalar] = [
            UInt8(ascii: "\""): "\"", UInt8(ascii: "\\"): "\\", UInt8(ascii: "/"): "/", UInt8(ascii: "b"): "\u{08}",
            UInt8(ascii: "f"): "\u{0C}", UInt8(ascii: "n"): "\n", UInt8(ascii: "r"): "\r", UInt8(ascii: "t"): "\t"
        ]

        let bytes: [UInt8]
        var index = 0

        var isAtEnd: Bool { index >= bytes.count }

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
                index += 1
            }
        }

        mutating func value() throws(ParseError) -> LosslessJSONValue {
            skipWhitespace()
            guard index < bytes.count else {
                throw ParseError()
            }
            switch bytes[index] {
            case UInt8(ascii: "{"):
                return try object()
            case UInt8(ascii: "["):
                return try array()
            case UInt8(ascii: "\""):
                return .string(try string())
            case UInt8(ascii: "t"):
                try literal("true")
                return .boolean(true)
            case UInt8(ascii: "f"):
                try literal("false")
                return .boolean(false)
            case UInt8(ascii: "n"):
                try literal("null")
                return .null
            default:
                return .number(try number())
            }
        }

        private mutating func object() throws(ParseError) -> LosslessJSONValue {
            index += 1
            var members: [String: LosslessJSONValue] = [:]
            skipWhitespace()
            if try consume(UInt8(ascii: "}")) {
                return .object(members)
            }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                    throw ParseError()
                }
                let key = try string()
                skipWhitespace()
                guard try consume(UInt8(ascii: ":")) else {
                    throw ParseError()
                }
                guard members.updateValue(try value(), forKey: key) == nil else {
                    throw ParseError()
                }
                skipWhitespace()
                if try consume(UInt8(ascii: ",")) {
                    continue
                }
                guard try consume(UInt8(ascii: "}")) else {
                    throw ParseError()
                }
                return .object(members)
            }
        }

        private mutating func array() throws(ParseError) -> LosslessJSONValue {
            index += 1
            var elements: [LosslessJSONValue] = []
            skipWhitespace()
            if try consume(UInt8(ascii: "]")) {
                return .array(elements)
            }
            while true {
                elements.append(try value())
                skipWhitespace()
                if try consume(UInt8(ascii: ",")) {
                    continue
                }
                guard try consume(UInt8(ascii: "]")) else {
                    throw ParseError()
                }
                return .array(elements)
            }
        }

        private mutating func consume(_ byte: UInt8) throws(ParseError) -> Bool {
            guard index < bytes.count else {
                throw ParseError()
            }
            guard bytes[index] == byte else {
                return false
            }
            index += 1
            return true
        }

        private mutating func literal(_ text: String) throws(ParseError) {
            let expected = Array(text.utf8)
            guard bytes.count - index >= expected.count,
                  Array(bytes[index..<(index + expected.count)]) == expected else {
                throw ParseError()
            }
            index += expected.count
        }

        private mutating func number() throws(ParseError) -> String {
            let start = index
            if try consume(UInt8(ascii: "-")) {}
            try digits(allowingLeadingZeroOnly: true)
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                try digits(allowingLeadingZeroOnly: false)
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                    index += 1
                }
                try digits(allowingLeadingZeroOnly: false)
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        private mutating func digits(allowingLeadingZeroOnly: Bool) throws(ParseError) {
            let start = index
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) {
                index += 1
            }
            guard index > start else {
                throw ParseError()
            }
            if allowingLeadingZeroOnly, bytes[start] == 0x30, index - start > 1 {
                throw ParseError()
            }
        }

        private mutating func string() throws(ParseError) -> String {
            index += 1
            var scalars = String.UnicodeScalarView()
            var utf8Run: [UInt8] = []
            func flushRun() throws(ParseError) {
                guard !utf8Run.isEmpty else {
                    return
                }
                guard let text = String(bytes: utf8Run, encoding: .utf8) else {
                    throw ParseError()
                }
                scalars.append(contentsOf: text.unicodeScalars)
                utf8Run.removeAll()
            }
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                switch byte {
                case UInt8(ascii: "\""):
                    try flushRun()
                    return String(scalars)
                case UInt8(ascii: "\\"):
                    try flushRun()
                    scalars.append(try escape())
                case 0x00...0x1F:
                    throw ParseError()
                default:
                    utf8Run.append(byte)
                }
            }
            throw ParseError()
        }

        private mutating func escape() throws(ParseError) -> Unicode.Scalar {
            guard index < bytes.count else {
                throw ParseError()
            }
            let byte = bytes[index]
            index += 1
            if let scalar = Self.simpleEscapes[byte] {
                return scalar
            }
            guard byte == UInt8(ascii: "u") else {
                throw ParseError()
            }
            return try unicodeEscape()
        }

        private mutating func unicodeEscape() throws(ParseError) -> Unicode.Scalar {
            let unit = try codeUnit()
            guard UTF16.isLeadSurrogate(unit) else {
                guard !UTF16.isTrailSurrogate(unit), let scalar = Unicode.Scalar(unit) else {
                    throw ParseError()
                }
                return scalar
            }
            guard try consume(UInt8(ascii: "\\")), try consume(UInt8(ascii: "u")) else {
                throw ParseError()
            }
            let trail = try codeUnit()
            guard UTF16.isTrailSurrogate(trail),
                  let scalar = UTF16.decode(UTF16.EncodedScalar([unit, trail])) as Unicode.Scalar? else {
                throw ParseError()
            }
            return scalar
        }

        private mutating func codeUnit() throws(ParseError) -> UInt16 {
            guard bytes.count - index >= 4,
                  let unit = UInt16(String(decoding: bytes[index..<(index + 4)], as: UTF8.self), radix: 16) else {
                throw ParseError()
            }
            index += 4
            return unit
        }
    }

    init(parsing data: Data) throws(ParseError) {
        var parser = Parser(bytes: Array(data))
        let value = try parser.value()
        parser.skipWhitespace()
        guard parser.isAtEnd else {
            throw ParseError()
        }
        self = value
    }
}


extension ExchangeGraph {
    /// Whether two graphs carry the same JSON tokens.
    ///
    /// Member order, whitespace and string escaping do not matter; a decimal lexeme is compared as
    /// text, so `72` and `72.0` are different content. A retry that is equal under this comparison
    /// is the exact retry the exchange protocol admits.
    public func isSemanticallyEqual(to other: ExchangeGraph) -> Bool {
        guard let lhs = try? LosslessJSONValue(parsing: jsonData),
              let rhs = try? LosslessJSONValue(parsing: other.jsonData) else {
            return false
        }
        return lhs == rhs
    }
}
